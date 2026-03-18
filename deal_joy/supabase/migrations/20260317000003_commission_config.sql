-- ============================================================
-- 差异化抽成系统：全局配置表 + merchants 免费期字段 + RPC 重建
-- ============================================================

-- 1. 全局抽成配置表（始终只有一行）
CREATE TABLE IF NOT EXISTS platform_commission_config (
  id                        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  free_months               INT          NOT NULL DEFAULT 3,
  fixed_date_rate           DECIMAL(5,4) NOT NULL DEFAULT 0.15,
  short_after_purchase_rate DECIMAL(5,4) NOT NULL DEFAULT 0.10,
  long_after_purchase_rate  DECIMAL(5,4) NOT NULL DEFAULT 0.15,
  note                      TEXT,
  updated_at                TIMESTAMPTZ  DEFAULT now(),
  updated_by                UUID         REFERENCES auth.users(id)
);

-- 条件插入初始数据（避免重复执行报错）
INSERT INTO platform_commission_config
  (free_months, fixed_date_rate, short_after_purchase_rate, long_after_purchase_rate)
SELECT 3, 0.15, 0.10, 0.15
WHERE NOT EXISTS (SELECT 1 FROM platform_commission_config LIMIT 1);

-- updated_at 自动更新触发器
CREATE OR REPLACE FUNCTION update_commission_config_updated_at()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_commission_config_updated_at ON platform_commission_config;
CREATE TRIGGER trg_commission_config_updated_at
  BEFORE UPDATE ON platform_commission_config
  FOR EACH ROW EXECUTE FUNCTION update_commission_config_updated_at();

ALTER TABLE platform_commission_config ENABLE ROW LEVEL SECURITY;

-- admin 可读写
CREATE POLICY "admin_all_commission_config" ON platform_commission_config
  FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin'));

-- 已登录商家可读取（展示费率用）
CREATE POLICY "merchant_read_commission_config" ON platform_commission_config
  FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role IN ('admin', 'merchant')));


-- ============================================================
-- 2. merchants 表新增 commission_free_until
-- ============================================================
ALTER TABLE public.merchants
  ADD COLUMN IF NOT EXISTS commission_free_until TIMESTAMPTZ;

COMMENT ON COLUMN public.merchants.commission_free_until IS
  '免费期截止时间（NULL = 无免费期）。审核通过时由后端自动填入，admin 可手动覆盖。';


-- ============================================================
-- 3. 重建 get_merchant_transactions（动态三档费率 + 免费期）
--    返回类型有变更（新增 validity_type, platform_fee_rate），必须 DROP 再 CREATE
-- ============================================================
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
  deal_title        TEXT,
  validity_type     TEXT,
  amount            NUMERIC,
  platform_fee_rate DECIMAL,
  platform_fee      NUMERIC,
  net_amount        NUMERIC,
  status            TEXT,
  created_at        TIMESTAMPTZ,
  total_count       BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_fixed_rate            DECIMAL;
  v_short_rate            DECIMAL;
  v_long_rate             DECIMAL;
  v_commission_free_until TIMESTAMPTZ;
