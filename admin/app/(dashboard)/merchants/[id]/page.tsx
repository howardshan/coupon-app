import { createClient } from '@/lib/supabase/server'
import { getServiceRoleClient } from '@/lib/supabase/service'
import { redirect } from 'next/navigation'
import Link from 'next/link'
import StaffToggleButton from '@/components/staff-toggle-button'
import MerchantCommissionForm from '@/components/merchant-commission-form'

const DOCUMENT_TYPE_LABELS: Record<string, string> = {
  business_license: 'Business License',
  health_permit: 'Health Permit',
  food_service_license: 'Food Service License',
  cosmetology_license: 'Cosmetology License',
  massage_therapy_license: 'Massage Therapy License',
  facility_license: 'Facility License',
  general_business_permit: 'General Business Permit',
  storefront_photo: 'Storefront Photo',
  owner_id: 'Owner ID',
}

export default async function MerchantReviewPage({
  params,
}: {
  params: Promise<{ id: string }>
}) {
  const { id } = await params
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  const { data: profile } = await supabase.from('users').select('role').eq('id', user!.id).single()

  if (profile?.role !== 'admin') redirect('/dashboard')

  const serviceClient = getServiceRoleClient()

  // 读取全局默认费率（用于占位提示）
  const { data: globalConfig } = await serviceClient
    .from('platform_commission_config')
    .select('commission_rate, stripe_processing_rate, stripe_flat_fee')
    .single()

  const { data: merchant } = await supabase
    .from('merchants')
    .select('id, user_id, name, company_name, description, contact_name, contact_email, phone, category, ein, address, status, rejection_reason, submitted_at, created_at, updated_at, brand_id, commission_free_until, commission_rate, commission_stripe_rate, commission_stripe_flat_fee, commission_effective_from, commission_effective_to, brands(id, name, logo_url)')
    .eq('id', id)
    .single()

  if (!merchant) {
    return (
      <div>
        <p className="text-gray-500">Merchant not found.</p>
        <Link href="/merchants" className="mt-3 inline-flex items-center gap-2 px-4 py-2 text-sm font-medium rounded-lg border border-gray-300 bg-white text-gray-700 shadow-sm hover:bg-gray-50 transition-colors">
          ← Back to Merchants
        </Link>
      </div>
    )
  }

  const { data: documents } = await supabase
    .from('merchant_documents')
    .select('id, document_type, file_url, file_name, uploaded_at')
    .eq('merchant_id', id)
    .order('uploaded_at', { ascending: true })

  const { data: staff } = await supabase
    .from('merchant_staff')
    .select('id, role, nickname, is_active, created_at, user_id, users(email, full_name)')
    .eq('merchant_id', id)
    .order('created_at', { ascending: true })

  // 获取商家本月收入数据
  const monthStart = new Date()
  monthStart.setDate(1)
  const monthStartStr = monthStart.toISOString().slice(0, 10)

  const { data: merchantEarnings } = await serviceClient.rpc('get_merchant_earnings_summary', {
    p_merchant_id: id,
    p_month_start: monthStartStr,
  })
  const mEarnings = merchantEarnings?.[0] ?? null

  // 最近交易记录 — 以券为最小单位
  const itemSelect = 'id, order_id, unit_price, customer_status, redeemed_at, redeemed_merchant_id, refunded_at, refund_amount, refund_method, created_at, orders(id, order_number, created_at, users(id, email)), deals!inner(id, title), coupons!order_items_coupon_id_fkey(coupon_code)'

  // V3: 该商家 deal 的 order_items
  const { data: dealItems } = await serviceClient
    .from('order_items')
    .select(itemSelect)
    .eq('deals.merchant_id', id)
    .order('created_at', { ascending: false })
    .limit(30)

  // V3: 在该门店核销的 order_items
  const { data: redeemedItems } = await serviceClient
    .from('order_items')
    .select('id, order_id, unit_price, customer_status, redeemed_at, redeemed_merchant_id, refunded_at, refund_amount, refund_method, created_at, orders(id, order_number, created_at, users(id, email)), deals(id, title), coupons!order_items_coupon_id_fkey(coupon_code)')
    .eq('redeemed_merchant_id', id)
    .order('created_at', { ascending: false })
    .limit(30)

  // V2: 该商家的 coupons（没有 order_item_id 的旧券）
  const { data: v2Coupons } = await serviceClient
    .from('coupons')
    .select('id, order_id, coupon_code, status, used_at, created_at, orders(id, order_number, unit_price, created_at, users(id, email)), deals!inner(id, title)')
    .is('order_item_id', null)
    .eq('deals.merchant_id', id)
    .order('created_at', { ascending: false })
    .limit(30)

  const { data: v2RedeemedCoupons } = await serviceClient
    .from('coupons')
    .select('id, order_id, coupon_code, status, used_at, created_at, redeemed_at_merchant_id, orders(id, order_number, unit_price, created_at, users(id, email)), deals(id, title)')
    .is('order_item_id', null)
    .eq('redeemed_at_merchant_id', id)
    .order('created_at', { ascending: false })
    .limit(30)

  // 统一格式：合并 V3 items + V2 coupons，去重后按时间排序
  type TxnRow = { id: string; orderId: string; orderNumber: string; customerEmail: string; dealTitle: string; amount: number; status: string; redeemedAt: string | null; refundedAt: string | null; refundAmount: number | null; refundMethod: string | null; date: string; isV3: boolean }
  const txnMap = new Map<string, TxnRow>()

  // V3 items
  for (const item of [...(dealItems ?? []), ...(redeemedItems ?? [])]) {
    if (txnMap.has(item.id)) continue
    const orderInfo = Array.isArray(item.orders) ? item.orders[0] : item.orders
    const dealInfo = Array.isArray(item.deals) ? item.deals[0] : item.deals
    const customerInfo = orderInfo?.users
    const customer = Array.isArray(customerInfo) ? customerInfo[0] : customerInfo
    txnMap.set(item.id, {
      id: item.id,
      orderId: orderInfo?.id ?? item.order_id,
      orderNumber: orderInfo?.order_number ?? item.order_id?.slice(0, 8) ?? '—',
      customerEmail: customer?.email ?? '—',
      dealTitle: dealInfo?.title ?? '—',
      amount: Number(item.unit_price),
      status: item.customer_status,
      redeemedAt: item.redeemed_at,
      refundedAt: item.refunded_at,
      refundAmount: item.refund_amount ? Number(item.refund_amount) : null,
      refundMethod: item.refund_method,
      date: item.created_at,
      isV3: true,
    })
  }

  // V2 coupons
  for (const c of [...(v2Coupons ?? []), ...(v2RedeemedCoupons ?? [])]) {
    const key = `v2_${c.id}`
    if (txnMap.has(key)) continue
    const orderInfo = Array.isArray(c.orders) ? c.orders[0] : c.orders
    const dealInfo = Array.isArray(c.deals) ? c.deals[0] : c.deals
    const customer = orderInfo?.users
    const cust = Array.isArray(customer) ? customer[0] : customer
    txnMap.set(key, {
      id: c.id,
      orderId: orderInfo?.id ?? c.order_id,
      orderNumber: orderInfo?.order_number ?? c.order_id?.slice(0, 8) ?? '—',
      customerEmail: cust?.email ?? '—',
      dealTitle: dealInfo?.title ?? '—',
      amount: Number(orderInfo?.unit_price ?? 0),
      status: c.status,
      redeemedAt: c.used_at,
      refundedAt: null,
      refundAmount: null,
      refundMethod: null,
      date: c.created_at,
      isV3: false,
    })
  }

  const recentTxns = Array.from(txnMap.values())
    .sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime())
    .slice(0, 20)

  // brands join 可能返回数组或单对象，统一处理
  const brandsRaw = merchant.brands as any
  const brandInfo = Array.isArray(brandsRaw) ? brandsRaw[0] ?? null : brandsRaw ?? null

  return (
    <div>
      <div className="mb-6">
        <div className="flex items-center justify-between">
          <div>
            <Link href="/merchants" className="mb-3 inline-flex items-center gap-2 px-3 py-2 text-sm font-medium rounded-lg border border-gray-300 bg-white text-gray-700 shadow-sm hover:bg-gray-50 transition-colors">
              ← Back to Merchants
            </Link>
            <h1 className="text-2xl font-bold text-gray-900">Merchant Profile</h1>
          </div>
        </div>
        {/* 审批操作已移至统一审批中心 */}
        {merchant.status === 'pending' && (
          <div className="mt-3 flex items-center gap-3 rounded-lg border border-yellow-200 bg-yellow-50 px-4 py-3">
            <span className="text-sm text-yellow-800">
              This merchant is pending review.
            </span>
            <Link
              href={`/approvals?tab=merchants`}
              className="text-sm font-semibold text-yellow-700 underline hover:text-yellow-900"
            >
              Review in Approvals Center →
            </Link>
          </div>
        )}
      </div>

      <div className="space-y-6">
        <div className="bg-white rounded-xl border border-gray-200 p-6">
          <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-3">Status</h2>
          <span className={`inline-block px-3 py-1 rounded-full text-sm font-medium ${merchant.status === 'approved' ? 'bg-green-100 text-green-700' : merchant.status === 'rejected' ? 'bg-red-100 text-red-700' : 'bg-yellow-100 text-yellow-700'}`}>
            {merchant.status}
          </span>
          {merchant.rejection_reason && (
            <p className="mt-2 text-sm text-red-600 bg-red-50 p-3 rounded-lg">Rejection reason: {merchant.rejection_reason}</p>
          )}
        </div>

        {brandInfo && (
          <div className="bg-white rounded-xl border border-gray-200 p-6">
            <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-3">Brand</h2>
            <div className="flex items-center gap-3">
              {brandInfo.logo_url ? (
                <img src={brandInfo.logo_url} alt="" className="w-8 h-8 rounded-full object-cover border border-gray-200" />
              ) : (
                <div className="w-8 h-8 rounded-full bg-gray-100 flex items-center justify-center text-gray-400 text-xs font-bold">
                  {brandInfo.name?.charAt(0)?.toUpperCase()}
                </div>
              )}
              <Link href={`/brands/${brandInfo.id}`} className="text-blue-600 hover:underline font-medium">
                {brandInfo.name}
              </Link>
            </div>
          </div>
        )}

        <div className="bg-white rounded-xl border border-gray-200 p-6">
          <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-4">Application Information</h2>
          <dl className="grid grid-cols-1 sm:grid-cols-2 gap-x-4 gap-y-3 text-sm">
            <div><dt className="text-gray-500">Company / Display name</dt><dd className="font-medium text-gray-900">{merchant.company_name || merchant.name || '—'}</dd></div>
            <div><dt className="text-gray-500">Contact name</dt><dd className="font-medium text-gray-900">{merchant.contact_name || '—'}</dd></div>
            <div><dt className="text-gray-500">Contact email</dt><dd className="font-medium text-gray-900">{merchant.contact_email || '—'}</dd></div>
            <div><dt className="text-gray-500">Phone</dt><dd className="font-medium text-gray-900">{merchant.phone || '—'}</dd></div>
            <div><dt className="text-gray-500">Category</dt><dd className="font-medium text-gray-900">{merchant.category || '—'}</dd></div>
            <div><dt className="text-gray-500">EIN / Tax ID</dt><dd className="font-medium text-gray-900">{merchant.ein || '—'}</dd></div>
            <div className="sm:col-span-2"><dt className="text-gray-500">Address</dt><dd className="font-medium text-gray-900">{merchant.address || '—'}</dd></div>
            {merchant.description && <div className="sm:col-span-2"><dt className="text-gray-500">Description</dt><dd className="font-medium text-gray-900">{merchant.description}</dd></div>}
            <div><dt className="text-gray-500">Registration type</dt><dd className="font-medium text-gray-900">{brandInfo ? 'Brand / Chain Store' : 'Single Location'}</dd></div>
            <div><dt className="text-gray-500">Submitted at</dt><dd className="font-medium text-gray-900">{merchant.submitted_at ? new Date(merchant.submitted_at).toLocaleString() : (merchant.created_at ? new Date(merchant.created_at).toLocaleString() : '—')}</dd></div>
          </dl>
        </div>

        <div className="bg-white rounded-xl border border-gray-200 p-6">
          <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-4">Submitted Documents</h2>
          {documents && documents.length > 0 ? (
            <ul className="space-y-2">
              {documents.map((doc) => (
                <li key={doc.id} className="flex items-center justify-between py-2 border-b border-gray-100 last:border-0">
                  <span className="text-sm font-medium text-gray-700">
                    {DOCUMENT_TYPE_LABELS[doc.document_type] || doc.document_type}
                    {doc.file_name && <span className="text-gray-500 font-normal ml-2">({doc.file_name})</span>}
                  </span>
                  <a href={doc.file_url} target="_blank" rel="noopener noreferrer" className="inline-flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium rounded-lg border border-blue-200 bg-blue-50 text-blue-700 hover:bg-blue-100 transition-colors">
                    View / Download ↗
                  </a>
                </li>
              ))}
            </ul>
          ) : (
            <p className="text-sm text-gray-500">No documents submitted.</p>
          )}
        </div>

        <MerchantCommissionForm
          merchantId={merchant.id}
          commissionFreeUntil={(merchant as any).commission_free_until ?? null}
          commissionRate={(merchant as any).commission_rate ?? null}
          commissionStripeRate={(merchant as any).commission_stripe_rate ?? null}
          commissionStripeFlatFee={(merchant as any).commission_stripe_flat_fee ?? null}
          commissionEffectiveFrom={(merchant as any).commission_effective_from ?? null}
          commissionEffectiveTo={(merchant as any).commission_effective_to ?? null}
          defaultCommissionRate={Number(globalConfig?.commission_rate ?? 0.15)}
          defaultStripeRate={Number(globalConfig?.stripe_processing_rate ?? 0.03)}
          defaultStripeFlatFee={Number(globalConfig?.stripe_flat_fee ?? 0.30)}
        />

        {/* 商家本月收入 */}
        <div className="bg-white rounded-xl border border-gray-200 p-6">
          <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-4">Merchant Earnings (This Month)</h2>
          {brandInfo && (
            <div className="mb-4 p-3 bg-blue-50 rounded-lg text-sm">
              <span className="text-gray-500">Brand Fee:</span>{' '}
              <Link href={`/brands/${brandInfo.id}`} className="text-blue-600 hover:underline font-medium">{brandInfo.name}</Link>
              {merchant.commission_rate != null && (
                <span className="ml-2 text-gray-600">
                  (Brand Commission: {((merchant as any).commission_rate * 100).toFixed(0)}%)
                </span>
              )}
            </div>
          )}
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
            <div className="bg-gray-50 rounded-lg p-4">
              <p className="text-xs text-gray-500 mb-1">This Month</p>
              <p className="text-xl font-bold text-orange-600">${(mEarnings?.total_revenue ?? 0).toFixed(2)}</p>
            </div>
            <div className="bg-gray-50 rounded-lg p-4">
              <p className="text-xs text-gray-500 mb-1">Awaiting Settlement</p>
              <p className="text-xl font-bold text-yellow-600">${(mEarnings?.pending_settlement ?? 0).toFixed(2)}</p>
            </div>
            <div className="bg-gray-50 rounded-lg p-4">
              <p className="text-xs text-gray-500 mb-1">Settled</p>
              <p className="text-xl font-bold text-green-600">${(mEarnings?.settled_amount ?? 0).toFixed(2)}</p>
            </div>
            <div className="bg-gray-50 rounded-lg p-4">
              <p className="text-xs text-gray-500 mb-1">Refunded</p>
              <p className="text-xl font-bold text-red-500">${(mEarnings?.refunded_amount ?? 0).toFixed(2)}</p>
            </div>
          </div>
        </div>

        {/* 最近交易（以券为最小单位） */}
        <div className="bg-white rounded-xl border border-gray-200 p-6">
          <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-4">
            Recent Transactions ({recentTxns.length})
          </h2>
          {recentTxns.length > 0 ? (
            <table className="w-full text-sm">
              <thead className="border-b border-gray-200">
                <tr>
                  <th className="text-left pb-2 font-medium text-gray-500">Order #</th>
                  <th className="text-left pb-2 font-medium text-gray-500">Customer</th>
                  <th className="text-left pb-2 font-medium text-gray-500">Deal</th>
                  <th className="text-right pb-2 font-medium text-gray-500">Amount</th>
                  <th className="text-left pb-2 font-medium text-gray-500">Status</th>
                  <th className="text-left pb-2 font-medium text-gray-500">Action Time</th>
                  <th className="text-left pb-2 font-medium text-gray-500">Date</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {recentTxns.map((t) => {
                  const actionTime = t.redeemedAt ?? t.refundedAt
                  return (
                  <tr key={t.id} className="hover:bg-gray-50">
                    <td className="py-2">
                      <Link href={`/orders/${t.orderId}`} className="text-blue-600 hover:underline font-medium font-mono text-xs">
                        {t.orderNumber}
                      </Link>
                    </td>
                    <td className="py-2 text-gray-600 text-xs">{t.customerEmail}</td>
                    <td className="py-2 text-gray-700 text-xs max-w-[200px] truncate">{t.dealTitle}</td>
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
                  )
                })}
              </tbody>
            </table>
          ) : (
            <p className="text-sm text-gray-500">No transactions yet.</p>
          )}
        </div>

        <div className="bg-white rounded-xl border border-gray-200 p-6">
          <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-4">Staff ({staff?.length ?? 0})</h2>
          {staff && staff.length > 0 ? (
            <table className="w-full text-sm">
              <thead className="border-b border-gray-100">
                <tr>
                  <th className="text-left py-2 font-medium text-gray-500">Name</th>
                  <th className="text-left py-2 font-medium text-gray-500">Email</th>
                  <th className="text-left py-2 font-medium text-gray-500">Role</th>
                  <th className="text-left py-2 font-medium text-gray-500">Status</th>
                  <th className="text-left py-2 font-medium text-gray-500">Joined</th>
                  <th className="text-left py-2 font-medium text-gray-500">Action</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-50">
                {staff.map((s: any) => (
                  <tr key={s.id}>
                    <td className="py-2 text-gray-900">{s.nickname || s.users?.full_name || '—'}</td>
                    <td className="py-2 text-gray-600 text-xs">{s.users?.email || '—'}</td>
                    <td className="py-2">
                      <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${s.role === 'manager' ? 'bg-purple-100 text-purple-700' : s.role === 'cashier' ? 'bg-blue-100 text-blue-700' : 'bg-green-100 text-green-700'}`}>
                        {s.role}
                      </span>
                    </td>
                    <td className="py-2">
                      <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${s.is_active ? 'bg-green-100 text-green-700' : 'bg-red-100 text-red-700'}`}>
                        {s.is_active ? 'Active' : 'Disabled'}
                      </span>
                    </td>
                    <td className="py-2 text-gray-500 text-xs">{new Date(s.created_at).toLocaleDateString('en-US')}</td>
                    <td className="py-2">
                      <StaffToggleButton staffId={s.id} isActive={s.is_active} />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          ) : (
            <p className="text-sm text-gray-500">No staff members.</p>
          )}
        </div>
      </div>
    </div>
  )
}
