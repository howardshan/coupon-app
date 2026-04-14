-- get_merchant_transactions 增加 tax_amount 字段
-- 让商家端能看到每笔交易代收的税额（按用户要求，仅展示数值，不加归属附注）
-- 注意：commission base 仍然是 unit_price（不含税），税费不影响 net_amount 计算

DROP FUNCTION IF EXISTS public.get_merchant_transactions(UUID, DATE, DATE, INT, INT);

CREATE FUNCTION public.get_merchant_transactions(
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
  tax_amount        NUMERIC,   -- 新增：单笔交易代收税额
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
    COALESCE(oi.tax_amount, 0) AS tax_amount,
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
    AND oi.customer_status::TEXT NOT IN ('refund_success', 'refund_pending')
    AND (p_date_from IS NULL OR oi.created_at::DATE >= p_date_from)
    AND (p_date_to   IS NULL OR oi.created_at::DATE <= p_date_to)
  ORDER BY oi.created_at DESC
  OFFSET (p_page - 1) * p_per_page LIMIT p_per_page;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_merchant_transactions(UUID, DATE, DATE, INT, INT)
  TO authenticated, service_role;
