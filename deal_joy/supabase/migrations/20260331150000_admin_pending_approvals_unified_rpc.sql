-- 审批中心 /approvals All Tab：四类待办按 created_at 全局排序后 LIMIT/OFFSET 分页
-- 仅 service_role 可执行（Admin Next 使用 service role client）
-- 总条数与页面角标一致，由客户端已有 fetchCounts 四类 count 相加，不单独 RPC count

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
  )
  SELECT u.approval_kind, u.entity_id, u.sort_at
  FROM unified u
  ORDER BY u.sort_at ASC, u.entity_id ASC
  LIMIT LEAST(GREATEST(p_limit, 1), 100)
  OFFSET GREATEST(p_offset, 0);
$$;

COMMENT ON FUNCTION public.admin_pending_approvals_unified_page(integer, integer) IS '审批中心 All Tab：按 sort_at 全局分页';

REVOKE ALL ON FUNCTION public.admin_pending_approvals_unified_page(integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_pending_approvals_unified_page(integer, integer) TO service_role;
