-- ============================================================
-- 修正免费期边界：改为 <= DATE 比较（含当天），抽成从次日起算
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
  v_commission_free_until DATE;   -- 用 DATE 类型，方便做 <= 比较
  m_fixed_rate            DECIMAL;
  m_short_rate            DECIMAL;
  m_long_rate             DECIMAL;
BEGIN
  -- 读取全局默认费率
  SELECT fixed_date_rate, short_after_purchase_rate, long_after_purchase_rate
  INTO v_fixed_rate, v_short_rate, v_long_rate
  FROM platform_commission_config LIMIT 1;

  -- 读取商家专属费率 + 免费期（转为 DATE）
  SELECT
    commission_free_until::DATE,
    commission_fixed_date_rate,
    commission_short_rate,
    commission_long_rate
  INTO v_commission_free_until, m_fixed_rate, m_short_rate, m_long_rate
  FROM public.merchants WHERE id = p_merchant_id;

  -- 商家专属费率优先，否则用全局默认
  v_fixed_rate := COALESCE(m_fixed_rate, v_fixed_rate);
  v_short_rate := COALESCE(m_short_rate, v_short_rate);
  v_long_rate  := COALESCE(m_long_rate,  v_long_rate);

  RETURN QUERY
  SELECT
    o.id,
    d.title,
    COALESCE(d.validity_type, 'fixed_date')::TEXT,
    o.total_amount,
    -- 免费期：当天（<=）含当天免费，次日起按费率收取
    CASE
      WHEN v_commission_free_until IS NOT NULL
           AND o.created_at::DATE <= v_commission_free_until THEN 0::DECIMAL
      WHEN COALESCE(d.validity_type, 'fixed_date') = 'short_after_purchase' THEN v_short_rate
      WHEN COALESCE(d.validity_type, 'fixed_date') = 'long_after_purchase'  THEN v_long_rate
      ELSE v_fixed_rate
    END AS platform_fee_rate,
    ROUND(o.total_amount * CASE
      WHEN v_commission_free_until IS NOT NULL
           AND o.created_at::DATE <= v_commission_free_until THEN 0
      WHEN COALESCE(d.validity_type, 'fixed_date') = 'short_after_purchase' THEN v_short_rate
      WHEN COALESCE(d.validity_type, 'fixed_date') = 'long_after_purchase'  THEN v_long_rate
      ELSE v_fixed_rate
    END, 2) AS platform_fee,
    ROUND(o.total_amount * (1 - CASE
      WHEN v_commission_free_until IS NOT NULL
           AND o.created_at::DATE <= v_commission_free_until THEN 0
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
