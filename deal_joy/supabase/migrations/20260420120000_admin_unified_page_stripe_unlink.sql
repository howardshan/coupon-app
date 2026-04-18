-- 审批中心 /approvals All Tab：在统一 RPC 中纳入 stripe_connect_unlink_requests（pending）
-- 与 admin/app/(dashboard)/approvals/page.tsx 中 fetchUnifiedAllTab 的 approval_kind 一致

CREATE OR REPLACE FUNCTION public.admin_pending_approvals_unified_page(
  p_limit integer,
  p_offset integer
)
RETURNS TABLE (
  approval_kind text,
  entity_id uuid,
  sort_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH unified AS (
    SELECT 'merchant'::text AS approval_kind, m.id AS entity_id, m.created_at AS sort_at
    FROM public.merchants m
    WHERE m.status = 'pending'
    UNION ALL
    SELECT 'deal'::text, d.id, d.created_at
    FROM public.deals d
    WHERE d.deal_status = 'pending'
    UNION ALL
    SELECT 'refund_dispute'::text, rr.id, rr.created_at
    FROM public.refund_requests rr
    WHERE rr.status = 'pending_admin'
    UNION ALL
    SELECT 'after_sales'::text, a.id, a.created_at
    FROM public.after_sales_requests a
    WHERE a.status = 'awaiting_platform'
    UNION ALL
    SELECT 'stripe_unlink'::text, s.id, s.created_at
    FROM public.stripe_connect_unlink_requests s
    WHERE s.status = 'pending'
  )
  SELECT u.approval_kind, u.entity_id, u.sort_at
  FROM unified u
  ORDER BY u.sort_at ASC, u.entity_id ASC
  LIMIT LEAST(GREATEST(p_limit, 1), 100)
  OFFSET GREATEST(p_offset, 0);
$$;

COMMENT ON FUNCTION public.admin_pending_approvals_unified_page(integer, integer) IS
  '审批中心 All Tab：五类待办按 sort_at 全局分页（含 Stripe Unlink pending）';

REVOKE ALL ON FUNCTION public.admin_pending_approvals_unified_page(integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_pending_approvals_unified_page(integer, integer) TO service_role;
