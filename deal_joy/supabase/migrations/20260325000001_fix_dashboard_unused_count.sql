-- ============================================================
-- 修复 Dashboard Unused 数量统计
--
-- 问题：pending_coupons 基于 coupons.status = 'unused' 统计，
-- 但 coupons.status 和 order_items.customer_status 不同步，
-- 导致已退款/已取消的券仍被计为 unused。
--
-- 修复：改为基于 order_items.customer_status = 'unused' 统计，
-- 与 Orders 页 Unused tab 一致。
-- ============================================================

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
    -- 今日订单数：基于 order_items
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

    -- 今日核销数
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

    -- 今日收入
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

    -- Unused 券数：基于 order_items.customer_status，与 Orders 页 Unused tab 一致
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
