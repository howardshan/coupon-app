-- =============================================================
-- Admin 订单搜索 RPC：在数据库内做 ILIKE，避免 query 参数中 % 的编码问题
-- 依赖：is_current_user_admin() 已由 20260304000000 提供
-- =============================================================

CREATE OR REPLACE FUNCTION public.get_admin_orders_search(search_q text)
RETURNS setof json
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_current_user_admin() THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT json_build_object(
    'id', o.id,
    'order_number', o.order_number,
    'total_amount', o.total_amount,
    'quantity', o.quantity,
    'status', o.status,
    'refund_reason', o.refund_reason,
    'created_at', o.created_at,
    'users', json_build_object('email', u.email),
    'deals', json_build_object(
      'title', d.title,
      'merchants', json_build_object('name', m.name)
    )
  )
  FROM public.orders o
  LEFT JOIN public.users u ON u.id = o.user_id
  LEFT JOIN public.deals d ON d.id = o.deal_id
  LEFT JOIN public.merchants m ON m.id = d.merchant_id
  WHERE (search_q IS NULL OR search_q = '' OR (
    o.order_number ILIKE '%' || search_q || '%'
    OR u.email ILIKE '%' || search_q || '%'
    OR d.title ILIKE '%' || search_q || '%'
  ))
  ORDER BY o.created_at DESC
  LIMIT 100;
END;
$$;
