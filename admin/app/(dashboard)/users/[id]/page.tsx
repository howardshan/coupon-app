import { createClient } from '@/lib/supabase/server'
import { getServiceRoleClient } from '@/lib/supabase/service'
import { redirect } from 'next/navigation'
import Link from 'next/link'
import BanUserButton from '@/components/ban-user-button'

export default async function UserDetailPage({
  params,
}: {
  params: Promise<{ id: string }>
}) {
  const { id } = await params
  const supabase = await createClient()
  const { data: { user: currentUser } } = await supabase.auth.getUser()
  const { data: profile } = await supabase.from('users').select('role').eq('id', currentUser!.id).single()

  if (profile?.role !== 'admin') redirect('/dashboard')

  const serviceClient = getServiceRoleClient()

  // 用户基本信息
  const { data: userInfo } = await supabase
    .from('users')
    .select('id, email, full_name, role, avatar_url, bio, phone, created_at, updated_at')
    .eq('id', id)
    .single()

  if (!userInfo) {
    return (
      <div>
        <p className="text-gray-500">User not found.</p>
        <Link href="/users" className="mt-3 inline-flex items-center gap-2 px-4 py-2 text-sm font-medium rounded-lg border border-gray-300 bg-white text-gray-700 shadow-sm hover:bg-gray-50">
          ← Back to Users
        </Link>
      </div>
    )
  }

  // 检查是否被封禁（通过 auth.users 的 banned_until）
  const { data: authUser } = await serviceClient.auth.admin.getUserById(id)
  const bannedUntil = authUser?.user?.banned_until
  const isBanned = bannedUntil && new Date(bannedUntil) > new Date()

  // 购买记录（orders）— 用 service client 绕过 RLS
  const { data: orders } = await serviceClient
    .from('orders')
    .select('id, deal_id, quantity, total_price, status, created_at, deals(title, merchants(name))')
    .eq('user_id', id)
    .order('created_at', { ascending: false })
    .limit(50)

  // 券使用记录（coupons）— 用 service client 绕过 RLS
  const { data: coupons } = await serviceClient
    .from('coupons')
    .select('id, deal_id, status, qr_code, used_at, expires_at, created_at, void_reason, voided_at, deals(title, merchants(name))')
    .eq('user_id', id)
    .order('created_at', { ascending: false })
    .limit(50)

  // 统计
  const totalSpent = orders?.reduce((sum, o) => sum + (o.total_price ?? 0), 0) ?? 0
  const totalOrders = orders?.length ?? 0
  const usedCoupons = coupons?.filter(c => c.status === 'used').length ?? 0
  const activeCoupons = coupons?.filter(c => c.status === 'active').length ?? 0

  return (
    <div className="space-y-6">
      {/* 顶部导航 */}
      <Link href="/users" className="inline-flex items-center gap-2 text-sm text-gray-500 hover:text-gray-700">
        ← Back to Users
      </Link>

      {/* 用户信息卡片 */}
      <div className="bg-white rounded-xl border border-gray-200 p-6">
        <div className="flex items-start justify-between">
          <div className="flex items-center gap-4">
            {userInfo.avatar_url ? (
              <img src={userInfo.avatar_url} alt="" className="w-16 h-16 rounded-full object-cover border-2 border-gray-200" />
            ) : (
              <div className="w-16 h-16 rounded-full bg-gray-200 flex items-center justify-center text-2xl text-gray-400">
                {(userInfo.full_name || userInfo.email)?.[0]?.toUpperCase() || '?'}
              </div>
            )}
            <div>
              <h1 className="text-xl font-bold text-gray-900">{userInfo.full_name || '—'}</h1>
              <p className="text-sm text-gray-500">{userInfo.email}</p>
              {userInfo.phone && <p className="text-sm text-gray-500">{userInfo.phone}</p>}
              {userInfo.bio && <p className="text-sm text-gray-400 mt-1">{userInfo.bio}</p>}
            </div>
          </div>
          <div className="flex items-center gap-3">
            <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${
              userInfo.role === 'admin' ? 'bg-red-100 text-red-700' :
              userInfo.role === 'merchant' ? 'bg-blue-100 text-blue-700' :
              'bg-gray-100 text-gray-600'
            }`}>
              {userInfo.role}
            </span>
            {isBanned && (
              <span className="px-2 py-0.5 rounded-full text-xs font-medium bg-red-100 text-red-700">
                Banned until {new Date(bannedUntil).toLocaleDateString()}
              </span>
            )}
          </div>
        </div>

        {/* 统计数据 */}
        <div className="grid grid-cols-4 gap-4 mt-6 pt-6 border-t border-gray-100">
          <div>
            <p className="text-xs text-gray-500">Total Orders</p>
            <p className="text-lg font-semibold text-gray-900">{totalOrders}</p>
          </div>
          <div>
            <p className="text-xs text-gray-500">Total Spent</p>
            <p className="text-lg font-semibold text-gray-900">${totalSpent.toFixed(2)}</p>
          </div>
          <div>
            <p className="text-xs text-gray-500">Active Coupons</p>
            <p className="text-lg font-semibold text-gray-900">{activeCoupons}</p>
          </div>
          <div>
            <p className="text-xs text-gray-500">Used Coupons</p>
            <p className="text-lg font-semibold text-gray-900">{usedCoupons}</p>
          </div>
        </div>

        {/* 日期信息 */}
        <div className="flex gap-6 mt-4 pt-4 border-t border-gray-100 text-xs text-gray-400">
          <span>Joined: {new Date(userInfo.created_at).toLocaleDateString()}</span>
          {userInfo.updated_at && <span>Last updated: {new Date(userInfo.updated_at).toLocaleDateString()}</span>}
        </div>
      </div>

      {/* 黑名单操作 */}
      <div className="bg-white rounded-xl border border-gray-200 p-6">
        <h2 className="text-base font-semibold text-gray-900 mb-4">Account Actions</h2>
        <BanUserButton userId={id} isBanned={!!isBanned} bannedUntil={bannedUntil ?? null} />
      </div>

      {/* 购买记录 */}
      <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
        <div className="px-4 py-3 border-b border-gray-200 bg-gray-50">
          <h2 className="text-base font-semibold text-gray-900">Purchase History ({totalOrders})</h2>
        </div>
        {orders && orders.length > 0 ? (
          <table className="w-full text-sm">
            <thead className="bg-gray-50 border-b border-gray-200">
              <tr>
                <th className="text-left px-4 py-2 font-medium text-gray-600">Deal</th>
                <th className="text-left px-4 py-2 font-medium text-gray-600">Merchant</th>
                <th className="text-left px-4 py-2 font-medium text-gray-600">Qty</th>
                <th className="text-left px-4 py-2 font-medium text-gray-600">Total</th>
                <th className="text-left px-4 py-2 font-medium text-gray-600">Status</th>
                <th className="text-left px-4 py-2 font-medium text-gray-600">Date</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {orders.map(o => (
                <tr key={o.id} className="hover:bg-gray-50">
                  <td className="px-4 py-2 text-gray-900">
                    <Link href={`/orders/${o.id}`} className="text-blue-600 hover:underline">
                      {(o.deals as any)?.title ?? '—'}
                    </Link>
                  </td>
                  <td className="px-4 py-2 text-gray-600">{(o.deals as any)?.merchants?.name ?? '—'}</td>
                  <td className="px-4 py-2 text-gray-600">{o.quantity ?? 1}</td>
                  <td className="px-4 py-2 text-gray-900 font-medium">${(o.total_price ?? 0).toFixed(2)}</td>
                  <td className="px-4 py-2">
                    <OrderStatusBadge status={o.status} />
                  </td>
                  <td className="px-4 py-2 text-gray-500">{new Date(o.created_at).toLocaleDateString()}</td>
                </tr>
              ))}
            </tbody>
          </table>
        ) : (
          <p className="text-center text-gray-400 py-8">No orders found</p>
        )}
      </div>

      {/* 券使用记录 */}
      <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
        <div className="px-4 py-3 border-b border-gray-200 bg-gray-50">
          <h2 className="text-base font-semibold text-gray-900">Coupon Records ({coupons?.length ?? 0})</h2>
        </div>
        {coupons && coupons.length > 0 ? (
          <table className="w-full text-sm">
            <thead className="bg-gray-50 border-b border-gray-200">
              <tr>
                <th className="text-left px-4 py-2 font-medium text-gray-600">Deal</th>
                <th className="text-left px-4 py-2 font-medium text-gray-600">Merchant</th>
                <th className="text-left px-4 py-2 font-medium text-gray-600">Status</th>
                <th className="text-left px-4 py-2 font-medium text-gray-600">Used At</th>
                <th className="text-left px-4 py-2 font-medium text-gray-600">Expires</th>
                <th className="text-left px-4 py-2 font-medium text-gray-600">Created</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {coupons.map(c => (
                <tr key={c.id} className="hover:bg-gray-50">
                  <td className="px-4 py-2 text-gray-900">{(c.deals as any)?.title ?? '—'}</td>
                  <td className="px-4 py-2 text-gray-600">{(c.deals as any)?.merchants?.name ?? '—'}</td>
                  <td className="px-4 py-2">
                    <CouponStatusBadge status={c.status} />
                  </td>
                  <td className="px-4 py-2 text-gray-500">
                    {c.used_at ? new Date(c.used_at).toLocaleDateString() : '—'}
                  </td>
                  <td className="px-4 py-2 text-gray-500">
                    {c.expires_at ? new Date(c.expires_at).toLocaleDateString() : '—'}
                  </td>
                  <td className="px-4 py-2 text-gray-500">{new Date(c.created_at).toLocaleDateString()}</td>
                </tr>
              ))}
            </tbody>
          </table>
        ) : (
          <p className="text-center text-gray-400 py-8">No coupons found</p>
        )}
      </div>
    </div>
  )
}

// 订单状态 Badge
function OrderStatusBadge({ status }: { status: string }) {
  const styles: Record<string, string> = {
    paid: 'bg-green-100 text-green-700',
    pending: 'bg-yellow-100 text-yellow-700',
    refunded: 'bg-red-100 text-red-700',
    voided: 'bg-gray-100 text-gray-600',
    captured: 'bg-blue-100 text-blue-700',
  }
  return (
    <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${styles[status] ?? 'bg-gray-100 text-gray-600'}`}>
      {status}
    </span>
  )
}

// 券状态 Badge
function CouponStatusBadge({ status }: { status: string }) {
  const styles: Record<string, string> = {
    active: 'bg-green-100 text-green-700',
    used: 'bg-blue-100 text-blue-700',
    expired: 'bg-gray-100 text-gray-600',
    refunded: 'bg-red-100 text-red-700',
    voided: 'bg-gray-100 text-gray-600',
    gifted: 'bg-purple-100 text-purple-700',
  }
  return (
    <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${styles[status] ?? 'bg-gray-100 text-gray-600'}`}>
      {status}
    </span>
  )
}
