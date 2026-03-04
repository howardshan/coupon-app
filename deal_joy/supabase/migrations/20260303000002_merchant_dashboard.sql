-- =============================================================
-- DealJoy 商家工作台 Migration
-- 添加 is_online 字段 + 创建统计函数
-- =============================================================

-- -------------------------------------------------------------
-- 1. 为 merchants 表添加 is_online 字段
--    控制门店是否对用户端可见
-- -------------------------------------------------------------
ALTER TABLE public.merchants
  ADD COLUMN IF NOT EXISTS is_online boolean NOT NULL DEFAULT true;

-- is_online 索引（用户端查询时过滤）
CREATE INDEX IF NOT EXISTS idx_merchants_is_online
  ON public.merchants(is_online);

-- -------------------------------------------------------------
-- 2. 修改用户端 deals 可见性策略：
--    下线商家的 deals 不在用户端展示
--    （扩展 deals_read_active 策略，增加 merchant.is_online 检查）
-- -------------------------------------------------------------
-- 先删除旧策略再重建
DROP POLICY IF EXISTS "deals_read_active" ON public.deals;

CREATE POLICY "deals_read_active" ON public.deals
  FOR SELECT USING (
    is_active = true
    AND merchant_id IN (
      SELECT id FROM public.merchants
      WHERE status = 'approved' AND is_online = true
    )
  );

-- -------------------------------------------------------------
-- 3. 函数: get_merchant_daily_stats
--    返回今日订单数、核销数、收入、待核销券数
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_merchant_daily_stats(p_merchant_id uuid)
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
    -- 今日订单数（当天创建，非退款）
    (
      SELECT COUNT(*)
      FROM orders o
      JOIN deals d ON d.id = o.deal_id
      WHERE d.merchant_id = p_merchant_id
        AND o.created_at >= CURRENT_DATE
        AND o.created_at <  CURRENT_DATE + INTERVAL '1 day'
        AND o.status NOT IN ('refunded')
    )::bigint AS today_orders,

    -- 今日核销数（today used_at）
    (
      SELECT COUNT(*)
      FROM coupons c
      WHERE c.merchant_id = p_merchant_id
        AND c.used_at >= CURRENT_DATE
        AND c.used_at <  CURRENT_DATE + INTERVAL '1 day'
    )::bigint AS today_redemptions,

    -- 今日收入（当天下单，非退款/申请退款）
    (
      SELECT COALESCE(SUM(o.total_amount), 0)
      FROM orders o
      JOIN deals d ON d.id = o.deal_id
      WHERE d.merchant_id = p_merchant_id
        AND o.created_at >= CURRENT_DATE
        AND o.created_at <  CURRENT_DATE + INTERVAL '1 day'
        AND o.status NOT IN ('refunded', 'refund_requested')
    ) AS today_revenue,

    -- 待核销券数（未过期、状态=unused）
    (
      SELECT COUNT(*)
      FROM coupons c
      WHERE c.merchant_id = p_merchant_id
        AND c.status = 'unused'
        AND c.expires_at > NOW()
    )::bigint AS pending_coupons;
END;
$$;

-- -------------------------------------------------------------
-- 4. 函数: get_merchant_weekly_trend
--    返回近 7 天（含今日）每天的订单数和收入
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_merchant_weekly_trend(p_merchant_id uuid)
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
    COALESCE(COUNT(o.id), 0)::bigint           AS daily_orders,
    COALESCE(SUM(o.total_amount), 0)           AS daily_revenue
  FROM
    -- 生成过去 7 天的日期序列（含今日）
    generate_series(
      CURRENT_DATE - INTERVAL '6 days',
      CURRENT_DATE,
      INTERVAL '1 day'
    ) AS gs(day)
  LEFT JOIN orders o
    ON o.created_at >= gs.day
    AND o.created_at <  gs.day + INTERVAL '1 day'
    AND o.status NOT IN ('refunded')
    AND o.deal_id IN (
      SELECT id FROM deals WHERE merchant_id = p_merchant_id
    )
  GROUP BY gs.day
  ORDER BY gs.day DESC;
END;
$$;

-- -------------------------------------------------------------
-- 5. 函数: get_merchant_todos
--    返回待处理事项计数
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_merchant_todos(p_merchant_id uuid)
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
    -- 待回复评价：该商家旗下 deals 的所有评价（V1：total review count）
    -- 未来可在 reviews 表加 reply_text 字段后改为 reply_text IS NULL
    (
      SELECT COUNT(*)
      FROM reviews r
      JOIN deals d ON d.id = r.deal_id
      WHERE d.merchant_id = p_merchant_id
    )::bigint AS pending_reviews,

    -- 待审核退款：status = refund_requested
    (
      SELECT COUNT(*)
      FROM orders o
      JOIN deals d ON d.id = o.deal_id
      WHERE d.merchant_id = p_merchant_id
        AND o.status = 'refund_requested'
    )::bigint AS pending_refunds,

    -- Influencer 申请：V1 暂时返回 0（influencer 模块后续开发）
    0::bigint AS influencer_requests;
END;
$$;

-- -------------------------------------------------------------
-- 6. 权限授予
--    Edge Function 使用 service_role 调用，无需额外 GRANT
--    但如果用 anon/authenticated 直接调用则需要：
-- -------------------------------------------------------------
GRANT EXECUTE ON FUNCTION public.get_merchant_daily_stats(uuid)  TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_merchant_weekly_trend(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_merchant_todos(uuid)        TO authenticated;

-- 限制：只能查询自己的数据（函数内部用 p_merchant_id 参数过滤，
-- Edge Function 层再验证 merchant_id 属于当前 JWT user）
