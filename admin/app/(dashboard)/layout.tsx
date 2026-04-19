import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getServiceRoleClient } from '@/lib/supabase/service'
import DashboardShell from '@/components/dashboard-shell'

/** 待审批总数：与 /approvals 页 fetchCounts 一致，每次布局请求实时查询，避免角标与列表不一致 */
async function getPendingCount(): Promise<number> {
  const db = getServiceRoleClient()
  const [merchantRes, dealRes, refundRes, afterSalesRes] = await Promise.all([
    db.from('merchants').select('id', { count: 'exact', head: true }).eq('status', 'pending'),
    db.from('deals').select('id', { count: 'exact', head: true }).eq('deal_status', 'pending'),
    db.from('refund_requests').select('id', { count: 'exact', head: true }).eq('status', 'pending_admin'),
    db.from('after_sales_requests').select('id', { count: 'exact', head: true }).eq('status', 'awaiting_platform'),
  ])
  return (
    (merchantRes.count ?? 0) +
    (dealRes.count ?? 0) +
    (refundRes.count ?? 0) +
    (afterSalesRes.count ?? 0)
  )
}

export default async function DashboardLayout({ children }: { children: React.ReactNode }) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()

  if (!user) redirect('/login')

  const { data: profile } = await supabase
    .from('users')
    .select('role, email')
    .eq('id', user.id)
    .single()

  if (!profile || (profile.role !== 'admin' && profile.role !== 'merchant')) {
    redirect('/login')
  }

  // 仅 admin 需要角标数量
  const pendingCount = profile.role === 'admin' ? await getPendingCount() : 0

  return (
    <DashboardShell role={profile.role} email={profile.email ?? ''} pendingCount={pendingCount}>
      {children}
    </DashboardShell>
  )
}
