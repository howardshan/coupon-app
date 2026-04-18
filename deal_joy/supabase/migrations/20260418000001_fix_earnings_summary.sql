-- ============================================================
-- 修复 get_merchant_earnings_summary:
-- 1. total_revenue: 从 SUM(unit_price) 票面价改为商家到手净额（扣平台费+品牌费+Stripe费），且只算已核销
-- 2. refunded_amount: 只统计核销后退款（redeemed_at IS NOT NULL），排除未核销直接退款
-- ============================================================

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
    -- total_revenue：当月已核销的商家到手净额（扣除平台费+品牌费+Stripe费）
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
        AND oi.created_at::DATE >= p_month_start
        AND oi.created_at::DATE < (p_month_start + INTERVAL '1 month')::DATE
    ), 0),
    -- pending_settlement：已核销不足7天，扣除平台抽成+品牌费+Stripe后的实收
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
    -- settled_amount：已结算
    COALESCE((
      SELECT SUM(s.net_amount)
      FROM public.settlements s
      WHERE s.merchant_id = p_merchant_id
        AND s.status = 'paid'
        AND s.period_start >= p_month_start
        AND s.period_start < (p_month_start + INTERVAL '1 month')::DATE
    ), 0),
    -- refunded_amount：仅核销后退款金额（redeemed_at IS NOT NULL 表示曾经核销过）
    COALESCE((
      SELECT SUM(oi.unit_price)
      FROM public.order_items oi
      JOIN public.deals d ON d.id = oi.deal_id
      WHERE COALESCE(oi.redeemed_merchant_id, d.merchant_id) = p_merchant_id
        AND oi.customer_status::TEXT = 'refund_success'
        AND oi.redeemed_at IS NOT NULL
        AND oi.created_at::DATE >= p_month_start
        AND oi.created_at::DATE < (p_month_start + INTERVAL '1 month')::DATE
    ), 0);
END;
$$;
