-- My Coupons 列表：按 Tab 过滤 + 游标分页（仅返回 id + created_at），客户端再 select 富集
-- 与客户端 coupons_provider 各 Tab 过滤语义对齐

CREATE OR REPLACE FUNCTION public.fetch_my_coupon_ids_page(
  p_tab text,
  p_limit int DEFAULT 20,
  p_cursor_created_at timestamptz DEFAULT NULL,
  p_cursor_id uuid DEFAULT NULL
)
RETURNS TABLE (id uuid, created_at timestamptz)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT c.id, c.created_at
  FROM public.coupons c
  LEFT JOIN public.order_items oi ON oi.id = c.order_item_id
  WHERE (c.user_id = auth.uid() OR c.current_holder_user_id = auth.uid())
  AND (
    CASE p_tab
      WHEN 'used' THEN
        c.status = 'used'
      WHEN 'refunded' THEN
        c.status = 'refunded' AND c.expires_at > now()
      WHEN 'unused' THEN
        c.status = 'unused'
        AND c.expires_at > now()
        AND c.order_item_id IS NOT NULL
        AND oi.id IS NOT NULL
        AND oi.refunded_at IS NULL
        AND (oi.customer_status IS NULL OR oi.customer_status = 'unused')
      WHEN 'expired' THEN
        (c.status = 'expired' OR c.expires_at < now())
        AND (c.status <> 'voided' OR (c.status = 'voided' AND c.void_reason = 'gifted'))
      WHEN 'gifted' THEN
        oi.customer_status = 'gifted'
      ELSE FALSE
    END
  )
  AND (
    p_cursor_created_at IS NULL
    OR c.created_at < p_cursor_created_at
    OR (c.created_at = p_cursor_created_at AND c.id < p_cursor_id)
  )
  ORDER BY c.created_at DESC, c.id DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 20), 1), 100);
$$;

COMMENT ON FUNCTION public.fetch_my_coupon_ids_page IS
  'My Coupons 分页：按 Tab 返回券 id（auth.uid），游标为上一页最后一条的 (created_at, id)。';

GRANT EXECUTE ON FUNCTION public.fetch_my_coupon_ids_page(text, int, timestamptz, uuid) TO authenticated;

-- 按订单统计「仍符合 Unused Tab」的未使用券数量（用于 Used/Expired 订单卡片）
CREATE OR REPLACE FUNCTION public.fetch_unused_voucher_counts_for_orders(p_order_ids uuid[])
RETURNS TABLE (order_id uuid, unused_count bigint)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT c.order_id, COUNT(*)::bigint
  FROM public.coupons c
  INNER JOIN public.order_items oi ON oi.id = c.order_item_id
  WHERE (c.user_id = auth.uid() OR c.current_holder_user_id = auth.uid())
  AND c.order_id = ANY(p_order_ids)
  AND c.status = 'unused'
  AND c.expires_at > now()
  AND c.order_item_id IS NOT NULL
  AND oi.refunded_at IS NULL
  AND (oi.customer_status IS NULL OR oi.customer_status = 'unused')
  GROUP BY c.order_id;
$$;

COMMENT ON FUNCTION public.fetch_unused_voucher_counts_for_orders IS
  '给定订单 ID 列表，返回每单当前 Unused Tab 口径下的未使用券数量。';

GRANT EXECUTE ON FUNCTION public.fetch_unused_voucher_counts_for_orders(uuid[]) TO authenticated;
