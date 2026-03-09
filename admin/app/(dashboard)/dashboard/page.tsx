import { createClient } from '@/lib/supabase/server'

async function getStats() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  const { data: profile } = await supabase.from('users').select('role').eq('id', user!.id).single()

  if (profile?.role === 'admin') {
    const [
      { count: userCount },
      { count: merchantCount },
      { count: dealCount },
      { count: brandCount },
      { count: pendingMerchantCount },
      { count: refundCount },
    ] = await Promise.all([
      supabase.from('users').select('*', { count: 'exact', head: true }),
      supabase.from('merchants').select('*', { count: 'exact', head: true }),
      supabase.from('deals').select('*', { count: 'exact', head: true }),
      supabase.from('brands').select('*', { count: 'exact', head: true }),
      supabase.from('merchants').select('*', { count: 'exact', head: true }).eq('status', 'pending'),
      supabase.from('orders').select('*', { count: 'exact', head: true }).eq('status', 'refund_requested'),
    ])
    return { role: 'admin', userCount, merchantCount, dealCount, brandCount, pendingMerchantCount, refundCount }
  } else {
    const { data: merchant } = await supabase.from('merchants').select('id, name').eq('user_id', user!.id).single()
    if (!merchant) return { role: 'merchant', merchantName: null, dealCount: 0, orderCount: 0 }

    const [{ count: dealCount }, { count: orderCount }] = await Promise.all([
      supabase.from('deals').select('*', { count: 'exact', head: true }).eq('merchant_id', merchant.id),
      supabase.from('orders').select('*', { count: 'exact', head: true }).eq('merchant_id', merchant.id),
    ])
    return { role: 'merchant', merchantName: merchant.name, dealCount, orderCount }
  }
}

export default async function DashboardPage() {
  const stats = await getStats()

  return (
    <div>
      <h1 className="text-2xl font-bold text-gray-900 mb-6">Overview</h1>

      {stats.role === 'admin' ? (
        <>
          <div className="grid grid-cols-4 gap-4">
            <StatCard label="Total Users" value={stats.userCount ?? 0} color="blue" />
            <StatCard label="Total Merchants" value={stats.merchantCount ?? 0} color="green" />
            <StatCard label="Total Deals" value={stats.dealCount ?? 0} color="purple" />
            <StatCard label="Total Brands" value={stats.brandCount ?? 0} color="orange" />
          </div>
          <div className="mt-6 bg-white rounded-xl border border-gray-200 p-6">
            <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-4">Pending</h2>
            <div className="grid grid-cols-2 gap-4">
              <a
                href="/merchants"
                className="block rounded-xl border border-gray-200 p-6 hover:border-yellow-300 hover:bg-yellow-50/50 transition-colors"
              >
                <p className="text-sm text-gray-500">Merchants pending review</p>
                <p className="text-3xl font-bold mt-1 text-yellow-700">{stats.pendingMerchantCount ?? 0}</p>
              </a>
              <a
                href="/orders"
                className="block rounded-xl border border-gray-200 p-6 hover:border-orange-300 hover:bg-orange-50/50 transition-colors"
              >
                <p className="text-sm text-gray-500">Refund requests pending</p>
                <p className="text-3xl font-bold mt-1 text-orange-700">{stats.refundCount ?? 0}</p>
              </a>
            </div>
          </div>
        </>
      ) : (
        <div>
          {stats.merchantName && (
            <p className="text-gray-500 mb-4">Store: <span className="font-medium text-gray-900">{stats.merchantName}</span></p>
          )}
          <div className="grid grid-cols-2 gap-4">
            <StatCard label="Active Deals" value={stats.dealCount ?? 0} color="blue" />
            <StatCard label="Total Orders" value={stats.orderCount ?? 0} color="green" />
          </div>
        </div>
      )}
    </div>
  )
}

function StatCard({ label, value, color }: { label: string; value: number; color: string }) {
  const colors: Record<string, string> = {
    blue: 'text-blue-700',
    green: 'text-green-700',
    purple: 'text-purple-700',
    orange: 'text-orange-700',
  }
  return (
    <div className="bg-white rounded-xl border border-gray-200 p-6">
      <p className="text-sm text-gray-500">{label}</p>
      <p className={`text-3xl font-bold mt-1 ${colors[color] ?? 'text-gray-900'}`}>{value}</p>
    </div>
  )
}
