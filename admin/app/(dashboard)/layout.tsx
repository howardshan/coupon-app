import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getServiceRoleClient } from '@/lib/supabase/service'
import Sidebar from '@/components/sidebar'
import { unstable_cache } from 'next/cache'
import { APPROVALS_PENDING_COUNT_TAG } from '@/lib/approvals-cache-tag'

// 查询待审批总数，5 分钟缓存，避免每次渲染都触发 4 个数据库查询
const getPendingCount = unstable_cache(
  async () => {
    const db = getServiceRoleClient()
    const [merchantRes, dealRes, refundRes, afterSalesRes] = await Promise.all([
      db.from('merchants').select('id', { count: 'exact', head: true }).eq('status', 'pending'),
      db.from('deals').select('id', { count: 'exact', head: true }).eq('deal_status', 'pending'),
      db.from('refund_requests').select('id', { count: 'exact', head: true }).eq('status', 'pending_admin'),
      db.from('after_sales_requests').select('id', { count: 'exact', head: true }).eq('status', 'awaiting_platform'),
    ])
    return (merchantRes.count ?? 0)
      + (dealRes.count ?? 0)
      + (refundRes.count ?? 0)
      + (afterSalesRes.count ?? 0)
  },
  ['approvals-pending-count'],
  { revalidate: 300, tags: [APPROVALS_PENDING_COUNT_TAG] }
)

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
    <div className="flex min-h-screen bg-gray-50">
      <Sidebar role={profile.role} email={profile.email} pendingCount={pendingCount} />
      <main className="flex-1 p-8 overflow-auto">{children}</main>
    </div>
  )
}
