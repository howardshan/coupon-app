-- ============================================================
-- Commission 与 Stripe Fee 分离计算
--
-- 问题：旧版 RPC 把 15% 统一作为 platform_fee，
-- 没有单独计算 Stripe 手续费（stripe_fee 始终为 0）。
--
-- 修复：
--   - commission = unit_price × effective_commission_rate（纯平台抽佣）
--   - stripe_fee = unit_price × stripe_rate + flat_fee（单独算）
--   - net_amount = unit_price - commission - stripe_fee
--
-- 费率来源：platform_commission_config（全局）→ merchants（商家覆盖）
-- ============================================================


-- =============================================================
-- 1. get_merchant_transactions — 加入 stripe_fee 独立计算
-- =============================================================
DROP FUNCTION IF EXISTS public.get_merchant_transactions(uuid, date, date, int, int);

CREATE FUNCTION public.get_merchant_transactions(
  p_merchant_id uuid,
  p_date_from   date    DEFAULT NULL,
  p_date_to     date    DEFAULT NULL,
  p_page        int     DEFAULT 1,
  p_per_page    int     DEFAULT 20
)
RETURNS TABLE(
  order_id          uuid,
  deal_title        text,
  validity_type     text,
  amount            numeric,
  platform_fee_rate numeric,
  platform_fee      numeric,
  stripe_fee        numeric,
  net_amount        numeric,
  status            text,
  created_at        timestamptz,
  total_count       bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_commission_rate     numeric;
  v_stripe_rate         numeric;
  v_stripe_flat_fee     numeric;
  v_is_free             boolean;
  -- 商家自定义费率
  v_m_commission_rate   numeric;
  v_m_stripe_rate       numeric;
  v_m_stripe_flat_fee   numeric;
  v_m_free_until        timestamptz;
  v_m_eff_from          date;
  v_m_eff_to            date;
  v_merchant_active     boolean := false;
BEGIN
  -- 读取全局费率
  SELECT
    COALESCE(c.commission_rate, 0.15),
    COALESCE(c.stripe_processing_rate, 0.03),
    COALESCE(c.stripe_flat_fee, 0.30)
  INTO v_commission_rate, v_stripe_rate, v_stripe_flat_fee
  FROM platform_commission_config c
  LIMIT 1;

  -- 读取商家自定义费率
  SELECT
    m.commission_rate,
    m.commission_stripe_rate,
    m.commission_stripe_flat_fee,
    m.commission_free_until,
    m.commission_effective_from,
    m.commission_effective_to
  INTO v_m_commission_rate, v_m_stripe_rate, v_m_stripe_flat_fee,
       v_m_free_until, v_m_eff_from, v_m_eff_to
  FROM merchants m
  WHERE m.id = p_merchant_id;

  -- 判断免费期
  v_is_free := (v_m_free_until IS NOT NULL AND NOW() <= v_m_free_until);

  -- 判断商家自定义费率是否生效
  IF v_m_commission_rate IS NOT NULL OR v_m_stripe_rate IS NOT NULL THEN
    IF v_m_eff_from IS NULL AND v_m_eff_to IS NULL THEN
      v_merchant_active := true;
    ELSIF v_m_eff_from IS NOT NULL AND v_m_eff_to IS NOT NULL THEN
      v_merchant_active := CURRENT_DATE BETWEEN v_m_eff_from AND v_m_eff_to;
    ELSIF v_m_eff_from IS NOT NULL THEN
      v_merchant_active := CURRENT_DATE >= v_m_eff_from;
    ELSIF v_m_eff_to IS NOT NULL THEN
      v_merchant_active := CURRENT_DATE <= v_m_eff_to;
    END IF;
  END IF;

  -- 最终生效费率
  IF v_merchant_active AND v_m_commission_rate IS NOT NULL THEN
    v_commission_rate := v_m_commission_rate;
  END IF;
  IF v_merchant_active AND v_m_stripe_rate IS NOT NULL THEN
    v_stripe_rate := v_m_stripe_rate;
  END IF;
  IF v_merchant_active AND v_m_stripe_flat_fee IS NOT NULL THEN
    v_stripe_flat_fee := v_m_stripe_flat_fee;
  END IF;

  -- 免费期内 commission = 0（Stripe 费仍需支付）
  IF v_is_free THEN
    v_commission_rate := 0;
  END IF;

  RETURN QUERY
  SELECT
    oi.order_id                                          AS order_id,
    COALESCE(d.title, '')::text                          AS deal_title,
    COALESCE(d.validity_type, 'fixed_date')::text        AS validity_type,
    oi.unit_price                                        AS amount,
    v_commission_rate                                    AS platform_fee_rate,
    ROUND(oi.unit_price * v_commission_rate, 2)          AS platform_fee,
    ROUND(oi.unit_price * v_stripe_rate + v_stripe_flat_fee, 2) AS stripe_fee,
    ROUND(oi.unit_price
      - oi.unit_price * v_commission_rate
      - (oi.unit_price * v_stripe_rate + v_stripe_flat_fee), 2) AS net_amount,
    oi.customer_status::text                             AS status,
    oi.redeemed_at                                       AS created_at,
    COUNT(*) OVER ()                                     AS total_count
  FROM order_items oi
  JOIN deals d ON d.id = oi.deal_id
  WHERE oi.redeemed_at IS NOT NULL
    AND COALESCE(oi.redeemed_merchant_id, oi.purchased_merchant_id) = p_merchant_id
    AND oi.customer_status NOT IN ('refund_success')
    AND (p_date_from IS NULL OR date(oi.redeemed_at) >= p_date_from)
    AND (p_date_to   IS NULL OR date(oi.redeemed_at) <= p_date_to)
  ORDER BY oi.redeemed_at DESC
  LIMIT p_per_page
  OFFSET (p_page - 1) * p_per_page;
END;
$$;


-- =============================================================
-- 2. get_merchant_report_data — 加入 stripe_fee 独立计算
-- =============================================================
DROP FUNCTION IF EXISTS public.get_merchant_report_data(uuid, date, date);

CREATE FUNCTION public.get_merchant_report_data(
  p_merchant_id uuid,
  p_date_from   date,
  p_date_to     date
)
RETURNS TABLE(
  report_date   date,
  order_count   bigint,
  gross_amount  numeric,
  platform_fee  numeric,
  stripe_fee    numeric,
  net_amount    numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_commission_rate     numeric;
  v_stripe_rate         numeric;
  v_stripe_flat_fee     numeric;
  v_is_free             boolean;
  v_m_commission_rate   numeric;
  v_m_stripe_rate       numeric;
  v_m_stripe_flat_fee   numeric;
  v_m_free_until        timestamptz;
  v_m_eff_from          date;
  v_m_eff_to            date;
  v_merchant_active     boolean := false;
BEGIN
  -- 读取全局费率
  SELECT
    COALESCE(c.commission_rate, 0.15),
    COALESCE(c.stripe_processing_rate, 0.03),
    COALESCE(c.stripe_flat_fee, 0.30)
  INTO v_commission_rate, v_stripe_rate, v_stripe_flat_fee
  FROM platform_commission_config c
  LIMIT 1;

  -- 读取商家自定义费率
  SELECT
    m.commission_rate,
    m.commission_stripe_rate,
    m.commission_stripe_flat_fee,
    m.commission_free_until,
    m.commission_effective_from,
    m.commission_effective_to
  INTO v_m_commission_rate, v_m_stripe_rate, v_m_stripe_flat_fee,
       v_m_free_until, v_m_eff_from, v_m_eff_to
  FROM merchants m
  WHERE m.id = p_merchant_id;

  -- 判断免费期
  v_is_free := (v_m_free_until IS NOT NULL AND NOW() <= v_m_free_until);

  -- 判断商家自定义费率是否生效
  IF v_m_commission_rate IS NOT NULL OR v_m_stripe_rate IS NOT NULL THEN
    IF v_m_eff_from IS NULL AND v_m_eff_to IS NULL THEN
      v_merchant_active := true;
    ELSIF v_m_eff_from IS NOT NULL AND v_m_eff_to IS NOT NULL THEN
      v_merchant_active := CURRENT_DATE BETWEEN v_m_eff_from AND v_m_eff_to;
    ELSIF v_m_eff_from IS NOT NULL THEN
      v_merchant_active := CURRENT_DATE >= v_m_eff_from;
    ELSIF v_m_eff_to IS NOT NULL THEN
      v_merchant_active := CURRENT_DATE <= v_m_eff_to;
    END IF;
  END IF;

  IF v_merchant_active AND v_m_commission_rate IS NOT NULL THEN
    v_commission_rate := v_m_commission_rate;
  END IF;
  IF v_merchant_active AND v_m_stripe_rate IS NOT NULL THEN
    v_stripe_rate := v_m_stripe_rate;
  END IF;
  IF v_merchant_active AND v_m_stripe_flat_fee IS NOT NULL THEN
    v_stripe_flat_fee := v_m_stripe_flat_fee;
  END IF;

  IF v_is_free THEN
    v_commission_rate := 0;
  END IF;

  RETURN QUERY
  SELECT
    date(oi.redeemed_at) AS report_date,
    COUNT(*)             AS order_count,
    COALESCE(SUM(oi.unit_price), 0) AS gross_amount,
    COALESCE(ROUND(SUM(oi.unit_price * v_commission_rate), 2), 0) AS platform_fee,
    COALESCE(ROUND(SUM(oi.unit_price * v_stripe_rate + v_stripe_flat_fee), 2), 0) AS stripe_fee,
    COALESCE(ROUND(SUM(
      oi.unit_price
      - oi.unit_price * v_commission_rate
      - (oi.unit_price * v_stripe_rate + v_stripe_flat_fee)
    ), 2), 0) AS net_amount
  FROM order_items oi
  WHERE oi.redeemed_at IS NOT NULL
    AND COALESCE(oi.redeemed_merchant_id, oi.purchased_merchant_id) = p_merchant_id
    AND oi.customer_status NOT IN ('refund_success')
    AND date(oi.redeemed_at) BETWEEN p_date_from AND p_date_to
  GROUP BY date(oi.redeemed_at)
  ORDER BY date(oi.redeemed_at) ASC;
END;
$$;


-- =============================================================
-- 3. get_merchant_earnings_summary — 分离 commission 和 stripe fee
-- =============================================================
DROP FUNCTION IF EXISTS public.get_merchant_earnings_summary(uuid, date);

CREATE FUNCTION public.get_merchant_earnings_summary(
  p_merchant_id uuid,
  p_month_start date
)
RETURNS TABLE(
  total_revenue      numeric,
  pending_settlement numeric,
  settled_amount     numeric,
  refunded_amount    numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_month_end           date;
  v_settlement_cutoff   timestamptz;
  v_commission_rate     numeric;
  v_stripe_rate         numeric;
  v_stripe_flat_fee     numeric;
  v_is_free             boolean;
  v_m_commission_rate   numeric;
  v_m_stripe_rate       numeric;
  v_m_stripe_flat_fee   numeric;
  v_m_free_until        timestamptz;
  v_m_eff_from          date;
  v_m_eff_to            date;
  v_merchant_active     boolean := false;
BEGIN
  v_month_end := (p_month_start + INTERVAL '1 month - 1 day')::date;
  v_settlement_cutoff := now() - INTERVAL '7 days';

  -- 读取全局费率
  SELECT
    COALESCE(c.commission_rate, 0.15),
    COALESCE(c.stripe_processing_rate, 0.03),
    COALESCE(c.stripe_flat_fee, 0.30)
  INTO v_commission_rate, v_stripe_rate, v_stripe_flat_fee
  FROM platform_commission_config c
  LIMIT 1;

  -- 读取商家自定义费率
  SELECT
    m.commission_rate,
    m.commission_stripe_rate,
    m.commission_stripe_flat_fee,
    m.commission_free_until,
    m.commission_effective_from,
    m.commission_effective_to
  INTO v_m_commission_rate, v_m_stripe_rate, v_m_stripe_flat_fee,
       v_m_free_until, v_m_eff_from, v_m_eff_to
  FROM merchants m
  WHERE m.id = p_merchant_id;

  v_is_free := (v_m_free_until IS NOT NULL AND NOW() <= v_m_free_until);

  IF v_m_commission_rate IS NOT NULL OR v_m_stripe_rate IS NOT NULL THEN
    IF v_m_eff_from IS NULL AND v_m_eff_to IS NULL THEN
      v_merchant_active := true;
    ELSIF v_m_eff_from IS NOT NULL AND v_m_eff_to IS NOT NULL THEN
      v_merchant_active := CURRENT_DATE BETWEEN v_m_eff_from AND v_m_eff_to;
    ELSIF v_m_eff_from IS NOT NULL THEN
      v_merchant_active := CURRENT_DATE >= v_m_eff_from;
    ELSIF v_m_eff_to IS NOT NULL THEN
      v_merchant_active := CURRENT_DATE <= v_m_eff_to;
    END IF;
  END IF;

  IF v_merchant_active AND v_m_commission_rate IS NOT NULL THEN
    v_commission_rate := v_m_commission_rate;
  END IF;
  IF v_merchant_active AND v_m_stripe_rate IS NOT NULL THEN
    v_stripe_rate := v_m_stripe_rate;
  END IF;
  IF v_merchant_active AND v_m_stripe_flat_fee IS NOT NULL THEN
    v_stripe_flat_fee := v_m_stripe_flat_fee;
  END IF;

  IF v_is_free THEN
    v_commission_rate := 0;
  END IF;

  RETURN QUERY
  SELECT
    -- 本月核销收入（已核销且非退款）
    COALESCE((
      SELECT SUM(oi.unit_price)
      FROM order_items oi
      WHERE oi.redeemed_at IS NOT NULL
        AND date(oi.redeemed_at) BETWEEN p_month_start AND v_month_end
        AND oi.customer_status NOT IN ('refund_success', 'refund_pending')
        AND COALESCE(oi.redeemed_merchant_id, oi.purchased_merchant_id) = p_merchant_id
    ), 0)::numeric AS total_revenue,

    -- 待结算：已核销但不足 7 天，商家实收部分（扣除 commission + stripe fee）
    COALESCE((
      SELECT SUM(
        oi.unit_price
        - oi.unit_price * v_commission_rate
        - (oi.unit_price * v_stripe_rate + v_stripe_flat_fee)
      )
      FROM order_items oi
      WHERE oi.redeemed_at IS NOT NULL
        AND oi.redeemed_at > v_settlement_cutoff
        AND date(oi.redeemed_at) BETWEEN p_month_start AND v_month_end
        AND oi.customer_status = 'used'
        AND COALESCE(oi.redeemed_merchant_id, oi.purchased_merchant_id) = p_merchant_id
    ), 0)::numeric AS pending_settlement,

    -- 已结算
    COALESCE((
      SELECT SUM(s.net_amount)
      FROM settlements s
      WHERE s.merchant_id = p_merchant_id
        AND s.status = 'paid'
        AND s.period_start >= p_month_start
        AND s.period_end <= v_month_end
    ), 0)::numeric AS settled_amount,

    -- 退款金额
    COALESCE((
      SELECT SUM(oi.unit_price)
      FROM order_items oi
      WHERE oi.customer_status = 'refund_success'
        AND oi.refunded_at IS NOT NULL
        AND date(oi.refunded_at) BETWEEN p_month_start AND v_month_end
        AND COALESCE(oi.redeemed_merchant_id, oi.purchased_merchant_id) = p_merchant_id
    ), 0)::numeric AS refunded_amount;
END;
$$;


-- =============================================================
-- 4. 权限授予
-- =============================================================
GRANT EXECUTE ON FUNCTION public.get_merchant_transactions(uuid, date, date, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_merchant_report_data(uuid, date, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_merchant_earnings_summary(uuid, date) TO authenticated;
