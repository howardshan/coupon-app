import { createClient } from '@/lib/supabase/server'
import { redirect, notFound } from 'next/navigation'
import Link from 'next/link'
import OrderRefundButtons from '@/components/order-refund-buttons'
import { getOrderDetailStatusTags, STATUS_STYLES, STATUS_LABELS } from '@/lib/order-display-status'

// V3 order_item 的 customer_status 状态样式
const ITEM_STATUS_STYLES: Record<string, string> = {
  unused: 'bg-blue-100 text-blue-700',
  used: 'bg-gray-100 text-gray-600',
  expired: 'bg-red-100 text-red-700',
  refund_pending: 'bg-amber-100 text-amber-700',
  refund_review: 'bg-orange-100 text-orange-700',
  refund_reject: 'bg-amber-100 text-amber-700',
  refund_success: 'bg-purple-100 text-purple-700',
}

const ITEM_STATUS_LABELS: Record<string, string> = {
  unused: 'Unused',
  used: 'Used',
  expired: 'Expired',
  refund_pending: 'Refund Pending',
  refund_review: 'Refund Review',
  refund_reject: 'Refund Rejected',
  refund_success: 'Refunded',
}

export default async function OrderDetailPage({
  params,
}: {
  params: Promise<{ id: string }>
}) {
  const { id } = await params
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  const { data: profile } = await supabase.from('users').select('role').eq('id', user!.id).single()

  if (profile?.role !== 'admin') redirect('/dashboard')

  const { data: order } = await supabase
    .from('orders')
    .select(`
      id,
      order_number,
      quantity,
      unit_price,
      total_amount,
      items_amount,
      service_fee_total,
      status,
      payment_intent_id,
      refund_reason,
      created_at,
      updated_at,
      refund_requested_at,
      refunded_at,
      refund_rejected_at,
      users ( id, email ),
      deals ( id, title, discount_price, applicable_merchant_ids, merchants ( id, name ) ),
      coupons!fk_orders_coupon_id ( redeemed_at_merchant_id, expires_at ),
      order_items (
        id, deal_id, unit_price, service_fee,
        customer_status, merchant_status,
        redeemed_merchant_id, redeemed_at,
        refunded_at, refund_reason, refund_amount, refund_method,
        deals ( id, title, discount_price, merchants ( id, name ) ),
        coupons!order_items_coupon_id_fkey ( id, qr_code, coupon_code, status, expires_at )
      )
    `)
    .eq('id', id)
    .single()

  if (!order) notFound()

  const customer = order.users as any
  const orderItems = (order as any).order_items as any[] | null
  const hasV3Items = orderItems && orderItems.length > 0

  // V3：按 deal 分组
  type DealGroup = {
    dealId: string
    dealTitle: string
    merchantId: string | null
    merchantName: string | null
    unitPrice: number
    items: any[]
  }
  let dealGroups: DealGroup[] = []
  if (hasV3Items) {
    const groupMap = new Map<string, DealGroup>()
    for (const item of orderItems) {
      const d = item.deals as any
      const m = Array.isArray(d?.merchants) ? d.merchants[0] : d?.merchants
      const key = item.deal_id
      if (!groupMap.has(key)) {
        groupMap.set(key, {
          dealId: d?.id ?? item.deal_id,
          dealTitle: d?.title ?? '—',
          merchantId: m?.id ?? null,
          merchantName: m?.name ?? null,
          unitPrice: Number(item.unit_price),
          items: [],
        })
      }
      groupMap.get(key)!.items.push(item)
    }
    dealGroups = Array.from(groupMap.values())
  }

  // V2 兼容：旧订单
  const deal = order.deals as any
  const merchant = Array.isArray(deal?.merchants) ? deal.merchants[0] : deal?.merchants

  // 核销门店信息 + 券过期时间（用于多维度状态）—— 仅 V2
  const raw = order.coupons
  const first = Array.isArray(raw) ? raw[0] : raw
  const redeemedMerchantId = first?.redeemed_at_merchant_id
  const orderForDisplay = {
    status: order.status as string,
    refund_rejected_at: (order as { refund_rejected_at?: string | null }).refund_rejected_at,
    coupon_expires_at: first?.expires_at ?? null,
    deals: order.deals as { expires_at?: string | null } | null,
  }
  const detailStatusTags = hasV3Items ? [] : getOrderDetailStatusTags(orderForDisplay)

  let redeemedMerchantName: string | null = null
  if (!hasV3Items && redeemedMerchantId) {
    const { data: rm } = await supabase.from('merchants').select('name').eq('id', redeemedMerchantId).single()
    redeemedMerchantName = rm?.name ?? null
  }

  // V3：批量查询核销门店名称
  const redeemedMerchantNames: Record<string, string> = {}
  if (hasV3Items) {
    const ids = new Set<string>()
    for (const item of orderItems) {
      if (item.redeemed_merchant_id) ids.add(item.redeemed_merchant_id)
    }
    if (ids.size > 0) {
      const { data: merchants } = await supabase.from('merchants').select('id, name').in('id', Array.from(ids))
      for (const m of merchants ?? []) {
        redeemedMerchantNames[m.id] = m.name
      }
    }
  }

  // 适用门店（仅 V2）
  const applicableIds = deal?.applicable_merchant_ids as string[] | null
  let applicableStores: { id: string; name: string }[] = []
  if (!hasV3Items && applicableIds && applicableIds.length > 0) {
    const { data } = await supabase.from('merchants').select('id, name').in('id', applicableIds)
    applicableStores = data ?? []
  }

  // V3 汇总状态
  const v3StatusSummary = hasV3Items
    ? (() => {
        const counts: Record<string, number> = {}
        for (const item of orderItems) {
          const s = item.customer_status as string
          counts[s] = (counts[s] ?? 0) + 1
        }
        return counts
      })()
    : null

  return (
    <div>
      <div className="mb-6">
        <Link href="/orders" className="mb-3 inline-flex items-center gap-2 px-3 py-2 text-sm font-medium rounded-lg border border-gray-300 bg-white text-gray-700 shadow-sm hover:bg-gray-50 transition-colors">
          ← Back to Orders
        </Link>
        <h1 className="text-2xl font-bold text-gray-900 mt-2">
          Order {order.order_number ?? id.slice(0, 8)}
        </h1>
      </div>

      <div className="space-y-6">
        {/* 状态区块 */}
        <div className="bg-white rounded-xl border border-gray-200 p-6">
          <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-3">Status</h2>
          {hasV3Items ? (
            <div className="flex items-center gap-3 flex-wrap">
              {Object.entries(v3StatusSummary!).map(([status, count]) => (
                <span
                  key={status}
                  className={`px-3 py-1 rounded-full text-sm font-medium ${ITEM_STATUS_STYLES[status] ?? 'bg-gray-100 text-gray-600'}`}
                >
                  {ITEM_STATUS_LABELS[status] ?? status} ×{count}
                </span>
              ))}
            </div>
          ) : (
            <>
              <div className="flex items-center gap-3 flex-wrap">
                {detailStatusTags.map((tag) => (
                  <span
                    key={tag}
                    className={`px-3 py-1 rounded-full text-sm font-medium ${STATUS_STYLES[tag] ?? STATUS_STYLES.used}`}
                  >
                    {STATUS_LABELS[tag] ?? tag}
                  </span>
                ))}
                {order.status === 'refund_requested' && (
                  <OrderRefundButtons orderId={order.id} initialStatus={order.status} />
                )}
              </div>
              {(detailStatusTags.includes('pending_refund') || detailStatusTags.includes('expired')) && (
                <p className="text-sm text-gray-500 mt-3">
                  {detailStatusTags.includes('pending_refund')
                    ? 'Auto-refund in progress (runs hourly).'
                    : 'Coupon expired; will be auto-refunded 24h after expiry.'}
                </p>
              )}
            </>
          )}
        </div>

        {/* V3: Order Items 按 deal 分组 */}
        {hasV3Items ? (
          <div className="bg-white rounded-xl border border-gray-200 p-6">
            <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-4">
              Order Items ({orderItems.length} coupon{orderItems.length > 1 ? 's' : ''})
            </h2>

            {/* 汇总 */}
            <dl className="grid grid-cols-2 sm:grid-cols-4 gap-3 text-sm mb-6 pb-4 border-b border-gray-100">
              <div>
                <dt className="text-gray-500">Items Amount</dt>
                <dd className="font-medium text-gray-900 mt-0.5">${Number((order as any).items_amount ?? 0).toFixed(2)}</dd>
              </div>
              <div>
                <dt className="text-gray-500">Service Fee</dt>
                <dd className="font-medium text-gray-900 mt-0.5">${Number((order as any).service_fee_total ?? 0).toFixed(2)}</dd>
              </div>
              <div>
                <dt className="text-gray-500">Total Amount</dt>
                <dd className="font-semibold text-gray-900 mt-0.5">${Number(order.total_amount).toFixed(2)}</dd>
              </div>
              <div>
                <dt className="text-gray-500">Created</dt>
                <dd className="font-medium text-gray-900 mt-0.5">{new Date(order.created_at).toLocaleString()}</dd>
              </div>
            </dl>

            {/* 按 deal 分组展示 */}
            <div className="space-y-5">
              {dealGroups.map((group) => (
                <div key={group.dealId} className="border border-gray-100 rounded-lg p-4">
                  <div className="flex items-center justify-between mb-3">
                    <div>
                      <Link
                        href={`/deals/${group.dealId}?returnTo=${encodeURIComponent(`/orders/${order.id}`)}`}
                        className="text-blue-600 hover:underline font-medium"
                      >
                        {group.dealTitle}
                      </Link>
                      {group.merchantName && (
                        <span className="text-gray-500 text-sm ml-2">
                          by{' '}
                          <Link href={`/merchants/${group.merchantId}`} className="text-blue-600 hover:underline">
                            {group.merchantName}
                          </Link>
                        </span>
                      )}
                    </div>
                    <span className="text-sm text-gray-500">
                      ${group.unitPrice.toFixed(2)} × {group.items.length}
                    </span>
                  </div>

                  {/* 每张券 */}
                  <table className="w-full text-xs">
                    <thead className="bg-gray-50">
                      <tr>
                        <th className="text-left px-3 py-2 font-medium text-gray-500">Coupon</th>
                        <th className="text-left px-3 py-2 font-medium text-gray-500">Status</th>
                        <th className="text-left px-3 py-2 font-medium text-gray-500">Expires</th>
                        <th className="text-left px-3 py-2 font-medium text-gray-500">Redeemed At</th>
                        <th className="text-left px-3 py-2 font-medium text-gray-500">Refund</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-gray-50">
                      {group.items.map((item: any) => {
                        const coupon = Array.isArray(item.coupons) ? item.coupons[0] : item.coupons
                        const couponCode = coupon?.coupon_code
                        const formattedCode = couponCode && couponCode.length === 16
                          ? `${couponCode.slice(0, 4)}-${couponCode.slice(4, 8)}-${couponCode.slice(8, 12)}-${couponCode.slice(12)}`
                          : couponCode ?? '—'
                        const redeemedName = item.redeemed_merchant_id
                          ? redeemedMerchantNames[item.redeemed_merchant_id] ?? item.redeemed_merchant_id.slice(0, 8)
                          : null

                        return (
                          <tr key={item.id}>
                            <td className="px-3 py-2 font-mono text-gray-700">{formattedCode}</td>
                            <td className="px-3 py-2">
                              <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${ITEM_STATUS_STYLES[item.customer_status] ?? 'bg-gray-100 text-gray-600'}`}>
                                {ITEM_STATUS_LABELS[item.customer_status] ?? item.customer_status}
                              </span>
                            </td>
                            <td className="px-3 py-2 text-gray-500">
                              {coupon?.expires_at ? new Date(coupon.expires_at).toLocaleDateString('en-US') : '—'}
                            </td>
                            <td className="px-3 py-2 text-gray-600">
                              {redeemedName ? (
                                <Link href={`/merchants/${item.redeemed_merchant_id}`} className="text-blue-600 hover:underline">
                                  {redeemedName}
                                </Link>
                              ) : (
                                <span className="text-gray-400">—</span>
                              )}
                            </td>
                            <td className="px-3 py-2 text-gray-500">
                              {item.refunded_at ? (
                                <span>
                                  ${Number(item.refund_amount ?? item.unit_price).toFixed(2)}
                                  {item.refund_method === 'store_credit' && (
                                    <span className="ml-1 text-xs text-purple-600">(credit)</span>
                                  )}
                                </span>
                              ) : '—'}
                            </td>
                          </tr>
                        )
                      })}
                    </tbody>
                  </table>
                </div>
              ))}
            </div>
          </div>
        ) : (
          /* V2 兼容：旧的 Order & Deal 区块 */
          <>
            <div className="bg-white rounded-xl border border-gray-200 p-6">
              <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-4">Order & Deal</h2>
              <dl className="grid grid-cols-1 sm:grid-cols-2 gap-3 text-sm">
                <div>
                  <dt className="text-gray-500">Deal</dt>
                  <dd className="font-medium text-gray-900 mt-0.5">
                    {deal ? (<Link href={`/deals/${deal.id}?returnTo=${encodeURIComponent(`/orders/${order.id}`)}`} className="text-blue-600 hover:underline">{deal.title}</Link>) : '—'}
                  </dd>
                </div>
                <div>
                  <dt className="text-gray-500">Purchase Merchant</dt>
                  <dd className="font-medium text-gray-900 mt-0.5">
                    {merchant ? (<Link href={`/merchants/${merchant.id}`} className="text-blue-600 hover:underline">{merchant.name}</Link>) : '—'}
                  </dd>
                </div>
                <div>
                  <dt className="text-gray-500">Redeemed At</dt>
                  <dd className="font-medium text-gray-900 mt-0.5">
                    {redeemedMerchantName ? (
                      <Link href={`/merchants/${redeemedMerchantId}`} className="text-blue-600 hover:underline">{redeemedMerchantName}</Link>
                    ) : (
                      <span className="text-gray-400">—</span>
                    )}
                    {redeemedMerchantId && merchant && redeemedMerchantId !== merchant.id && (
                      <span className="ml-1 text-xs text-orange-600">(different store)</span>
                    )}
                  </dd>
                </div>
                <div>
                  <dt className="text-gray-500">Quantity</dt>
                  <dd className="font-medium text-gray-900 mt-0.5">{order.quantity}</dd>
                </div>
                <div>
                  <dt className="text-gray-500">Unit price</dt>
                  <dd className="font-medium text-gray-900 mt-0.5">${Number(order.unit_price).toFixed(2)}</dd>
                </div>
                <div>
                  <dt className="text-gray-500">Total amount</dt>
                  <dd className="font-medium text-gray-900 mt-0.5">${Number(order.total_amount).toFixed(2)}</dd>
                </div>
                <div>
                  <dt className="text-gray-500">Created</dt>
                  <dd className="font-medium text-gray-900 mt-0.5">{new Date(order.created_at).toLocaleString()}</dd>
                </div>
              </dl>
            </div>

            {/* 适用门店（多店 Deal） */}
            {applicableStores.length > 0 && (
              <div className="bg-white rounded-xl border border-gray-200 p-6">
                <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-3">Applicable Stores</h2>
                <div className="flex flex-wrap gap-2">
                  {applicableStores.map(s => (
                    <Link key={s.id} href={`/merchants/${s.id}`} className="px-2 py-1 rounded bg-gray-100 text-xs text-blue-600 hover:underline">
                      {s.name}
                    </Link>
                  ))}
                </div>
              </div>
            )}
          </>
        )}

        <div className="bg-white rounded-xl border border-gray-200 p-6">
          <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-3">Customer</h2>
          <p className="text-sm text-gray-900">{customer?.email ?? '—'}</p>
        </div>

        {/* Refund info (if any) — 仅 V2 */}
        {!hasV3Items && (order.refund_reason != null || order.refund_requested_at != null || order.refunded_at != null || (order as { refund_rejected_at?: string | null }).refund_rejected_at != null) && (
          <div className="bg-white rounded-xl border border-gray-200 p-6">
            <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-3">Refund</h2>
            <dl className="space-y-2 text-sm">
              {order.refund_reason != null && (
                <div><dt className="text-gray-500">Reason</dt><dd className="text-gray-900 mt-0.5">{order.refund_reason}</dd></div>
              )}
              {order.refund_requested_at != null && (
                <div><dt className="text-gray-500">Requested at</dt><dd className="text-gray-900 mt-0.5">{new Date(order.refund_requested_at).toLocaleString()}</dd></div>
              )}
              {order.refunded_at != null && (
                <div><dt className="text-gray-500">Refunded at</dt><dd className="text-gray-900 mt-0.5">{new Date(order.refunded_at).toLocaleString()}</dd></div>
              )}
              {(order as { refund_rejected_at?: string | null }).refund_rejected_at != null && (
                <div>
                  <dt className="text-gray-500">Rejected at</dt>
                  <dd className="text-gray-900 mt-0.5">{new Date((order as { refund_rejected_at: string }).refund_rejected_at).toLocaleString()}</dd>
                </div>
              )}
            </dl>
          </div>
        )}

        <div className="bg-white rounded-xl border border-gray-200 p-6">
          <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-3">Payment</h2>
          <p className="text-xs text-gray-500 font-mono break-all">{order.payment_intent_id ?? '—'}</p>
          <p className="text-xs text-gray-400 mt-1">Use this ID to look up the charge in Stripe Dashboard.</p>
        </div>
      </div>
    </div>
  )
}
