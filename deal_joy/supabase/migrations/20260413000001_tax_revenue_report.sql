-- Tax Revenue Report
-- 1. 给 order_items 新增 tax_metro_area 快照字段（下单时锁定，防止 merchant.metro_area 后续变更导致历史报表漂移）
-- 2. 回填历史数据
-- 3. 创建月度税费/营业额统计 RPC（仅基于已 redeem 且未退款的 order_items）

-- ============================================================
-- 1. order_items 新增 tax_metro_area 字段
-- ============================================================
ALTER TABLE public.order_items
  ADD COLUMN IF NOT EXISTS tax_metro_area text;

COMMENT ON COLUMN public.order_items.tax_metro_area IS
  '税收归属地快照（下单时根据 deal → merchant.metro_area 锁定）。与 tax_rate / tax_amount 一起构成税费快照。';

-- ============================================================
-- 2. 回填历史 order_items（按 deal.merchant 当前 metro_area）
-- ============================================================
UPDATE public.order_items oi
SET tax_metro_area = m.metro_area
FROM public.deals d
JOIN public.merchants m ON m.id = d.merchant_id
WHERE oi.deal_id = d.id
  AND oi.tax_metro_area IS NULL;

-- ============================================================
-- 3. 索引（仅覆盖已 redeem 场景，月度报表查询专用）
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_order_items_tax_metro_area_redeemed
  ON public.order_items (tax_metro_area, redeemed_at)
  WHERE customer_status = 'used';

-- ============================================================
-- 4. RPC：月度税费/营业额报表（按城市分组）
--   口径：仅统计 redeemed_at 在指定月份内且 customer_status = 'used' 的 order_items
--   排除：已退款（refund_success / refund_pending / refund_processing）
--   Commission 公式：完全复用 brand_commission migration 里的逻辑（per-merchant + brand + stripe）
-- ============================================================
DROP FUNCTION IF EXISTS public.get_tax_revenue_report(text);

CREATE FUNCTION public.get_tax_revenue_report(
  p_year_month text  -- 'YYYY-MM' 格式
)
RETURNS TABLE (
  metro_area          text,
  redeemed_count      bigint,
  gross_revenue       numeric,   -- unit_price 合计（不含税）
  tax_collected       numeric,   -- tax_amount 合计
  platform_commission numeric,   -- 平台抽成合计
  brand_commission    numeric,   -- 品牌抽成合计
  stripe_fee          numeric,   -- Stripe 手续费合计
  net_to_merchants    numeric    -- 商家实收合计（= gross - platform - brand - stripe）
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_month_start date;
  v_month_end   date;
  g_rate        decimal;
  g_stripe_rate decimal;
  g_stripe_flat decimal;
BEGIN
  -- 解析 YYYY-MM
  v_month_start := to_date(p_year_month || '-01', 'YYYY-MM-DD');
  v_month_end   := (v_month_start + interval '1 month')::date;

  -- 读取全局费率（作为 fallback，当 merchant 没有专属费率时用）
  SELECT
    commission_rate,
    COALESCE(stripe_processing_rate, 0.03),
    COALESCE(stripe_flat_fee, 0.30)
  INTO g_rate, g_stripe_rate, g_stripe_flat
  FROM public.platform_commission_config
  LIMIT 1;

  RETURN QUERY
  WITH eligible AS (
    -- 每一行：一张已 redeem 且未退款的 order_item
    SELECT
      COALESCE(oi.tax_metro_area, 'Unknown') AS metro_area,
      oi.unit_price,
      oi.tax_amount,
      oi.created_at,
      -- 商家的当期有效 commission_rate：优先用 merchant 专属，否则 fallback 全局
      CASE
        WHEN m.commission_free_until IS NOT NULL
             AND oi.created_at::date <= m.commission_free_until::date THEN 0::decimal
        WHEN m.commission_rate IS NOT NULL
             AND (m.commission_effective_from IS NULL OR CURRENT_DATE >= m.commission_effective_from)
             AND (m.commission_effective_to   IS NULL OR CURRENT_DATE <= m.commission_effective_to)
          THEN m.commission_rate
        ELSE g_rate
      END AS eff_platform_rate,
      CASE
        WHEN m.commission_free_until IS NOT NULL
             AND oi.created_at::date <= m.commission_free_until::date THEN 0::decimal
        WHEN m.commission_stripe_rate IS NOT NULL
          THEN m.commission_stripe_rate
        ELSE g_stripe_rate
      END AS eff_stripe_rate,
      CASE
        WHEN m.commission_free_until IS NOT NULL
             AND oi.created_at::date <= m.commission_free_until::date THEN 0::decimal
        WHEN m.commission_stripe_flat_fee IS NOT NULL
          THEN m.commission_stripe_flat_fee
        ELSE g_stripe_flat
      END AS eff_stripe_flat,
      COALESCE(b.commission_rate, 0) AS eff_brand_rate
    FROM public.order_items oi
    JOIN public.deals d     ON d.id = oi.deal_id
    JOIN public.merchants m ON m.id = d.merchant_id
    LEFT JOIN public.brands b ON b.id = m.brand_id
    WHERE oi.customer_status = 'used'
      AND oi.redeemed_at IS NOT NULL
      AND oi.redeemed_at >= v_month_start
      AND oi.redeemed_at <  v_month_end
  )
  SELECT
    e.metro_area,
    COUNT(*)::bigint AS redeemed_count,
    ROUND(SUM(e.unit_price), 2) AS gross_revenue,
    ROUND(SUM(e.tax_amount), 2) AS tax_collected,
    ROUND(SUM(e.unit_price * e.eff_platform_rate), 2) AS platform_commission,
    ROUND(SUM(e.unit_price * e.eff_brand_rate), 2) AS brand_commission,
    ROUND(SUM(e.unit_price * e.eff_stripe_rate + e.eff_stripe_flat), 2) AS stripe_fee,
    ROUND(SUM(
      e.unit_price
      - e.unit_price * e.eff_platform_rate
      - e.unit_price * e.eff_brand_rate
      - (e.unit_price * e.eff_stripe_rate + e.eff_stripe_flat)
    ), 2) AS net_to_merchants
  FROM eligible e
  GROUP BY e.metro_area
  ORDER BY e.metro_area;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_tax_revenue_report(text)
  TO authenticated, service_role;

COMMENT ON FUNCTION public.get_tax_revenue_report(text) IS
  '月度税费/营业额报表：按 city（order_items.tax_metro_area 快照）分组，仅统计已 redeem 且未退款的券。参数 p_year_month 格式 YYYY-MM。';
