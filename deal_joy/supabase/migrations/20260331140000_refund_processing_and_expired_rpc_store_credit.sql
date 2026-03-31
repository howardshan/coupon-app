-- =============================================================
-- refund_processing：Stripe 退款已发起、等 webhook（不入「待人工审核」队列）
-- get_expired_order_items：增加 orders.store_credit_used 供自动退款 SC/卡拆分
-- 收入/待办 RPC：将 refund_processing 与 refund_pending 同等视为「非有效营收」
-- 数据：refunded_at IS NULL 的 refund_pending → refund_processing（等款到账）
-- =============================================================

DO $$ BEGIN
  ALTER TYPE public.customer_item_status ADD VALUE 'refund_processing';
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TYPE public.customer_item_status IS
  'unused/used/expired/refund_pending(legacy)/refund_processing(等 Stripe webhook)/refund_review/refund_reject/refund_success/gifted';

-- ─── get_expired_order_items：DROP + CREATE（返回列变更）────────────────
DROP FUNCTION IF EXISTS public.get_expired_order_items(int);

CREATE FUNCTION public.get_expired_order_items(
  p_limit int DEFAULT 50
)
RETURNS TABLE (
  id                   uuid,
  order_id             uuid,
  user_id              uuid,
  unit_price           numeric,
  service_fee          numeric,
  tax_amount           numeric,
  coupon_id            uuid,
  expires_at           timestamptz,
  stripe_charge_id     text,
  payment_intent_id    text,
  store_credit_used    numeric,
  customer_status      text,
  deal_id              uuid
)
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT
    oi.id,
    oi.order_id,
    o.user_id,
    oi.unit_price,
    oi.service_fee,
    COALESCE(oi.tax_amount, 0) AS tax_amount,
    c.id                      AS coupon_id,
    c.expires_at,
    o.stripe_charge_id,
    o.payment_intent_id,
    COALESCE(o.store_credit_used, 0) AS store_credit_used,
    oi.customer_status::text,
    oi.deal_id
  FROM public.order_items oi
  JOIN public.coupons c ON c.order_item_id = oi.id
  JOIN public.orders  o ON o.id = oi.order_id
  WHERE oi.customer_status IN ('unused', 'gifted')
    AND c.expires_at < now()
  ORDER BY c.expires_at ASC
  LIMIT p_limit;
$$;

