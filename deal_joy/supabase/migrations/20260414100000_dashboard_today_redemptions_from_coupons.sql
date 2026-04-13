-- Dashboard today_redemptions：改为以 coupons.redeemed_at 计数，与核销写库一致
--
-- 背景：merchant-scan 始终更新 coupons.redeemed_at / used_at，但仅当 coupon.order_item_id
-- 非空时才更新 order_items.redeemed_at。若某张券无 order_item_id 或历史数据不同步，
-- 仅统计 order_items 会少计，表现为「3 张券核销只显示 2」。
-- 门店归属：有 order_item 时沿用 purchased_merchant_id / applicable_store_ids；
-- 无 order_item 时回退 coupons.merchant_id / purchased_merchant_id。

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

    (
      SELECT COUNT(*)
      FROM coupons c
      LEFT JOIN order_items oi ON oi.id = c.order_item_id
      WHERE c.status = 'used'
        AND c.redeemed_at IS NOT NULL
        AND c.redeemed_at >= CURRENT_DATE
        AND c.redeemed_at <  CURRENT_DATE + INTERVAL '1 day'
        AND (
          (oi.id IS NULL AND (c.merchant_id = p_merchant_id OR c.purchased_merchant_id = p_merchant_id))
          OR (
            oi.id IS NOT NULL
            AND (
              oi.purchased_merchant_id = p_merchant_id
              OR p_merchant_id = ANY (oi.applicable_store_ids)
            )
          )
        )
    )::bigint AS today_redemptions,

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
        AND oi.customer_status NOT IN ('refund_success', 'refund_pending', 'refund_processing')
    ) AS today_revenue,

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
