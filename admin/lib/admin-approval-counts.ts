import { getServiceRoleClient } from '@/lib/supabase/service'

type ServiceDb = ReturnType<typeof getServiceRoleClient>

export type PendingApprovalCounts = {
  merchants: number
  deals: number
  refundDisputes: number
  afterSales: number
  stripeUnlink: number
}

/**
 * 与侧栏 Approvals 角标、/approvals 页 tab 角标使用相同查询，保证数字一致。
 */
export async function fetchPendingApprovalCounts(db: ServiceDb): Promise<PendingApprovalCounts> {
  const [merchantRes, dealRes, refundRes, afterSalesRes, stripeUnlinkRes] = await Promise.all([
    db.from('merchants').select('id', { count: 'exact', head: true }).eq('status', 'pending'),
    db.from('deals').select('id', { count: 'exact', head: true }).eq('deal_status', 'pending'),
    db.from('refund_requests').select('id', { count: 'exact', head: true }).eq('status', 'pending_admin'),
    db.from('after_sales_requests').select('id', { count: 'exact', head: true }).eq('status', 'awaiting_platform'),
    db
      .from('stripe_connect_unlink_requests')
      .select('id', { count: 'exact', head: true })
      .eq('status', 'pending'),
  ])
  return {
    merchants: merchantRes.count ?? 0,
    deals: dealRes.count ?? 0,
    refundDisputes: refundRes.count ?? 0,
    afterSales: afterSalesRes.count ?? 0,
    stripeUnlink: stripeUnlinkRes.count ?? 0,
  }
}

export function totalPendingApprovals(c: PendingApprovalCounts): number {
  return c.merchants + c.deals + c.refundDisputes + c.afterSales + c.stripeUnlink
}
