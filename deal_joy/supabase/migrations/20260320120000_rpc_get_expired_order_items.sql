-- ============================================================
-- RPC: get_expired_order_items
-- 供 auto-refund-expired Edge Function 调用
-- 查找所有 customer_status = 'unused' 且 coupon 已过期的 order_items
-- 返回扁平结构，包含 user_id 和金额字段
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_expired_order_items(
  p_limit int DEFAULT 50
)
RETURNS TABLE (
  id            uuid,
  order_id      uuid,
  user_id       uuid,
  unit_price    numeric,
  service_fee   numeric,
  coupon_id     uuid,
  expires_at    timestamptz
)
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT
    oi.id,
    oi.order_id,
    o.user_id,
    oi.unit_price,
    oi.service_fee,
    c.id        AS coupon_id,
    c.expires_at
  FROM public.order_items oi
  JOIN public.coupons c ON c.order_item_id = oi.id
  JOIN public.orders  o ON o.id = oi.order_id
  WHERE oi.customer_status = 'unused'
    AND c.expires_at < now()
  ORDER BY c.expires_at ASC
  LIMIT p_limit;
$$;

-- 仅允许 service_role 调用（Edge Function 用 service_role key）
REVOKE ALL ON FUNCTION public.get_expired_order_items(int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_expired_order_items(int) TO service_role;
