-- =============================================================
-- Admin 订单：搜索 RPC 增加 deal_id、筛选、分页；新增 count RPC
-- =============================================================

CREATE OR REPLACE FUNCTION public.get_admin_orders_search(
  search_q text DEFAULT NULL,
  p_merchant_id uuid DEFAULT NULL,
  p_status text[] DEFAULT NULL,
  p_date_from timestamptz DEFAULT NULL,
  p_date_to timestamptz DEFAULT NULL,
  p_amount_min numeric DEFAULT NULL,
  p_amount_max numeric DEFAULT NULL,
  p_sort text DEFAULT 'date_desc',
  p_limit int DEFAULT 20,
  p_offset int DEFAULT 0
)
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
    'refund_rejected_at', o.refund_rejected_at,
    'created_at', o.created_at,
    'deal_expires_at', d.expires_at,
    'coupon_expires_at', c.expires_at,
    'users', json_build_object('email', u.email),
    'deals', json_build_object(
      'id', d.id,
      'title', d.title,
      'expires_at', d.expires_at,
      'merchants', json_build_object('name', m.name)
    )
  )
  FROM public.orders o
  LEFT JOIN public.users u ON u.id = o.user_id
  LEFT JOIN public.deals d ON d.id = o.deal_id
  LEFT JOIN public.merchants m ON m.id = d.merchant_id
  LEFT JOIN public.coupons c ON c.id = o.coupon_id
  WHERE (search_q IS NULL OR search_q = '' OR (
    o.order_number ILIKE '%' || search_q || '%'
    OR u.email ILIKE '%' || search_q || '%'
    OR d.title ILIKE '%' || search_q || '%'
  ))
  AND (p_merchant_id IS NULL OR d.merchant_id = p_merchant_id)
  AND (p_status IS NULL OR array_length(p_status, 1) IS NULL OR o.status = ANY(p_status))
  AND (p_date_from IS NULL OR o.created_at >= p_date_from)
  AND (p_date_to IS NULL OR o.created_at < (p_date_to + interval '1 day'))
  AND (p_amount_min IS NULL OR o.total_amount >= p_amount_min)
  AND (p_amount_max IS NULL OR o.total_amount <= p_amount_max)
  ORDER BY
    CASE WHEN p_sort = 'amount_asc' THEN o.total_amount END ASC NULLS LAST,
    CASE WHEN p_sort = 'amount_desc' THEN o.total_amount END DESC NULLS LAST,
    CASE WHEN p_sort = 'date_asc' THEN o.created_at END ASC NULLS LAST,
    o.created_at DESC NULLS LAST
  LIMIT NULLIF(greatest(1, least(100, COALESCE(p_limit, 20))), 0)
  OFFSET greatest(0, COALESCE(p_offset, 0));
END;
$$;

CREATE OR REPLACE FUNCTION public.get_admin_orders_count(
  search_q text DEFAULT NULL,
  p_merchant_id uuid DEFAULT NULL,
  p_status text[] DEFAULT NULL,
  p_date_from timestamptz DEFAULT NULL,
  p_date_to timestamptz DEFAULT NULL,
  p_amount_min numeric DEFAULT NULL,
  p_amount_max numeric DEFAULT NULL
)
RETURNS bigint
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count bigint;
BEGIN
  IF NOT public.is_current_user_admin() THEN
    RETURN 0;
  END IF;

  SELECT count(*)::bigint INTO v_count
  FROM public.orders o
  LEFT JOIN public.users u ON u.id = o.user_id
  LEFT JOIN public.deals d ON d.id = o.deal_id
  WHERE (search_q IS NULL OR search_q = '' OR (
    o.order_number ILIKE '%' || search_q || '%'
    OR u.email ILIKE '%' || search_q || '%'
    OR d.title ILIKE '%' || search_q || '%'
  ))
  AND (p_merchant_id IS NULL OR d.merchant_id = p_merchant_id)
  AND (p_status IS NULL OR array_length(p_status, 1) IS NULL OR o.status = ANY(p_status))
  AND (p_date_from IS NULL OR o.created_at >= p_date_from)
  AND (p_date_to IS NULL OR o.created_at < (p_date_to + interval '1 day'))
  AND (p_amount_min IS NULL OR o.total_amount >= p_amount_min)
  AND (p_amount_max IS NULL OR o.total_amount <= p_amount_max);

  RETURN v_count;
END;
$$;
