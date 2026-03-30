import { createClient } from '@/lib/supabase/server'
import { getServiceRoleClient } from '@/lib/supabase/service'
import { redirect, notFound } from 'next/navigation'
import Link from 'next/link'
import AddBrandAdminForm from '@/components/add-brand-admin-form'
import AddStoreToBrand from '@/components/add-store-to-brand'
import BrandCommissionForm from '@/components/brand-commission-form'
import RemoveBrandAdminButton from './remove-brand-admin-button'
import RemoveStoreButton from './remove-store-button'

export default async function BrandDetailPage({
  params,
}: {
  params: Promise<{ id: string }>
}) {
  const { id } = await params
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  const { data: profile } = await supabase.from('users').select('role').eq('id', user!.id).single()

  if (profile?.role !== 'admin') redirect('/dashboard')

  // 使用 service role client 绕过 RLS（admin 页面需要读取所有数据）
  const adminDb = getServiceRoleClient()

  // 品牌基本信息
  const { data: brand } = await adminDb
    .from('brands')
    .select('id, name, logo_url, commission_rate, stripe_account_id, stripe_account_status, created_at')
    .eq('id', id)
    .single()

  if (!brand) notFound()

  // 品牌下所有门店
  const { data: stores } = await adminDb
    .from('merchants')
    .select('id, name, category, status, address, created_at')
    .eq('brand_id', id)
    .order('created_at', { ascending: false })

  // 品牌管理员（brand_admins.user_id 指向 auth.users，无法直接 join public.users）
  const { data: rawBrandAdmins } = await adminDb
    .from('brand_admins')
    .select('id, user_id, role, created_at')
    .eq('brand_id', id)
    .order('created_at', { ascending: true })

  // 手动补充用户信息
  const brandAdminUserIds = rawBrandAdmins?.map(a => a.user_id) ?? []
  let brandAdminUsers: Record<string, { email: string; full_name: string | null }> = {}
  if (brandAdminUserIds.length > 0) {
    const { data: users } = await adminDb
      .from('users')
      .select('id, email, full_name')
      .in('id', brandAdminUserIds)
    for (const u of users ?? []) {
      brandAdminUsers[u.id] = { email: u.email, full_name: u.full_name }
    }
  }
  const brandAdmins = rawBrandAdmins?.map(a => ({
    ...a,
    users: brandAdminUsers[a.user_id] ?? null,
  })) ?? []

  // 品牌邀请
  const { data: invitations } = await adminDb
    .from('brand_invitations')
    .select('id, email, role, status, created_at, expires_at')
    .eq('brand_id', id)
    .order('created_at', { ascending: false })
    .limit(20)

  // 品牌下所有 staff（merchant_staff.user_id 也指向 auth.users，无法 join public.users）
  const storeIds = stores?.map(s => s.id) ?? []
  let allStaff: any[] = []
  if (storeIds.length > 0) {
    const { data: rawStaff } = await adminDb
      .from('merchant_staff')
      .select('id, merchant_id, user_id, role, is_active, created_at')
      .in('merchant_id', storeIds)
      .order('created_at', { ascending: false })

    // 手动补充 staff 用户信息
    const staffUserIds = rawStaff?.map(s => s.user_id) ?? []
    let staffUsers: Record<string, { email: string; full_name: string | null }> = {}
    if (staffUserIds.length > 0) {
      const { data: users } = await adminDb
        .from('users')
        .select('id, email, full_name')
        .in('id', staffUserIds)
      for (const u of users ?? []) {
        staffUsers[u.id] = { email: u.email, full_name: u.full_name }
      }
    }
    allStaff = (rawStaff ?? []).map(s => ({
      ...s,
      users: staffUsers[s.user_id] ?? null,
    }))
  }

  // 获取品牌本月收入数据
  const monthStart = new Date()
  monthStart.setDate(1)
  const monthStartStr = monthStart.toISOString().slice(0, 10)

  const { data: brandEarnings } = await adminDb.rpc('get_brand_earnings_summary', {
    p_brand_id: id,
    p_month_start: monthStartStr,
  })
  const earnings = brandEarnings?.[0] ?? null

  // 最近交易记录（品牌下所有门店，以券为最小单位）
  type TxnRow = { id: string; orderId: string; orderNumber: string; customerEmail: string; dealTitle: string; storeName: string; storeId: string | null; amount: number; status: string; redeemedAt: string | null; refundedAt: string | null; date: string }
  let brandRecentTxns: TxnRow[] = []
  if (storeIds.length > 0) {
    // V3: 门店 deal 的 order_items
    const { data: dealItems } = await adminDb
      .from('order_items')
      .select('id, order_id, unit_price, customer_status, redeemed_at, refunded_at, created_at, orders(id, order_number, users(id, email)), deals!inner(id, title, merchant_id, merchants(id, name))')
      .in('deals.merchant_id', storeIds)
      .order('created_at', { ascending: false })
      .limit(30)

    // V3: 在门店核销的 order_items
    const { data: redeemedItems } = await adminDb
      .from('order_items')
      .select('id, order_id, unit_price, customer_status, redeemed_at, refunded_at, redeemed_merchant_id, created_at, orders(id, order_number, users(id, email)), deals(id, title, merchant_id, merchants(id, name))')
      .in('redeemed_merchant_id', storeIds)
      .order('created_at', { ascending: false })
      .limit(30)

    // V2 coupons
    const { data: v2Coupons } = await adminDb
      .from('coupons')
      .select('id, order_id, status, used_at, created_at, orders(id, order_number, unit_price, users(id, email)), deals!inner(id, title, merchant_id, merchants(id, name))')
      .is('order_item_id', null)
      .in('deals.merchant_id', storeIds)
      .order('created_at', { ascending: false })
      .limit(30)

    const { data: v2Redeemed } = await adminDb
      .from('coupons')
      .select('id, order_id, status, used_at, created_at, redeemed_at_merchant_id, orders(id, order_number, unit_price, users(id, email)), deals(id, title, merchant_id, merchants(id, name))')
      .is('order_item_id', null)
      .in('redeemed_at_merchant_id', storeIds)
      .order('created_at', { ascending: false })
      .limit(30)

    const txnMap = new Map<string, TxnRow>()
    for (const item of [...(dealItems ?? []), ...(redeemedItems ?? [])]) {
      if (txnMap.has(item.id)) continue
      const o = Array.isArray(item.orders) ? item.orders[0] : item.orders
      const d = Array.isArray(item.deals) ? item.deals[0] : item.deals
      const m = d?.merchants; const store = Array.isArray(m) ? m[0] : m
      const cu = o?.users; const c = Array.isArray(cu) ? cu[0] : cu
      txnMap.set(item.id, {
        id: item.id, orderId: o?.id ?? item.order_id, orderNumber: o?.order_number ?? item.order_id?.slice(0, 8) ?? '—',
        customerEmail: c?.email ?? '—', dealTitle: d?.title ?? '—',
        storeName: store?.name ?? '—', storeId: store?.id ?? null,
        amount: Number(item.unit_price), status: item.customer_status,
        redeemedAt: item.redeemed_at, refundedAt: item.refunded_at, date: item.created_at,
      })
    }
    for (const cp of [...(v2Coupons ?? []), ...(v2Redeemed ?? [])]) {
      const key = `v2_${cp.id}`
      if (txnMap.has(key)) continue
      const o = Array.isArray(cp.orders) ? cp.orders[0] : cp.orders
      const d = Array.isArray(cp.deals) ? cp.deals[0] : cp.deals
      const m = d?.merchants; const store = Array.isArray(m) ? m[0] : m
      const cu = o?.users; const c = Array.isArray(cu) ? cu[0] : cu
      txnMap.set(key, {
        id: cp.id, orderId: o?.id ?? cp.order_id, orderNumber: o?.order_number ?? cp.order_id?.slice(0, 8) ?? '—',
        customerEmail: c?.email ?? '—', dealTitle: d?.title ?? '—',
        storeName: store?.name ?? '—', storeId: store?.id ?? null,
        amount: Number(o?.unit_price ?? 0), status: cp.status,
        redeemedAt: cp.used_at, refundedAt: null, date: cp.created_at,
      })
    }
    brandRecentTxns = Array.from(txnMap.values())
      .sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime())
      .slice(0, 20)
  }

  // 未关联品牌的已通过门店（给 AddStoreToBrand 下拉用）
  const { data: unlinkedStores } = await adminDb
    .from('merchants')
    .select('id, name, category, address')
    .is('brand_id', null)
    .eq('status', 'approved')
    .order('name', { ascending: true })

  return (
    <div>
      <div className="mb-6">
        <Link
          href="/brands"
          className="mb-3 inline-flex items-center gap-2 px-3 py-2 text-sm font-medium rounded-lg border border-gray-300 bg-white text-gray-700 shadow-sm hover:bg-gray-50 transition-colors"
        >
          ← Back to Brands
        </Link>
        <div className="flex items-center gap-4 mt-2">
          {brand.logo_url ? (
            <img src={brand.logo_url} alt="" className="w-12 h-12 rounded-full object-cover border border-gray-200" />
          ) : (
            <div className="w-12 h-12 rounded-full bg-gray-100 flex items-center justify-center text-gray-400 text-lg font-bold">
              {brand.name?.charAt(0)?.toUpperCase() ?? '?'}
            </div>
          )}
          <h1 className="text-2xl font-bold text-gray-900">{brand.name}</h1>
        </div>
      </div>

      <div className="space-y-6">
        {/* 品牌信息 */}
        <div className="bg-white rounded-xl border border-gray-200 p-6">
          <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-3">Brand Info</h2>
          <dl className="grid grid-cols-1 sm:grid-cols-2 gap-3 text-sm">
            <div><dt className="text-gray-500">Name</dt><dd className="font-medium text-gray-900">{brand.name}</dd></div>
            <div><dt className="text-gray-500">Created</dt><dd className="font-medium text-gray-900">{new Date(brand.created_at).toLocaleString()}</dd></div>
            <div><dt className="text-gray-500">Total Stores</dt><dd className="font-medium text-gray-900">{stores?.length ?? 0}</dd></div>
            <div><dt className="text-gray-500">Total Staff</dt><dd className="font-medium text-gray-900">{allStaff.length}</dd></div>
          </dl>
        </div>

        {/* 品牌佣金设置 */}
        <div className="bg-white rounded-xl border border-gray-200 p-6">
          <div className="flex items-center justify-between mb-3">
            <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide">Brand Commission</h2>
            {brand.stripe_account_id && (
              <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${
                brand.stripe_account_status === 'connected' ? 'bg-green-100 text-green-700' :
                brand.stripe_account_status === 'pending' ? 'bg-yellow-100 text-yellow-700' :
                'bg-gray-100 text-gray-500'
              }`}>
                Stripe: {brand.stripe_account_status ?? 'not_connected'}
              </span>
            )}
          </div>
          <p className="text-xs text-gray-400 mb-4">
            Set the commission rate that this brand earns from each redeemed voucher across all member stores.
            The brand commission is deducted from the merchant&apos;s net amount (in addition to platform fee and Stripe fee).
          </p>
          <BrandCommissionForm brandId={id} currentRate={brand.commission_rate} />
        </div>

        {/* 品牌本月收入 */}
        <div className="bg-white rounded-xl border border-gray-200 p-6">
          <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-4">Brand Earnings (This Month)</h2>
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
            <div className="bg-gray-50 rounded-lg p-4">
              <p className="text-xs text-gray-500 mb-1">This Month</p>
              <p className="text-xl font-bold text-orange-600">${(earnings?.total_brand_revenue ?? 0).toFixed(2)}</p>
            </div>
            <div className="bg-gray-50 rounded-lg p-4">
              <p className="text-xs text-gray-500 mb-1">Awaiting Settlement</p>
              <p className="text-xl font-bold text-yellow-600">${(earnings?.pending_settlement ?? 0).toFixed(2)}</p>
            </div>
            <div className="bg-gray-50 rounded-lg p-4">
              <p className="text-xs text-gray-500 mb-1">Paid Out</p>
              <p className="text-xl font-bold text-green-600">${(earnings?.settled_amount ?? 0).toFixed(2)}</p>
            </div>
            <div className="bg-gray-50 rounded-lg p-4">
              <p className="text-xs text-gray-500 mb-1">Refunded</p>
              <p className="text-xl font-bold text-red-500">${(earnings?.refunded_amount ?? 0).toFixed(2)}</p>
            </div>
          </div>
        </div>

        {/* 最近交易（以券为最小单位） */}
        <div className="bg-white rounded-xl border border-gray-200 p-6">
          <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-4">
            Recent Transactions ({brandRecentTxns.length})
          </h2>
          {brandRecentTxns.length > 0 ? (
            <table className="w-full text-sm">
              <thead className="border-b border-gray-200">
                <tr>
                  <th className="text-left pb-2 font-medium text-gray-500">Order #</th>
                  <th className="text-left pb-2 font-medium text-gray-500">Customer</th>
                  <th className="text-left pb-2 font-medium text-gray-500">Deal</th>
                  <th className="text-left pb-2 font-medium text-gray-500">Store</th>
                  <th className="text-right pb-2 font-medium text-gray-500">Amount</th>
                  <th className="text-left pb-2 font-medium text-gray-500">Status</th>
                  <th className="text-left pb-2 font-medium text-gray-500">Action Time</th>
                  <th className="text-left pb-2 font-medium text-gray-500">Date</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {brandRecentTxns.map((t) => {
                  const actionTime = t.redeemedAt ?? t.refundedAt
                  return (
                  <tr key={t.id} className="hover:bg-gray-50">
                    <td className="py-2">
                      <Link href={`/orders/${t.orderId}`} className="text-blue-600 hover:underline font-medium font-mono text-xs">
                        {t.orderNumber}
                      </Link>
                    </td>
                    <td className="py-2 text-gray-600 text-xs">{t.customerEmail}</td>
                    <td className="py-2 text-gray-700 text-xs max-w-[160px] truncate">{t.dealTitle}</td>
                    <td className="py-2 text-xs">
                      {t.storeId ? (
                        <Link href={`/merchants/${t.storeId}`} className="text-blue-600 hover:underline">{t.storeName}</Link>
                      ) : '—'}
                    </td>
                    <td className="py-2 text-gray-900 font-medium text-xs text-right">${t.amount.toFixed(2)}</td>
                    <td className="py-2">
                      <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${
                        t.status === 'unused' ? 'bg-blue-100 text-blue-700'
                        : t.status === 'used' ? 'bg-green-100 text-green-700'
                        : t.status === 'refunded' || t.status === 'refund_success' ? 'bg-purple-100 text-purple-700'
                        : t.status === 'expired' ? 'bg-red-100 text-red-700'
                        : t.status === 'gifted' ? 'bg-pink-100 text-pink-700'
                        : t.status === 'refund_pending' || t.status === 'refund_review' ? 'bg-amber-100 text-amber-700'
                        : 'bg-gray-100 text-gray-600'
                      }`}>
                        {t.status === 'used' ? 'Redeemed' : t.status === 'refund_success' ? 'Refunded' : t.status}
                      </span>
                    </td>
                    <td className="py-2 text-gray-500 text-xs">
                      {actionTime ? new Date(actionTime).toLocaleString() : '—'}
                    </td>
                    <td className="py-2 text-gray-500 text-xs">{new Date(t.date).toLocaleDateString('en-US')}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          ) : (
            <p className="text-sm text-gray-500">No transactions yet.</p>
          )}
        </div>

        {/* 门店列表 */}
        <div className="bg-white rounded-xl border border-gray-200 p-6">
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide">
              Member Stores ({stores?.length ?? 0})
            </h2>
            <AddStoreToBrand brandId={id} availableStores={unlinkedStores ?? []} />
          </div>
          {stores && stores.length > 0 ? (
            <table className="w-full text-sm">
              <thead className="border-b border-gray-200">
                <tr>
                  <th className="text-left pb-2 font-medium text-gray-500">Name</th>
                  <th className="text-left pb-2 font-medium text-gray-500">Category</th>
                  <th className="text-left pb-2 font-medium text-gray-500">Status</th>
                  <th className="text-left pb-2 font-medium text-gray-500">Address</th>
                  <th className="text-right pb-2 font-medium text-gray-500">Action</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {stores.map(s => (
                  <tr key={s.id}>
                    <td className="py-2">
                      <Link href={`/merchants/${s.id}`} className="text-blue-600 hover:underline font-medium">
                        {s.name}
                      </Link>
                    </td>
                    <td className="py-2 text-gray-600">{s.category || '—'}</td>
                    <td className="py-2">
                      <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${
                        s.status === 'approved' ? 'bg-green-100 text-green-700' :
                        s.status === 'rejected' ? 'bg-red-100 text-red-700' :
                        s.status === 'closed' ? 'bg-gray-100 text-gray-500' :
                        'bg-yellow-100 text-yellow-700'
                      }`}>
                        {s.status}
                      </span>
                    </td>
                    <td className="py-2 text-gray-500 text-xs">{s.address || '—'}</td>
                    <td className="py-2 text-right">
                      <RemoveStoreButton merchantId={s.id} brandId={id} storeName={s.name} />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          ) : (
            <p className="text-sm text-gray-500">No stores in this brand.</p>
          )}
        </div>

        {/* 品牌管理员 */}
        <div className="bg-white rounded-xl border border-gray-200 p-6">
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide">
              Brand Admins ({brandAdmins?.length ?? 0})
            </h2>
          </div>
          <div className="mb-4">
            <AddBrandAdminForm brandId={id} />
          </div>
          {brandAdmins && brandAdmins.length > 0 ? (
            <table className="w-full text-sm">
              <thead className="border-b border-gray-200">
                <tr>
                  <th className="text-left pb-2 font-medium text-gray-500">User</th>
                  <th className="text-left pb-2 font-medium text-gray-500">Role</th>
                  <th className="text-left pb-2 font-medium text-gray-500">Since</th>
                  <th className="text-right pb-2 font-medium text-gray-500">Action</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {brandAdmins.map((a: any) => (
                  <tr key={a.id}>
                    <td className="py-2 font-medium text-gray-900">
                      {a.users?.full_name || a.users?.email || a.user_id?.slice(0, 8)}
                    </td>
                    <td className="py-2">
                      <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${
                        a.role === 'owner' ? 'bg-purple-100 text-purple-700' : 'bg-blue-100 text-blue-700'
                      }`}>
                        {a.role}
                      </span>
                    </td>
                    <td className="py-2 text-gray-500">{new Date(a.created_at).toLocaleDateString('en-US')}</td>
                    <td className="py-2 text-right">
                      <RemoveBrandAdminButton brandAdminId={a.id} brandId={id} userName={a.users?.email || 'this admin'} />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          ) : (
            <p className="text-sm text-gray-500">No brand admins.</p>
          )}
        </div>

        {/* 邀请记录 */}
        {invitations && invitations.length > 0 && (
          <div className="bg-white rounded-xl border border-gray-200 p-6">
            <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-4">
              Invitations ({invitations.length})
            </h2>
            <table className="w-full text-sm">
              <thead className="border-b border-gray-200">
                <tr>
                  <th className="text-left pb-2 font-medium text-gray-500">Email</th>
                  <th className="text-left pb-2 font-medium text-gray-500">Role</th>
                  <th className="text-left pb-2 font-medium text-gray-500">Status</th>
                  <th className="text-left pb-2 font-medium text-gray-500">Created</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {invitations.map((inv: any) => (
                  <tr key={inv.id}>
                    <td className="py-2 text-gray-900">{inv.email}</td>
                    <td className="py-2 text-gray-600">{inv.role?.replace('_', ' ')}</td>
                    <td className="py-2">
                      <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${
                        inv.status === 'accepted' ? 'bg-green-100 text-green-700' :
                        inv.status === 'expired' ? 'bg-red-100 text-red-700' :
                        'bg-yellow-100 text-yellow-700'
                      }`}>
                        {inv.status}
                      </span>
                    </td>
                    <td className="py-2 text-gray-500">{new Date(inv.created_at).toLocaleDateString('en-US')}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        {/* 全部员工 */}
        {allStaff.length > 0 && (
          <div className="bg-white rounded-xl border border-gray-200 p-6">
            <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-4">
              All Staff Across Stores ({allStaff.length})
            </h2>
            <table className="w-full text-sm">
              <thead className="border-b border-gray-200">
                <tr>
                  <th className="text-left pb-2 font-medium text-gray-500">User</th>
                  <th className="text-left pb-2 font-medium text-gray-500">Store</th>
                  <th className="text-left pb-2 font-medium text-gray-500">Role</th>
                  <th className="text-left pb-2 font-medium text-gray-500">Active</th>
                  <th className="text-left pb-2 font-medium text-gray-500">Since</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {allStaff.map((s: any) => {
                  const storeName = stores?.find(st => st.id === s.merchant_id)?.name ?? s.merchant_id?.slice(0, 8)
                  return (
                    <tr key={s.id}>
                      <td className="py-2 font-medium text-gray-900">
                        {s.users?.full_name || s.users?.email || s.user_id?.slice(0, 8)}
                      </td>
                      <td className="py-2">
                        <Link href={`/merchants/${s.merchant_id}`} className="text-blue-600 hover:underline text-xs">
                          {storeName}
                        </Link>
                      </td>
                      <td className="py-2">
                        <span className="px-2 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-600">
                          {s.role?.replace('_', ' ')}
                        </span>
                      </td>
                      <td className="py-2">
                        {s.is_active ? (
                          <span className="text-green-600 text-xs font-medium">Active</span>
                        ) : (
                          <span className="text-red-500 text-xs font-medium">Disabled</span>
                        )}
                      </td>
                      <td className="py-2 text-gray-500 text-xs">{new Date(s.created_at).toLocaleDateString('en-US')}</td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  )
}
