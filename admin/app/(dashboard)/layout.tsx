import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getServiceRoleClient } from '@/lib/supabase/service'
import DashboardShell from '@/components/dashboard-shell'
import { fetchPendingApprovalCounts, totalPendingApprovals } from '@/lib/admin-approval-counts'

/** 待审批总数：与 /approvals 页一致（含 Stripe 解绑等），避免角标与列表不一致 */
async function getPendingCount(): Promise<number> {
  const db = getServiceRoleClient()
  const counts = await fetchPendingApprovalCounts(db)
  return totalPendingApprovals(counts)
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
