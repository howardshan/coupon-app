-- 重建 get_merchant_daily_stats
-- 改动：today_revenue 改为基于 order_items.redeemed_at 统计（今日核销的券的 unit_price 合计）
-- 原因：商家视角的 "Revenue" 应该是今日产生的实际营业额（已核销），而不是今日下单的预收款
-- today_orders / today_redemptions / pending_coupons 保持不变

DROP FUNCTION IF EXISTS public.get_merchant_daily_stats(uuid);

CREATE FUNCTION public.get_merchant_daily_stats(p_merchant_id uuid)
RETURNS TABLE (
  today_orders      bigint,
  today_redemptions bigint,
  today_revenue     numeric,
  pending_coupons   bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  RETURN QUERY
  SELECT
    -- today_orders：今日新下单的 order_items 数（按 orders.created_at 过滤）
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

    -- today_redemptions：今日核销的券数（按 coupons.redeemed_at 过滤）
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

    -- today_revenue：今日核销的 order_items 的 unit_price 合计
    -- 新语义：按 oi.redeemed_at 过滤，代表今天实际产生的营业额
    -- 优先匹配 redeemed_merchant_id（实际核销门店），fallback 到 purchased/applicable
    (
      SELECT COALESCE(SUM(oi.unit_price), 0)
      FROM order_items oi
      WHERE oi.customer_status = 'used'
        AND oi.redeemed_at IS NOT NULL
        AND oi.redeemed_at >= CURRENT_DATE
        AND oi.redeemed_at <  CURRENT_DATE + INTERVAL '1 day'
        AND (
          oi.redeemed_merchant_id = p_merchant_id
          OR (
            oi.redeemed_merchant_id IS NULL
            AND (
              oi.purchased_merchant_id = p_merchant_id
              OR p_merchant_id = ANY(oi.applicable_store_ids)
            )
          )
        )
    ) AS today_revenue,

    -- pending_coupons：全部未核销的 order_items 数（不限今日）
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
$function$;

GRANT EXECUTE ON FUNCTION public.get_merchant_daily_stats(uuid)
  TO authenticated, service_role;
