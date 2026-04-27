-- ============================================================
-- 修复：受赠人持有的赠送券在 To Use (unused) Tab 显示
-- 之前：unused 分支排除 customer_status = 'gifted' 的所有券
-- 现在：若 current_holder_user_id = auth.uid()（受赠人视角），归入 unused Tab
--       gifted Tab 只显示赠送出去的券（current_holder 已是对方）
-- ============================================================

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
        AND (
          oi.customer_status IS NULL
          OR oi.customer_status = 'unused'
          -- 受赠人持有的赠送券也归入 unused Tab
          OR (oi.customer_status = 'gifted' AND c.current_holder_user_id = auth.uid())
        )
      WHEN 'expired' THEN
        (c.status = 'expired' OR c.expires_at < now())
        AND (c.status <> 'voided' OR (c.status = 'voided' AND c.void_reason = 'gifted'))
      WHEN 'gifted' THEN
        -- 只显示赠送出去的券（current_holder 已是对方，不是自己）
        oi.customer_status = 'gifted'
        AND (c.current_holder_user_id IS NULL OR c.current_holder_user_id <> auth.uid())
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
  'My Coupons 分页：按 Tab 返回券 id（auth.uid），游标为上一页最后一条的 (created_at, id)。受赠人持有的赠送券在 unused Tab 显示。';

GRANT EXECUTE ON FUNCTION public.fetch_my_coupon_ids_page(text, int, timestamptz, uuid) TO authenticated;
