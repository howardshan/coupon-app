import { createClient } from '@/lib/supabase/server'
import { redirect, notFound } from 'next/navigation'
import Link from 'next/link'
import OrderRefundButtons from '@/components/order-refund-buttons'
import { getOrderDetailStatusTags, STATUS_STYLES, STATUS_LABELS } from '@/lib/order-display-status'

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
      coupons!fk_orders_coupon_id ( redeemed_at_merchant_id, expires_at )
    `)
    .eq('id', id)
    .single()

  if (!order) notFound()

  const deal = order.deals as any
  const merchant = Array.isArray(deal?.merchants) ? deal.merchants[0] : deal?.merchants
  const customer = order.users as any

  // 核销门店信息 + 券过期时间（用于多维度状态）
  const raw = order.coupons
  const first = Array.isArray(raw) ? raw[0] : raw
  const redeemedMerchantId = first?.redeemed_at_merchant_id
  const orderForDisplay = {
    status: order.status as string,
    refund_rejected_at: (order as { refund_rejected_at?: string | null }).refund_rejected_at,
    coupon_expires_at: first?.expires_at ?? null,
    deals: order.deals as { expires_at?: string | null } | null,
  }
  const detailStatusTags = getOrderDetailStatusTags(orderForDisplay)
  let redeemedMerchantName: string | null = null
  if (redeemedMerchantId) {
    const { data: rm } = await supabase.from('merchants').select('name').eq('id', redeemedMerchantId).single()
    redeemedMerchantName = rm?.name ?? null
  }

  // 适用门店
  const applicableIds = deal?.applicable_merchant_ids as string[] | null
  let applicableStores: { id: string; name: string }[] = []
  if (applicableIds && applicableIds.length > 0) {
    const { data } = await supabase.from('merchants').select('id, name').in('id', applicableIds)
    applicableStores = data ?? []
  }

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
        <div className="bg-white rounded-xl border border-gray-200 p-6">
          <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-3">Status</h2>
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
        </div>

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

        <div className="bg-white rounded-xl border border-gray-200 p-6">
          <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-3">Customer</h2>
          <p className="text-sm text-gray-900">{customer?.email ?? '—'}</p>
        </div>

        {/* Refund info (if any) */}
        {(order.refund_reason != null || order.refund_requested_at != null || order.refunded_at != null || (order as { refund_rejected_at?: string | null }).refund_rejected_at != null) && (
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
