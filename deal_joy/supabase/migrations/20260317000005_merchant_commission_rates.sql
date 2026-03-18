-- ============================================================
-- 每个商家独立抽成费率字段（NULL = 使用全局默认）
-- ============================================================

ALTER TABLE public.merchants
  ADD COLUMN IF NOT EXISTS commission_fixed_date_rate  DECIMAL(5,4),
  ADD COLUMN IF NOT EXISTS commission_short_rate       DECIMAL(5,4),
  ADD COLUMN IF NOT EXISTS commission_long_rate        DECIMAL(5,4),
  ADD COLUMN IF NOT EXISTS commission_stripe_rate      DECIMAL(5,4),
  ADD COLUMN IF NOT EXISTS commission_stripe_flat_fee  DECIMAL(10,2),
  ADD COLUMN IF NOT EXISTS commission_effective_from   DATE,
  ADD COLUMN IF NOT EXISTS commission_effective_to     DATE;

-- ============================================================
-- 重建 get_merchant_transactions：优先用商家专属费率，否则用全局默认
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
  deal_title        TEXT,
  validity_type     TEXT,
  amount            NUMERIC,
  platform_fee_rate DECIMAL,
  platform_fee      NUMERIC,
  net_amount        NUMERIC,
  status            TEXT,
  created_at        TIMESTAMPTZ,
  total_count       BIGINT
) AS $$
DECLARE
  v_fixed_rate            DECIMAL;
  v_short_rate            DECIMAL;
  v_long_rate             DECIMAL;
  v_commission_free_until TIMESTAMPTZ;
  -- 商家专属费率（NULL 代表未设置）
  m_fixed_rate            DECIMAL;
  m_short_rate            DECIMAL;
  m_long_rate             DECIMAL;
BEGIN
  -- 读取全局默认费率
  SELECT fixed_date_rate, short_after_purchase_rate, long_after_purchase_rate
  INTO v_fixed_rate, v_short_rate, v_long_rate
  FROM platform_commission_config LIMIT 1;

  -- 读取商家专属费率 + 免费期
  SELECT
    commission_free_until,
    commission_fixed_date_rate,
    commission_short_rate,
    commission_long_rate
  INTO v_commission_free_until, m_fixed_rate, m_short_rate, m_long_rate
  FROM public.merchants WHERE id = p_merchant_id;

  -- COALESCE：商家专属 > 全局默认
  v_fixed_rate := COALESCE(m_fixed_rate, v_fixed_rate);
  v_short_rate := COALESCE(m_short_rate, v_short_rate);
  v_long_rate  := COALESCE(m_long_rate,  v_long_rate);

  RETURN QUERY
  SELECT
    o.id,
    d.title,
    COALESCE(d.validity_type, 'fixed_date')::TEXT,
    o.total_amount,
    CASE
      WHEN v_commission_free_until IS NOT NULL AND o.created_at < v_commission_free_until THEN 0::DECIMAL
      WHEN COALESCE(d.validity_type, 'fixed_date') = 'short_after_purchase' THEN v_short_rate
      WHEN COALESCE(d.validity_type, 'fixed_date') = 'long_after_purchase'  THEN v_long_rate
      ELSE v_fixed_rate
    END AS platform_fee_rate,
    ROUND(o.total_amount * CASE
      WHEN v_commission_free_until IS NOT NULL AND o.created_at < v_commission_free_until THEN 0
      WHEN COALESCE(d.validity_type, 'fixed_date') = 'short_after_purchase' THEN v_short_rate
      WHEN COALESCE(d.validity_type, 'fixed_date') = 'long_after_purchase'  THEN v_long_rate
      ELSE v_fixed_rate
    END, 2) AS platform_fee,
    ROUND(o.total_amount * (1 - CASE
      WHEN v_commission_free_until IS NOT NULL AND o.created_at < v_commission_free_until THEN 0
      WHEN COALESCE(d.validity_type, 'fixed_date') = 'short_after_purchase' THEN v_short_rate
      WHEN COALESCE(d.validity_type, 'fixed_date') = 'long_after_purchase'  THEN v_long_rate
      ELSE v_fixed_rate
    END), 2) AS net_amount,
    o.status::TEXT,
    o.created_at,
    COUNT(*) OVER ()
  FROM public.orders o
  JOIN public.deals d ON d.id = o.deal_id
  WHERE o.purchased_merchant_id = p_merchant_id
    AND o.status NOT IN ('refunded', 'refund_failed')
    AND (p_date_from IS NULL OR o.created_at::DATE >= p_date_from)
    AND (p_date_to   IS NULL OR o.created_at::DATE <= p_date_to)
  ORDER BY o.created_at DESC
  OFFSET (p_page - 1) * p_per_page LIMIT p_per_page;
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION get_merchant_transactions(UUID, DATE, DATE, INT, INT) TO authenticated;
