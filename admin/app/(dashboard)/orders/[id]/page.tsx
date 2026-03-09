import { createClient } from '@/lib/supabase/server'
import { redirect, notFound } from 'next/navigation'
import Link from 'next/link'
import OrderRefundButtons from '@/components/order-refund-buttons'
import { getOrderDetailStatusTags } from '@/lib/order-display-status'

const STATUS_STYLES: Record<string, string> = {
  unused: 'bg-blue-100 text-blue-700',
  used: 'bg-gray-100 text-gray-600',
  refunded: 'bg-purple-100 text-purple-700',
  refund_requested: 'bg-orange-100 text-orange-700',
  refund_failed: 'bg-red-100 text-red-700',
  refund_rejected: 'bg-amber-100 text-amber-700',
  expired: 'bg-red-100 text-red-700',
  pending_refund: 'bg-amber-100 text-amber-700',
}

const STATUS_LABELS: Record<string, string> = {
  unused: 'Unused',
  used: 'Used',
  refunded: 'Refunded',
  refund_requested: 'Refund Requested',
  refund_failed: 'Refund Failed',
  refund_rejected: 'Refund Rejected',
  expired: 'Expired',
  pending_refund: 'Pending Refund',
}

export default async function OrderDetailPage({
  params,
}: {
  params: Promise<{ id: string }>
}) {
  const { id } = await params
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  const { data: profile } = await supabase
    .from('users')
    .select('role')
    .eq('id', user!.id)
    .single()

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
      deals ( id, title, discount_price, expires_at, merchants ( id, name ) )
    `)
    .eq('id', id)
    .single()

  if (!order) notFound()

  const deal = order.deals as { id: string; title: string; discount_price?: number; expires_at?: string | null; merchants?: { id: string; name: string } | null } | null
  const merchant = deal?.merchants
  const customer = order.users as { id: string; email: string } | null
  const statusTags = getOrderDetailStatusTags(order)

  return (
    <div>
      <div className="mb-6">
        <Link
          href="/orders"
          className="mb-3 inline-flex items-center gap-2 px-3 py-2 text-sm font-medium rounded-lg border border-gray-300 bg-white text-gray-700 shadow-sm hover:bg-gray-50 transition-colors"
        >
          ← Back to Orders
        </Link>
        <h1 className="text-2xl font-bold text-gray-900 mt-2">
          Order {order.order_number ?? id.slice(0, 8)}
        </h1>
      </div>

      <div className="space-y-6">
        {/* Status */}
        <div className="bg-white rounded-xl border border-gray-200 p-6">
          <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-3">Status</h2>
          <div className="flex items-center gap-3 flex-wrap">
            {statusTags.map((tag) => (
              <span
                key={tag}
                className={`px-3 py-1 rounded-full text-sm font-medium ${STATUS_STYLES[tag] ?? STATUS_STYLES.used}`}
              >
                {STATUS_LABELS[tag] ?? tag}
              </span>
            ))}
            {(order.status === 'refund_requested') && (
              <OrderRefundButtons orderId={order.id} initialStatus={order.status} />
            )}
          </div>
          {(statusTags.includes('expired') || statusTags.includes('pending_refund')) && order.status === 'unused' && (
            <p className="text-sm text-gray-500 mt-2">
              {statusTags.includes('expired') ? 'Coupon expired; will be auto-refunded 24h after expiry.' : 'Auto-refund in progress (runs hourly).'}
            </p>
          )}
        </div>

        {/* Order & deal info */}
        <div className="bg-white rounded-xl border border-gray-200 p-6">
          <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-4">Order & Deal</h2>
          <dl className="grid grid-cols-1 sm:grid-cols-2 gap-3 text-sm">
            <div>
              <dt className="text-gray-500">Deal</dt>
              <dd className="font-medium text-gray-900 mt-0.5">
                {deal ? (
                  <Link href={`/deals/${deal.id}`} className="text-blue-600 hover:underline">
                    {deal.title}
                  </Link>
                ) : '—'}
              </dd>
            </div>
            <div>
              <dt className="text-gray-500">Merchant</dt>
              <dd className="font-medium text-gray-900 mt-0.5">
                {merchant ? (
                  <Link href={`/merchants/${merchant.id}`} className="text-blue-600 hover:underline">
                    {merchant.name}
                  </Link>
                ) : '—'}
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
              <dd className="font-medium text-gray-900 mt-0.5">
                {new Date(order.created_at).toLocaleString()}
              </dd>
            </div>
          </dl>
        </div>

        {/* Customer */}
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
                <div>
                  <dt className="text-gray-500">Reason</dt>
                  <dd className="text-gray-900 mt-0.5">{order.refund_reason}</dd>
                </div>
              )}
              {order.refund_requested_at != null && (
                <div>
                  <dt className="text-gray-500">Requested at</dt>
                  <dd className="text-gray-900 mt-0.5">{new Date(order.refund_requested_at).toLocaleString()}</dd>
                </div>
              )}
              {order.refunded_at != null && (
                <div>
                  <dt className="text-gray-500">Refunded at</dt>
                  <dd className="text-gray-900 mt-0.5">{new Date(order.refunded_at).toLocaleString()}</dd>
                </div>
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

        {/* Payment reference */}
        <div className="bg-white rounded-xl border border-gray-200 p-6">
          <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-3">Payment</h2>
          <p className="text-xs text-gray-500 font-mono break-all">{order.payment_intent_id ?? '—'}</p>
          <p className="text-xs text-gray-400 mt-1">Use this ID to look up the charge in Stripe Dashboard.</p>
        </div>
      </div>
    </div>
  )
}
