-- ============================================================
-- Earnings V3: RPC 函数适配 order_items 维度
--
-- 核心变更:
--   1. FROM orders → order_items（每张券独立计费）
--   2. 金额从 o.total_amount → oi.unit_price（单张券价格）
--   3. 商家归属从 COALESCE(c.redeemed_at_merchant_id, d.merchant_id)
--      → COALESCE(oi.redeemed_merchant_id, d.merchant_id)
--   4. 状态过滤从 o.status → oi.customer_status
--   5. 保留 Stripe fee + 生效日期逻辑不变
-- ============================================================


-- ============================================================
-- 1. 重建 get_merchant_transactions
-- ============================================================
DROP FUNCTION IF EXISTS get_merchant_transactions(UUID, DATE, DATE, INT, INT);

CREATE FUNCTION get_merchant_transactions(
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
  stripe_fee        NUMERIC,
  net_amount        NUMERIC,
  status            TEXT,
  created_at        TIMESTAMPTZ,
  total_count       BIGINT
) AS $$
DECLARE
  g_fixed_rate   DECIMAL;
  g_short_rate   DECIMAL;
  g_long_rate    DECIMAL;
  g_stripe_rate  DECIMAL;
  g_stripe_flat  DECIMAL;
  m_fixed_rate   DECIMAL;
  m_short_rate   DECIMAL;
  m_long_rate    DECIMAL;
  m_stripe_rate  DECIMAL;
  m_stripe_flat  DECIMAL;
  m_eff_from     DATE;
  m_eff_to       DATE;
  v_fixed_rate   DECIMAL;
  v_short_rate   DECIMAL;
  v_long_rate    DECIMAL;
  v_stripe_rate  DECIMAL;
  v_stripe_flat  DECIMAL;
  v_commission_free_until DATE;
  v_use_merchant_rates BOOLEAN := FALSE;
BEGIN
  -- 读取全局费率
  SELECT fixed_date_rate, short_after_purchase_rate, long_after_purchase_rate,
    COALESCE(stripe_processing_rate, 0.03), COALESCE(stripe_flat_fee, 0.30)
  INTO g_fixed_rate, g_short_rate, g_long_rate, g_stripe_rate, g_stripe_flat
  FROM platform_commission_config LIMIT 1;

  -- 读取商家专属
  SELECT commission_free_until::DATE,
    commission_fixed_date_rate, commission_short_rate, commission_long_rate,
    commission_stripe_rate, commission_stripe_flat_fee,
    commission_effective_from, commission_effective_to
  INTO v_commission_free_until,
    m_fixed_rate, m_short_rate, m_long_rate,
    m_stripe_rate, m_stripe_flat, m_eff_from, m_eff_to
  FROM public.merchants WHERE id = p_merchant_id;

  -- 判断生效期
  IF (m_fixed_rate IS NOT NULL OR m_short_rate IS NOT NULL OR m_long_rate IS NOT NULL
      OR m_stripe_rate IS NOT NULL OR m_stripe_flat IS NOT NULL) THEN
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
    v_fixed_rate  := COALESCE(m_fixed_rate,  g_fixed_rate);
    v_short_rate  := COALESCE(m_short_rate,  g_short_rate);
    v_long_rate   := COALESCE(m_long_rate,   g_long_rate);
    v_stripe_rate := COALESCE(m_stripe_rate, g_stripe_rate);
    v_stripe_flat := COALESCE(m_stripe_flat, g_stripe_flat);
  ELSE
    v_fixed_rate  := g_fixed_rate;
    v_short_rate  := g_short_rate;
    v_long_rate   := g_long_rate;
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
    -- 平台抽成费率
    CASE
      WHEN v_commission_free_until IS NOT NULL
           AND oi.created_at::DATE <= v_commission_free_until THEN 0::DECIMAL
      WHEN COALESCE(d.validity_type, 'fixed_date') = 'short_after_purchase' THEN v_short_rate
      WHEN COALESCE(d.validity_type, 'fixed_date') = 'long_after_purchase'  THEN v_long_rate
      ELSE v_fixed_rate
    END AS platform_fee_rate,
    -- 平台抽成金额
    ROUND(oi.unit_price * CASE
      WHEN v_commission_free_until IS NOT NULL
           AND oi.created_at::DATE <= v_commission_free_until THEN 0
      WHEN COALESCE(d.validity_type, 'fixed_date') = 'short_after_purchase' THEN v_short_rate
      WHEN COALESCE(d.validity_type, 'fixed_date') = 'long_after_purchase'  THEN v_long_rate
      ELSE v_fixed_rate
    END, 2) AS platform_fee,
    -- Stripe 手续费
    CASE
      WHEN v_commission_free_until IS NOT NULL
           AND oi.created_at::DATE <= v_commission_free_until THEN 0::NUMERIC
      ELSE ROUND(oi.unit_price * v_stripe_rate + v_stripe_flat, 2)
    END AS stripe_fee,
    -- 商家实收
    CASE
      WHEN v_commission_free_until IS NOT NULL
           AND oi.created_at::DATE <= v_commission_free_until THEN oi.unit_price
      ELSE ROUND(oi.unit_price
        - oi.unit_price * CASE
            WHEN COALESCE(d.validity_type, 'fixed_date') = 'short_after_purchase' THEN v_short_rate
            WHEN COALESCE(d.validity_type, 'fixed_date') = 'long_after_purchase'  THEN v_long_rate
            ELSE v_fixed_rate
          END
        - (oi.unit_price * v_stripe_rate + v_stripe_flat)
      , 2)
    END AS net_amount,
    oi.customer_status::TEXT,
    oi.created_at,
    COUNT(*) OVER ()
  FROM public.order_items oi
  JOIN public.deals d ON d.id = oi.deal_id
  WHERE COALESCE(oi.redeemed_merchant_id, d.merchant_id) = p_merchant_id
    AND oi.customer_status::TEXT NOT IN ('refund_success', 'refund_pending')
    AND (p_date_from IS NULL OR oi.created_at::DATE >= p_date_from)
    AND (p_date_to   IS NULL OR oi.created_at::DATE <= p_date_to)
  ORDER BY oi.created_at DESC
  OFFSET (p_page - 1) * p_per_page LIMIT p_per_page;
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION get_merchant_transactions(UUID, DATE, DATE, INT, INT)
  TO authenticated, service_role;