BEGIN
  -- 读取全局费率配置
  SELECT fixed_date_rate, short_after_purchase_rate, long_after_purchase_rate
  INTO v_fixed_rate, v_short_rate, v_long_rate
  FROM platform_commission_config LIMIT 1;

  -- 读取该商家的免费期截止时间
  SELECT commission_free_until INTO v_commission_free_until
  FROM public.merchants WHERE id = p_merchant_id;

  RETURN QUERY
  SELECT
    o.id,
    d.title::TEXT,
    COALESCE(d.validity_type, 'fixed_date')::TEXT,
    o.total_amount,
    -- 费率：免费期内 → 0，否则按 validity_type 三档
    CASE
      WHEN v_commission_free_until IS NOT NULL AND o.created_at < v_commission_free_until
        THEN 0::DECIMAL
      WHEN COALESCE(d.validity_type, 'fixed_date') = 'short_after_purchase'
        THEN v_short_rate
      WHEN COALESCE(d.validity_type, 'fixed_date') = 'long_after_purchase'
        THEN v_long_rate
      ELSE v_fixed_rate
    END AS platform_fee_rate,
    -- 平台手续费
    ROUND(o.total_amount * CASE
      WHEN v_commission_free_until IS NOT NULL AND o.created_at < v_commission_free_until THEN 0
      WHEN COALESCE(d.validity_type, 'fixed_date') = 'short_after_purchase' THEN v_short_rate
      WHEN COALESCE(d.validity_type, 'fixed_date') = 'long_after_purchase'  THEN v_long_rate
      ELSE v_fixed_rate
    END, 2) AS platform_fee,
    -- 商家实收
    ROUND(o.total_amount * (1 - CASE
      WHEN v_commission_free_until IS NOT NULL AND o.created_at < v_commission_free_until THEN 0
      WHEN COALESCE(d.validity_type, 'fixed_date') = 'short_after_purchase' THEN v_short_rate
      WHEN COALESCE(d.validity_type, 'fixed_date') = 'long_after_purchase'  THEN v_long_rate
      ELSE v_fixed_rate
    END), 2) AS net_amount,
    o.status::TEXT,
    o.created_at,
    COUNT(*) OVER () AS total_count
  FROM public.orders o
  JOIN public.deals d ON d.id = o.deal_id
  JOIN public.coupons c ON c.order_id = o.id
  -- 统计口径：核销归属（与现有逻辑一致）
  WHERE COALESCE(c.redeemed_at_merchant_id, d.merchant_id) = p_merchant_id
    AND o.status NOT IN ('refunded', 'refund_failed')
    AND (p_date_from IS NULL OR o.created_at::DATE >= p_date_from)
    AND (p_date_to   IS NULL OR o.created_at::DATE <= p_date_to)
  ORDER BY o.created_at DESC
  OFFSET (p_page - 1) * p_per_page LIMIT p_per_page;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_merchant_transactions(UUID, DATE, DATE, INT, INT)
  TO authenticated, service_role;


-- ============================================================
-- 4. 重建 get_merchant_earnings_summary（动态三档费率 + 免费期）
-- ============================================================
DROP FUNCTION IF EXISTS public.get_merchant_earnings_summary(UUID, DATE);

