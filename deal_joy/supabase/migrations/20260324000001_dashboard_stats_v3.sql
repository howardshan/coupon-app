-- ============================================================
-- Dashboard 统计函数升级至 V3（基于 order_items）
--
-- 问题：旧版 get_merchant_daily_stats / get_merchant_weekly_trend
-- 通过 orders.deal_id → deals.merchant_id 关联商家，
-- 但 V3 多 deal 订单的 orders.deal_id 只存 items[0] 的 deal，
-- 导致非首个 deal 的商家统计不到订单和收入。
--
-- 修复：改为基于 order_items.purchased_merchant_id 统计，
-- 同时兼容 applicable_store_ids（品牌 Deal 子门店）。
-- ============================================================


-- -------------------------------------------------------------
-- 1. 重建 get_merchant_daily_stats
-- -------------------------------------------------------------
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
    -- 今日订单数：基于 order_items，匹配 purchased_merchant_id 或 applicable_store_ids
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

    -- 今日核销数（保持基于 coupons，增加 purchased_merchant_id 匹配）
    (
      SELECT COUNT(*)
      FROM coupons c
      WHERE (c.merchant_id = p_merchant_id OR c.purchased_merchant_id = p_merchant_id)
        AND c.used_at >= CURRENT_DATE
        AND c.used_at <  CURRENT_DATE + INTERVAL '1 day'
    )::bigint AS today_redemptions,

    -- 今日收入：基于 order_items.unit_price（商家实际收入部分，不含服务费）
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
        AND oi.customer_status NOT IN ('refund_success', 'refund_pending')
    ) AS today_revenue,

    -- 待核销券数（增加 purchased_merchant_id 匹配）
    (
      SELECT COUNT(*)
      FROM coupons c
      WHERE (c.merchant_id = p_merchant_id OR c.purchased_merchant_id = p_merchant_id)
        AND c.status = 'unused'
        AND c.expires_at > NOW()
    )::bigint AS pending_coupons;
END;
$$;


-- -------------------------------------------------------------
-- 2. 重建 get_merchant_weekly_trend
-- -------------------------------------------------------------
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
    AND oi.customer_status NOT IN ('refund_success')
    AND (
      oi.purchased_merchant_id = p_merchant_id
      OR p_merchant_id = ANY(oi.applicable_store_ids)
    )
  GROUP BY gs.day
  ORDER BY gs.day DESC;
END;
$$;


-- -------------------------------------------------------------
-- 3. 重建 get_merchant_todos（也升级为 V3）
-- -------------------------------------------------------------
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
    -- 待回复评价
    (
      SELECT COUNT(*)
      FROM reviews r
      JOIN deals d ON d.id = r.deal_id
      WHERE d.merchant_id = p_merchant_id
    )::bigint AS pending_reviews,

    -- 待审核退款：基于 order_items V3 状态
    (
      SELECT COUNT(*)
      FROM order_items oi
      WHERE (
              oi.purchased_merchant_id = p_merchant_id
              OR p_merchant_id = ANY(oi.applicable_store_ids)
            )
        AND oi.customer_status = 'refund_pending'
    )::bigint AS pending_refunds,

    -- Influencer 申请：暂时返回 0
    0::bigint AS influencer_requests;
END;
$$;


-- -------------------------------------------------------------
-- 4. 权限授予
-- -------------------------------------------------------------
GRANT EXECUTE ON FUNCTION public.get_merchant_daily_stats(uuid)  TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_merchant_weekly_trend(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_merchant_todos(uuid)        TO authenticated;