-- ============================================================
-- 2. 重建 get_merchant_earnings_summary
-- ============================================================
DROP FUNCTION IF EXISTS get_merchant_earnings_summary(UUID, DATE);

CREATE FUNCTION get_merchant_earnings_summary(
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
  g_fixed_rate   DECIMAL;
  g_short_rate   DECIMAL;
  g_long_rate    DECIMAL;
  g_stripe_rate  DECIMAL;
  g_stripe_flat  DECIMAL;
  m_fixed_rate   DECIMAL;
  m_short_rate   DECIMAL;
  m_long_rate    DECIMAL;
  m_stripe_rate  DECIMAL;
  m_stripe_flat  DECIMAL;
  m_eff_from     DATE;
  m_eff_to       DATE;
  v_fixed_rate   DECIMAL;
  v_short_rate   DECIMAL;
  v_long_rate    DECIMAL;
  v_stripe_rate  DECIMAL;
  v_stripe_flat  DECIMAL;
  v_commission_free_until DATE;
  v_use_merchant_rates BOOLEAN := FALSE;
BEGIN
  SELECT fixed_date_rate, short_after_purchase_rate, long_after_purchase_rate,
    COALESCE(stripe_processing_rate, 0.03), COALESCE(stripe_flat_fee, 0.30)
  INTO g_fixed_rate, g_short_rate, g_long_rate, g_stripe_rate, g_stripe_flat
  FROM platform_commission_config LIMIT 1;

  SELECT commission_free_until::DATE,
    commission_fixed_date_rate, commission_short_rate, commission_long_rate,
    commission_stripe_rate, commission_stripe_flat_fee,
    commission_effective_from, commission_effective_to
  INTO v_commission_free_until,
    m_fixed_rate, m_short_rate, m_long_rate,
    m_stripe_rate, m_stripe_flat, m_eff_from, m_eff_to
  FROM public.merchants WHERE id = p_merchant_id;

  IF (m_fixed_rate IS NOT NULL OR m_short_rate IS NOT NULL OR m_long_rate IS NOT NULL
      OR m_stripe_rate IS NOT NULL OR m_stripe_flat IS NOT NULL) THEN
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
    v_fixed_rate  := COALESCE(m_fixed_rate,  g_fixed_rate);
    v_short_rate  := COALESCE(m_short_rate,  g_short_rate);
    v_long_rate   := COALESCE(m_long_rate,   g_long_rate);
    v_stripe_rate := COALESCE(m_stripe_rate, g_stripe_rate);
    v_stripe_flat := COALESCE(m_stripe_flat, g_stripe_flat);
  ELSE
    v_fixed_rate  := g_fixed_rate;
    v_short_rate  := g_short_rate;
    v_long_rate   := g_long_rate;
    v_stripe_rate := g_stripe_rate;
    v_stripe_flat := g_stripe_flat;
  END IF;

  RETURN QUERY SELECT
    -- total_revenue：当月非退款 order_items 总金额
    COALESCE((
      SELECT SUM(oi.unit_price)
      FROM public.order_items oi
      JOIN public.deals d ON d.id = oi.deal_id
      WHERE COALESCE(oi.redeemed_merchant_id, d.merchant_id) = p_merchant_id
        AND oi.customer_status::TEXT NOT IN ('refund_success', 'refund_pending')
        AND oi.created_at::DATE >= p_month_start
        AND oi.created_at::DATE < (p_month_start + INTERVAL '1 month')::DATE
    ), 0),
    -- pending_settlement：已核销不足7天，扣除平台抽成+Stripe后的实收
    COALESCE((
      SELECT SUM(
        CASE
          WHEN v_commission_free_until IS NOT NULL
               AND oi.created_at::DATE <= v_commission_free_until THEN oi.unit_price
          ELSE oi.unit_price
            - oi.unit_price * CASE
                WHEN COALESCE(d.validity_type,'fixed_date') = 'short_after_purchase' THEN v_short_rate
                WHEN COALESCE(d.validity_type,'fixed_date') = 'long_after_purchase'  THEN v_long_rate
                ELSE v_fixed_rate
              END
            - (oi.unit_price * v_stripe_rate + v_stripe_flat)
        END
      )
      FROM public.order_items oi
      JOIN public.deals d ON d.id = oi.deal_id
      WHERE COALESCE(oi.redeemed_merchant_id, d.merchant_id) = p_merchant_id
        AND oi.customer_status::TEXT = 'used'
        AND oi.redeemed_at > NOW() - INTERVAL '7 days'
    ), 0),
    -- settled_amount
    COALESCE((
      SELECT SUM(s.net_amount)
      FROM public.settlements s
      WHERE s.merchant_id = p_merchant_id
        AND s.status = 'paid'
        AND s.period_start >= p_month_start
        AND s.period_start < (p_month_start + INTERVAL '1 month')::DATE
    ), 0),
    -- refunded_amount
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

GRANT EXECUTE ON FUNCTION get_merchant_earnings_summary(UUID, DATE)
  TO authenticated, service_role;


-- ============================================================
-- 3. 重建 get_merchant_report_data
-- ============================================================
DROP FUNCTION IF EXISTS get_merchant_report_data(UUID, DATE, DATE);

CREATE FUNCTION get_merchant_report_data(
  p_merchant_id UUID,
  p_date_from   DATE,
  p_date_to     DATE
)
RETURNS TABLE (
  report_date  DATE,
  order_count  BIGINT,
  gross_amount NUMERIC,
  platform_fee NUMERIC,
  stripe_fee   NUMERIC,
  net_amount   NUMERIC
)
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  g_fixed_rate   DECIMAL;
  g_short_rate   DECIMAL;
  g_long_rate    DECIMAL;
  g_stripe_rate  DECIMAL;
  g_stripe_flat  DECIMAL;
  m_fixed_rate   DECIMAL;
  m_short_rate   DECIMAL;
  m_long_rate    DECIMAL;
  m_stripe_rate  DECIMAL;
  m_stripe_flat  DECIMAL;
  m_eff_from     DATE;
  m_eff_to       DATE;
  v_fixed_rate   DECIMAL;
  v_short_rate   DECIMAL;
  v_long_rate    DECIMAL;
  v_stripe_rate  DECIMAL;
  v_stripe_flat  DECIMAL;
  v_commission_free_until DATE;
  v_use_merchant_rates BOOLEAN := FALSE;
BEGIN
  SELECT fixed_date_rate, short_after_purchase_rate, long_after_purchase_rate,
    COALESCE(stripe_processing_rate, 0.03), COALESCE(stripe_flat_fee, 0.30)
  INTO g_fixed_rate, g_short_rate, g_long_rate, g_stripe_rate, g_stripe_flat
  FROM platform_commission_config LIMIT 1;

  SELECT commission_free_until::DATE,
    commission_fixed_date_rate, commission_short_rate, commission_long_rate,
    commission_stripe_rate, commission_stripe_flat_fee,
    commission_effective_from, commission_effective_to
  INTO v_commission_free_until,
    m_fixed_rate, m_short_rate, m_long_rate,
    m_stripe_rate, m_stripe_flat, m_eff_from, m_eff_to
  FROM public.merchants WHERE id = p_merchant_id;

  IF (m_fixed_rate IS NOT NULL OR m_short_rate IS NOT NULL OR m_long_rate IS NOT NULL
      OR m_stripe_rate IS NOT NULL OR m_stripe_flat IS NOT NULL) THEN
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
    v_fixed_rate  := COALESCE(m_fixed_rate,  g_fixed_rate);
    v_short_rate  := COALESCE(m_short_rate,  g_short_rate);
    v_long_rate   := COALESCE(m_long_rate,   g_long_rate);
    v_stripe_rate := COALESCE(m_stripe_rate, g_stripe_rate);
    v_stripe_flat := COALESCE(m_stripe_flat, g_stripe_flat);
  ELSE
    v_fixed_rate  := g_fixed_rate;
    v_short_rate  := g_short_rate;
    v_long_rate   := g_long_rate;
    v_stripe_rate := g_stripe_rate;
    v_stripe_flat := g_stripe_flat;
  END IF;

  RETURN QUERY
  SELECT
    DATE(oi.created_at) AS report_date,
    COUNT(*) AS order_count,
    COALESCE(SUM(oi.unit_price), 0) AS gross_amount,
    -- 平台抽成
    COALESCE(ROUND(SUM(
      CASE
        WHEN v_commission_free_until IS NOT NULL
             AND oi.created_at::DATE <= v_commission_free_until THEN 0
        ELSE oi.unit_price * CASE
          WHEN COALESCE(d.validity_type,'fixed_date') = 'short_after_purchase' THEN v_short_rate
          WHEN COALESCE(d.validity_type,'fixed_date') = 'long_after_purchase'  THEN v_long_rate
          ELSE v_fixed_rate
        END
      END
    ), 2), 0) AS platform_fee,
    -- Stripe 手续费
    COALESCE(ROUND(SUM(
      CASE
        WHEN v_commission_free_until IS NOT NULL
             AND oi.created_at::DATE <= v_commission_free_until THEN 0
        ELSE oi.unit_price * v_stripe_rate + v_stripe_flat
      END
    ), 2), 0) AS stripe_fee,
    -- 商家实收
    COALESCE(ROUND(SUM(
      CASE
        WHEN v_commission_free_until IS NOT NULL
             AND oi.created_at::DATE <= v_commission_free_until THEN oi.unit_price
        ELSE oi.unit_price
          - oi.unit_price * CASE
              WHEN COALESCE(d.validity_type,'fixed_date') = 'short_after_purchase' THEN v_short_rate
              WHEN COALESCE(d.validity_type,'fixed_date') = 'long_after_purchase'  THEN v_long_rate
              ELSE v_fixed_rate
            END
          - (oi.unit_price * v_stripe_rate + v_stripe_flat)
      END
    ), 2), 0) AS net_amount
  FROM public.order_items oi
  JOIN public.deals d ON d.id = oi.deal_id
  WHERE COALESCE(oi.redeemed_merchant_id, d.merchant_id) = p_merchant_id
    AND oi.customer_status::TEXT NOT IN ('refund_success')
    AND DATE(oi.created_at) BETWEEN p_date_from AND p_date_to
  GROUP BY DATE(oi.created_at)
  ORDER BY DATE(oi.created_at) ASC;
END;
$$;

GRANT EXECUTE ON FUNCTION get_merchant_report_data(UUID, DATE, DATE)
  TO authenticated, service_role;