REVOKE ALL ON FUNCTION public.get_expired_order_items(int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_expired_order_items(int) TO service_role;

COMMENT ON FUNCTION public.get_expired_order_items(int) IS
  '供 auto-refund-expired：过期未用/转赠券；含 Stripe、税额、store_credit_used。';

-- 历史数据回填见 20260331140100（须单独事务：ADD VALUE 后同事务内不能使用新枚举值）

-- ─── Dashboard：今日统计（以 25000001 为准，增加 refund_processing）────
DROP FUNCTION IF EXISTS public.get_merchant_daily_stats(uuid);

CREATE FUNCTION public.get_merchant_daily_stats(p_merchant_id uuid)
RETURNS TABLE(
  today_orders      bigint,
  today_redemptions bigint,
  today_revenue     numeric,
  pending_coupons   bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    (
      SELECT COUNT(*)
      FROM order_items oi
      JOIN orders o ON o.id = oi.order_id
      WHERE (
              oi.purchased_merchant_id = p_merchant_id
              OR p_merchant_id = ANY(oi.applicable_store_ids)
            )
        AND o.created_at >= CURRENT_DATE
        AND o.created_at <  CURRENT_DATE + INTERVAL '1 day'
        AND oi.customer_status NOT IN ('refund_success')
    )::bigint AS today_orders,

    (
      SELECT COUNT(*)
      FROM order_items oi
      WHERE (
              oi.purchased_merchant_id = p_merchant_id
              OR p_merchant_id = ANY(oi.applicable_store_ids)
            )
        AND oi.redeemed_at >= CURRENT_DATE
        AND oi.redeemed_at <  CURRENT_DATE + INTERVAL '1 day'
    )::bigint AS today_redemptions,

    (
      SELECT COALESCE(SUM(oi.unit_price), 0)
      FROM order_items oi
      JOIN orders o ON o.id = oi.order_id
      WHERE (
              oi.purchased_merchant_id = p_merchant_id
              OR p_merchant_id = ANY(oi.applicable_store_ids)
            )
        AND o.created_at >= CURRENT_DATE
        AND o.created_at <  CURRENT_DATE + INTERVAL '1 day'
        AND oi.customer_status NOT IN ('refund_success', 'refund_pending', 'refund_processing')
    ) AS today_revenue,

    (
      SELECT COUNT(*)
      FROM order_items oi
      WHERE (
              oi.purchased_merchant_id = p_merchant_id
              OR p_merchant_id = ANY(oi.applicable_store_ids)
            )
        AND oi.customer_status = 'unused'
    )::bigint AS pending_coupons;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_merchant_daily_stats(uuid) TO authenticated;

-- ─── 周趋势：收入排除处理中与已完成退款 ─────────────────────────────
DROP FUNCTION IF EXISTS public.get_merchant_weekly_trend(uuid);

CREATE FUNCTION public.get_merchant_weekly_trend(p_merchant_id uuid)
RETURNS TABLE(
  trend_date    date,
  daily_orders  bigint,
  daily_revenue numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    gs.day::date                               AS trend_date,
    COALESCE(COUNT(oi.id), 0)::bigint          AS daily_orders,
    COALESCE(SUM(oi.unit_price), 0)            AS daily_revenue
  FROM
    generate_series(
      CURRENT_DATE - INTERVAL '6 days',
      CURRENT_DATE,
      INTERVAL '1 day'
    ) AS gs(day)
  LEFT JOIN order_items oi
    ON oi.created_at >= gs.day
    AND oi.created_at <  gs.day + INTERVAL '1 day'
    AND oi.customer_status NOT IN ('refund_success', 'refund_pending', 'refund_processing')
    AND (
      oi.purchased_merchant_id = p_merchant_id
      OR p_merchant_id = ANY(oi.applicable_store_ids)
    )
  GROUP BY gs.day
  ORDER BY gs.day DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_merchant_weekly_trend(uuid) TO authenticated;

-- ─── 待办：仅统计需人工审核的 refund_review（不含等 webhook）──────────
DROP FUNCTION IF EXISTS public.get_merchant_todos(uuid);

CREATE FUNCTION public.get_merchant_todos(p_merchant_id uuid)
RETURNS TABLE(
  pending_reviews      bigint,
  pending_refunds      bigint,
  influencer_requests  bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    (
      SELECT COUNT(*)
      FROM reviews r
      JOIN deals d ON d.id = r.deal_id
      WHERE d.merchant_id = p_merchant_id
    )::bigint AS pending_reviews,

    (
      SELECT COUNT(*)
      FROM order_items oi
      WHERE (
              oi.purchased_merchant_id = p_merchant_id
              OR p_merchant_id = ANY(oi.applicable_store_ids)
            )
        AND oi.customer_status = 'refund_review'
    )::bigint AS pending_refunds,

    0::bigint AS influencer_requests;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_merchant_todos(uuid) TO authenticated;

-- ─── 品牌佣金相关 RPC：NOT IN 增加 refund_processing ─────────────────
CREATE OR REPLACE FUNCTION public.get_merchant_transactions(
  p_merchant_id UUID,
  p_date_from   DATE DEFAULT NULL,
  p_date_to     DATE DEFAULT NULL,
  p_page        INT  DEFAULT 1,
  p_per_page    INT  DEFAULT 20
)
RETURNS TABLE (
  order_id          UUID,
  order_item_id     UUID,
  deal_title        TEXT,
  validity_type     TEXT,
  amount            NUMERIC,
  platform_fee_rate DECIMAL,
  platform_fee      NUMERIC,
  brand_fee_rate    DECIMAL,
  brand_fee         NUMERIC,
  stripe_fee        NUMERIC,
  net_amount        NUMERIC,
  status            TEXT,
  created_at        TIMESTAMPTZ,
  total_count       BIGINT
)
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  g_rate        DECIMAL;
  g_stripe_rate DECIMAL;
  g_stripe_flat DECIMAL;
  m_rate        DECIMAL;
  m_stripe_rate DECIMAL;
  m_stripe_flat DECIMAL;
  m_eff_from    DATE;
  m_eff_to      DATE;
  v_rate        DECIMAL;
  v_stripe_rate DECIMAL;
  v_stripe_flat DECIMAL;
  v_commission_free_until DATE;
  v_use_merchant_rates    BOOLEAN := FALSE;
  v_brand_rate  DECIMAL := 0;
BEGIN
  SELECT
    commission_rate,
    COALESCE(stripe_processing_rate, 0.03),
    COALESCE(stripe_flat_fee, 0.30)
  INTO g_rate, g_stripe_rate, g_stripe_flat
  FROM platform_commission_config LIMIT 1;

  SELECT
    commission_free_until::DATE,
    m.commission_rate,
    m.commission_stripe_rate,
    m.commission_stripe_flat_fee,
    m.commission_effective_from,
    m.commission_effective_to
  INTO
    v_commission_free_until,
    m_rate, m_stripe_rate, m_stripe_flat,
    m_eff_from, m_eff_to
  FROM public.merchants m WHERE m.id = p_merchant_id;

  SELECT COALESCE(b.commission_rate, 0)
  INTO v_brand_rate
  FROM public.merchants m
  LEFT JOIN public.brands b ON b.id = m.brand_id
  WHERE m.id = p_merchant_id;

  IF (m_rate IS NOT NULL OR m_stripe_rate IS NOT NULL OR m_stripe_flat IS NOT NULL) THEN
    IF (m_eff_from IS NULL AND m_eff_to IS NULL) THEN
      v_use_merchant_rates := TRUE;
    ELSIF (m_eff_from IS NOT NULL AND m_eff_to IS NOT NULL) THEN
      v_use_merchant_rates := (CURRENT_DATE >= m_eff_from AND CURRENT_DATE <= m_eff_to);
    ELSIF (m_eff_from IS NOT NULL) THEN
      v_use_merchant_rates := (CURRENT_DATE >= m_eff_from);
    ELSIF (m_eff_to IS NOT NULL) THEN
      v_use_merchant_rates := (CURRENT_DATE <= m_eff_to);
    END IF;
  END IF;

  IF v_use_merchant_rates THEN
    v_rate        := COALESCE(m_rate,        g_rate);
    v_stripe_rate := COALESCE(m_stripe_rate, g_stripe_rate);
    v_stripe_flat := COALESCE(m_stripe_flat, g_stripe_flat);
  ELSE
    v_rate        := g_rate;
    v_stripe_rate := g_stripe_rate;
    v_stripe_flat := g_stripe_flat;
  END IF;

  RETURN QUERY
  SELECT
    oi.order_id,
    oi.id AS order_item_id,
    d.title::TEXT,
    COALESCE(d.validity_type, 'fixed_date')::TEXT,
    oi.unit_price,
    CASE
      WHEN v_commission_free_until IS NOT NULL
           AND oi.created_at::DATE <= v_commission_free_until THEN 0::DECIMAL
      ELSE v_rate
    END AS platform_fee_rate,
    CASE
      WHEN v_commission_free_until IS NOT NULL
           AND oi.created_at::DATE <= v_commission_free_until THEN 0::NUMERIC
      ELSE ROUND(oi.unit_price * v_rate, 2)
    END AS platform_fee,
    v_brand_rate AS brand_fee_rate,
    ROUND(oi.unit_price * v_brand_rate, 2) AS brand_fee,
    CASE
      WHEN v_commission_free_until IS NOT NULL
           AND oi.created_at::DATE <= v_commission_free_until THEN 0::NUMERIC
      ELSE ROUND(oi.unit_price * v_stripe_rate + v_stripe_flat, 2)
    END AS stripe_fee,
    CASE
      WHEN v_commission_free_until IS NOT NULL
           AND oi.created_at::DATE <= v_commission_free_until
        THEN ROUND(oi.unit_price - oi.unit_price * v_brand_rate, 2)
      ELSE ROUND(
        oi.unit_price
        - oi.unit_price * v_rate
        - oi.unit_price * v_brand_rate
        - (oi.unit_price * v_stripe_rate + v_stripe_flat),
        2)
    END AS net_amount,
    oi.customer_status::TEXT,
    oi.created_at,
    COUNT(*) OVER ()
  FROM public.order_items oi
  JOIN public.deals d ON d.id = oi.deal_id
  WHERE COALESCE(oi.redeemed_merchant_id, d.merchant_id) = p_merchant_id
    AND oi.customer_status::TEXT NOT IN ('refund_success', 'refund_pending', 'refund_processing')
    AND (p_date_from IS NULL OR oi.created_at::DATE >= p_date_from)
    AND (p_date_to   IS NULL OR oi.created_at::DATE <= p_date_to)
  ORDER BY oi.created_at DESC
  OFFSET (p_page - 1) * p_per_page LIMIT p_per_page;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_merchant_earnings_summary(
  p_merchant_id UUID,
  p_month_start DATE
)
RETURNS TABLE (
  total_revenue      NUMERIC,
  pending_settlement NUMERIC,
  settled_amount     NUMERIC,
  refunded_amount    NUMERIC
)
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  g_rate        DECIMAL;
  g_stripe_rate DECIMAL;
  g_stripe_flat DECIMAL;
  m_rate        DECIMAL;
  m_stripe_rate DECIMAL;
  m_stripe_flat DECIMAL;
  m_eff_from    DATE;
  m_eff_to      DATE;
  v_rate        DECIMAL;
  v_stripe_rate DECIMAL;
  v_stripe_flat DECIMAL;
  v_commission_free_until DATE;
  v_use_merchant_rates    BOOLEAN := FALSE;
  v_brand_rate  DECIMAL := 0;
BEGIN
  SELECT
    commission_rate,
    COALESCE(stripe_processing_rate, 0.03),
    COALESCE(stripe_flat_fee, 0.30)
  INTO g_rate, g_stripe_rate, g_stripe_flat
  FROM platform_commission_config LIMIT 1;

  SELECT
    commission_free_until::DATE,
    m.commission_rate,
    m.commission_stripe_rate,
    m.commission_stripe_flat_fee,
    m.commission_effective_from,
    m.commission_effective_to
  INTO
    v_commission_free_until,
    m_rate, m_stripe_rate, m_stripe_flat,
    m_eff_from, m_eff_to
  FROM public.merchants m WHERE m.id = p_merchant_id;

  SELECT COALESCE(b.commission_rate, 0)
  INTO v_brand_rate
  FROM public.merchants m
  LEFT JOIN public.brands b ON b.id = m.brand_id
  WHERE m.id = p_merchant_id;

  IF (m_rate IS NOT NULL OR m_stripe_rate IS NOT NULL OR m_stripe_flat IS NOT NULL) THEN
    IF (m_eff_from IS NULL AND m_eff_to IS NULL) THEN
      v_use_merchant_rates := TRUE;
    ELSIF (m_eff_from IS NOT NULL AND m_eff_to IS NOT NULL) THEN
      v_use_merchant_rates := (CURRENT_DATE >= m_eff_from AND CURRENT_DATE <= m_eff_to);
    ELSIF (m_eff_from IS NOT NULL) THEN
      v_use_merchant_rates := (CURRENT_DATE >= m_eff_from);
    ELSIF (m_eff_to IS NOT NULL) THEN
      v_use_merchant_rates := (CURRENT_DATE <= m_eff_to);
    END IF;
  END IF;

  IF v_use_merchant_rates THEN
    v_rate        := COALESCE(m_rate,        g_rate);
    v_stripe_rate := COALESCE(m_stripe_rate, g_stripe_rate);
    v_stripe_flat := COALESCE(m_stripe_flat, g_stripe_flat);
  ELSE
    v_rate        := g_rate;
    v_stripe_rate := g_stripe_rate;
    v_stripe_flat := g_stripe_flat;
  END IF;

  RETURN QUERY SELECT
    COALESCE((
      SELECT SUM(oi.unit_price)
      FROM public.order_items oi
      JOIN public.deals d ON d.id = oi.deal_id
      WHERE COALESCE(oi.redeemed_merchant_id, d.merchant_id) = p_merchant_id
        AND oi.customer_status::TEXT NOT IN ('refund_success', 'refund_pending', 'refund_processing')
        AND oi.created_at::DATE >= p_month_start
        AND oi.created_at::DATE < (p_month_start + INTERVAL '1 month')::DATE
    ), 0),
    COALESCE((
      SELECT SUM(
        CASE
          WHEN v_commission_free_until IS NOT NULL
               AND oi.created_at::DATE <= v_commission_free_until
            THEN oi.unit_price - oi.unit_price * v_brand_rate
          ELSE oi.unit_price
             - oi.unit_price * v_rate
             - oi.unit_price * v_brand_rate
             - (oi.unit_price * v_stripe_rate + v_stripe_flat)
        END
      )
      FROM public.order_items oi
      JOIN public.deals d ON d.id = oi.deal_id
      WHERE COALESCE(oi.redeemed_merchant_id, d.merchant_id) = p_merchant_id
        AND oi.customer_status::TEXT = 'used'
        AND oi.redeemed_at > NOW() - INTERVAL '7 days'
    ), 0),
    COALESCE((
      SELECT SUM(s.net_amount)
      FROM public.settlements s
      WHERE s.merchant_id = p_merchant_id
        AND s.status = 'paid'
        AND s.period_start >= p_month_start
        AND s.period_start < (p_month_start + INTERVAL '1 month')::DATE
    ), 0),
    COALESCE((
      SELECT SUM(oi.unit_price)
      FROM public.order_items oi
      JOIN public.deals d ON d.id = oi.deal_id
      WHERE COALESCE(oi.redeemed_merchant_id, d.merchant_id) = p_merchant_id
        AND oi.customer_status::TEXT = 'refund_success'
        AND oi.created_at::DATE >= p_month_start
        AND oi.created_at::DATE < (p_month_start + INTERVAL '1 month')::DATE
    ), 0);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_brand_earnings_summary(
  p_brand_id    UUID,
  p_month_start DATE
)
RETURNS TABLE (
  total_brand_revenue NUMERIC,
  pending_settlement  NUMERIC,
  settled_amount      NUMERIC,
  refunded_amount     NUMERIC
)
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_brand_rate DECIMAL := 0;
BEGIN
  SELECT COALESCE(b.commission_rate, 0)
  INTO v_brand_rate
  FROM public.brands b
  WHERE b.id = p_brand_id;

  RETURN QUERY SELECT
    COALESCE((
      SELECT ROUND(SUM(oi.unit_price * v_brand_rate), 2)
      FROM public.order_items oi
      JOIN public.deals d ON d.id = oi.deal_id
      JOIN public.merchants m ON m.id = COALESCE(oi.redeemed_merchant_id, d.merchant_id)
      WHERE m.brand_id = p_brand_id
        AND oi.customer_status::TEXT NOT IN ('refund_success', 'refund_pending', 'refund_processing')
        AND oi.created_at::DATE >= p_month_start
        AND oi.created_at::DATE < (p_month_start + INTERVAL '1 month')::DATE
    ), 0),
    COALESCE((
      SELECT ROUND(SUM(oi.unit_price * v_brand_rate), 2)
      FROM public.order_items oi
      JOIN public.deals d ON d.id = oi.deal_id
      JOIN public.merchants m ON m.id = COALESCE(oi.redeemed_merchant_id, d.merchant_id)
      WHERE m.brand_id = p_brand_id
        AND oi.customer_status::TEXT = 'used'
        AND oi.redeemed_at > NOW() - INTERVAL '7 days'
    ), 0),
    COALESCE((
      SELECT SUM(bw.amount)
      FROM public.brand_withdrawals bw
      WHERE bw.brand_id = p_brand_id
        AND bw.status = 'completed'
        AND bw.completed_at >= p_month_start
        AND bw.completed_at < (p_month_start + INTERVAL '1 month')::TIMESTAMPTZ
    ), 0),
    COALESCE((
      SELECT ROUND(SUM(oi.unit_price * v_brand_rate), 2)
      FROM public.order_items oi
      JOIN public.deals d ON d.id = oi.deal_id
      JOIN public.merchants m ON m.id = COALESCE(oi.redeemed_merchant_id, d.merchant_id)
      WHERE m.brand_id = p_brand_id
        AND oi.customer_status::TEXT = 'refund_success'
        AND oi.created_at::DATE >= p_month_start
        AND oi.created_at::DATE < (p_month_start + INTERVAL '1 month')::DATE
    ), 0);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_brand_transactions(
  p_brand_id  UUID,
  p_date_from DATE DEFAULT NULL,
  p_date_to   DATE DEFAULT NULL,
  p_page      INT  DEFAULT 1,
  p_per_page  INT  DEFAULT 20
)
RETURNS TABLE (
  order_id       UUID,
  order_item_id  UUID,
  deal_title     TEXT,
  store_name     TEXT,
  amount         NUMERIC,
  brand_fee_rate DECIMAL,
  brand_fee      NUMERIC,
  status         TEXT,
  created_at     TIMESTAMPTZ,
  total_count    BIGINT
)
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_brand_rate DECIMAL := 0;
BEGIN
  SELECT COALESCE(b.commission_rate, 0)
  INTO v_brand_rate
  FROM public.brands b
  WHERE b.id = p_brand_id;

  RETURN QUERY
  SELECT
    oi.order_id,
    oi.id AS order_item_id,
    d.title::TEXT,
    m.name::TEXT AS store_name,
    oi.unit_price AS amount,
    v_brand_rate AS brand_fee_rate,
    ROUND(oi.unit_price * v_brand_rate, 2) AS brand_fee,
    oi.customer_status::TEXT AS status,
    oi.created_at,
    COUNT(*) OVER () AS total_count
  FROM public.order_items oi
  JOIN public.deals d ON d.id = oi.deal_id
  JOIN public.merchants m ON m.id = COALESCE(oi.redeemed_merchant_id, d.merchant_id)
  WHERE m.brand_id = p_brand_id
    AND oi.customer_status::TEXT NOT IN ('refund_success', 'refund_pending', 'refund_processing')
    AND (p_date_from IS NULL OR oi.created_at::DATE >= p_date_from)
    AND (p_date_to   IS NULL OR oi.created_at::DATE <= p_date_to)
  ORDER BY oi.created_at DESC
  OFFSET (p_page - 1) * p_per_page LIMIT p_per_page;
END;
$$;