CREATE FUNCTION public.get_merchant_earnings_summary(
  p_merchant_id UUID,
  p_month_start DATE
)
RETURNS TABLE (
  total_revenue      NUMERIC,
  pending_settlement NUMERIC,
  settled_amount     NUMERIC,
  refunded_amount    NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_fixed_rate            DECIMAL;
  v_short_rate            DECIMAL;
  v_long_rate             DECIMAL;
  v_commission_free_until TIMESTAMPTZ;
BEGIN
  SELECT fixed_date_rate, short_after_purchase_rate, long_after_purchase_rate
  INTO v_fixed_rate, v_short_rate, v_long_rate
  FROM platform_commission_config LIMIT 1;

  SELECT commission_free_until INTO v_commission_free_until
  FROM public.merchants WHERE id = p_merchant_id;

  RETURN QUERY SELECT
    -- total_revenue：核销归属，当月所有非退款订单总金额
    COALESCE((
      SELECT SUM(o.total_amount)
      FROM public.orders o
      JOIN public.coupons c ON c.order_id = o.id
      JOIN public.deals d ON d.id = o.deal_id
      WHERE COALESCE(c.redeemed_at_merchant_id, d.merchant_id) = p_merchant_id
        AND o.status NOT IN ('refunded','refund_failed')
        AND o.created_at::DATE >= p_month_start
        AND o.created_at::DATE < (p_month_start + INTERVAL '1 month')::DATE
    ), 0),
    -- pending_settlement：已核销但不足 7 天，动态费率算实收
    COALESCE((
      SELECT SUM(o.total_amount * (1 - CASE
        WHEN v_commission_free_until IS NOT NULL AND o.created_at < v_commission_free_until THEN 0
        WHEN COALESCE(d.validity_type,'fixed_date') = 'short_after_purchase' THEN v_short_rate
        WHEN COALESCE(d.validity_type,'fixed_date') = 'long_after_purchase'  THEN v_long_rate
        ELSE v_fixed_rate
      END))
      FROM public.orders o
      JOIN public.coupons c ON c.order_id = o.id
      JOIN public.deals d ON d.id = o.deal_id
      WHERE COALESCE(c.redeemed_at_merchant_id, d.merchant_id) = p_merchant_id
        AND c.status = 'used'
        AND c.used_at > NOW() - INTERVAL '7 days'
    ), 0),
    -- settled_amount：已 paid 的 settlements 合计
    COALESCE((
      SELECT SUM(s.net_amount)
      FROM public.settlements s
      WHERE s.merchant_id = p_merchant_id
        AND s.status = 'paid'
        AND s.period_start >= p_month_start
        AND s.period_start < (p_month_start + INTERVAL '1 month')::DATE
    ), 0),
    -- refunded_amount：核销归属，当月退款总额
    COALESCE((
      SELECT SUM(o.total_amount)
      FROM public.orders o
      JOIN public.coupons c ON c.order_id = o.id
      JOIN public.deals d ON d.id = o.deal_id
      WHERE COALESCE(c.redeemed_at_merchant_id, d.merchant_id) = p_merchant_id
        AND o.status = 'refunded'
        AND o.created_at::DATE >= p_month_start
        AND o.created_at::DATE < (p_month_start + INTERVAL '1 month')::DATE
    ), 0);
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_merchant_earnings_summary(UUID, DATE)
  TO authenticated, service_role;


-- ============================================================
-- 5. 重建 get_merchant_report_data（动态三档费率 + 免费期）
-- ============================================================
DROP FUNCTION IF EXISTS public.get_merchant_report_data(UUID, DATE, DATE);

CREATE FUNCTION public.get_merchant_report_data(
  p_merchant_id UUID,
  p_date_from   DATE,
  p_date_to     DATE
)
RETURNS TABLE (
  report_date  DATE,
  order_count  BIGINT,
  gross_amount NUMERIC,
  platform_fee NUMERIC,
  net_amount   NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_fixed_rate            DECIMAL;
  v_short_rate            DECIMAL;
  v_long_rate             DECIMAL;
  v_commission_free_until TIMESTAMPTZ;
BEGIN
  SELECT fixed_date_rate, short_after_purchase_rate, long_after_purchase_rate
  INTO v_fixed_rate, v_short_rate, v_long_rate
  FROM platform_commission_config LIMIT 1;

  SELECT commission_free_until INTO v_commission_free_until
  FROM public.merchants WHERE id = p_merchant_id;

  RETURN QUERY
  SELECT
    DATE(o.created_at) AS report_date,
    COUNT(*) AS order_count,
    COALESCE(SUM(o.total_amount), 0) AS gross_amount,
    COALESCE(ROUND(SUM(o.total_amount * CASE
      WHEN v_commission_free_until IS NOT NULL AND o.created_at < v_commission_free_until THEN 0
      WHEN COALESCE(d.validity_type,'fixed_date') = 'short_after_purchase' THEN v_short_rate
      WHEN COALESCE(d.validity_type,'fixed_date') = 'long_after_purchase'  THEN v_long_rate
      ELSE v_fixed_rate
    END), 2), 0) AS platform_fee,
    COALESCE(ROUND(SUM(o.total_amount * (1 - CASE
      WHEN v_commission_free_until IS NOT NULL AND o.created_at < v_commission_free_until THEN 0
      WHEN COALESCE(d.validity_type,'fixed_date') = 'short_after_purchase' THEN v_short_rate
      WHEN COALESCE(d.validity_type,'fixed_date') = 'long_after_purchase'  THEN v_long_rate
      ELSE v_fixed_rate
    END)), 2), 0) AS net_amount
  FROM public.orders o
  JOIN public.deals d ON d.id = o.deal_id
  LEFT JOIN public.coupons c ON c.order_id = o.id
  WHERE COALESCE(c.redeemed_at_merchant_id, d.merchant_id) = p_merchant_id
    AND o.status NOT IN ('refunded')
    AND DATE(o.created_at) BETWEEN p_date_from AND p_date_to
  GROUP BY DATE(o.created_at)
  ORDER BY DATE(o.created_at) ASC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_merchant_report_data(UUID, DATE, DATE)
  TO authenticated, service_role;
