'use client'

import Link from 'next/link'
import { useState } from 'react'

type ActivityTab = 'orders' | 'coupons'

// 服务端序列化后的订单/券行（与 Supabase select 结构一致）
type OrderRow = Record<string, unknown> & {
  id: string
  order_number?: string | null
  total_amount?: number | string | null
  status?: string
  created_at: string
  deals?: unknown
  order_items?: unknown
}

type CouponRow = Record<string, unknown> & {
  id: string
  deal_id?: string
  status: string
  used_at?: string | null
  expires_at?: string | null
  created_at: string
  deals?: unknown
}

export default function UserDetailActivityTabs({
  orders,
  coupons,
  className,
}: {
  orders: OrderRow[]
  coupons: CouponRow[]
  /** 弹窗内可传 rounded-lg 等覆盖默认大圆角 */
  className?: string
}) {
  const [tab, setTab] = useState<ActivityTab>('orders')
  const orderCount = orders.length
  const couponCount = coupons.length

  return (
    <div
      className={`bg-white rounded-xl border border-gray-200 overflow-hidden${className ? ` ${className}` : ''}`}
    >
      <div className="flex border-b border-gray-200 bg-gray-50 px-2 pt-2 gap-1">
        <button
          type="button"
          onClick={() => setTab('orders')}
          className={`px-3 py-2 text-sm font-medium rounded-t-md border-b-2 -mb-px transition-colors ${
            tab === 'orders'
              ? 'border-blue-600 text-blue-700 bg-white'
              : 'border-transparent text-gray-600 hover:text-gray-900'
          }`}
        >
          Purchase History ({orderCount})
        </button>
        <button
          type="button"
          onClick={() => setTab('coupons')}
          className={`px-3 py-2 text-sm font-medium rounded-t-md border-b-2 -mb-px transition-colors ${
            tab === 'coupons'
              ? 'border-blue-600 text-blue-700 bg-white'
              : 'border-transparent text-gray-600 hover:text-gray-900'
          }`}
        >
          Coupon Records ({couponCount})
        </button>
      </div>

      <div className="max-h-[60vh] overflow-auto">
        {tab === 'orders' ? (
          orderCount > 0 ? (
            <table className="w-full text-sm">
              <thead className="sticky top-0 z-10 bg-gray-50 border-b border-gray-200 shadow-[0_1px_0_0_rgb(229_231_235)]">
                <tr>
                  <th className="text-left px-4 py-2 font-medium text-gray-600">Order</th>
                  <th className="text-left px-4 py-2 font-medium text-gray-600">Deal(s)</th>
                  <th className="text-left px-4 py-2 font-medium text-gray-600">Merchant</th>
                  <th className="text-left px-4 py-2 font-medium text-gray-600">Qty</th>
                  <th className="text-left px-4 py-2 font-medium text-gray-600">Total</th>
                  <th className="text-left px-4 py-2 font-medium text-gray-600">Status</th>
                  <th className="text-left px-4 py-2 font-medium text-gray-600">Date</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {orders.map((o) => {
                  const items = o.order_items as Record<string, unknown>[] | null | undefined
                  const hasItems = items && items.length > 0

                  const uniqueDeals = new Map<string, { title: string; merchantName: string }>()
                  if (hasItems) {
                    for (const item of items) {
                      const d = item.deals as Record<string, unknown> | undefined
                      const m = Array.isArray(d?.merchants)
                        ? (d.merchants as unknown[])[0]
                        : d?.merchants
                      const merchant = m as { name?: string } | undefined
                      const dealId = item.deal_id as string
                      if (d && dealId && !uniqueDeals.has(dealId)) {
                        uniqueDeals.set(dealId, {
                          title: (d.title as string) ?? '—',
                          merchantName: merchant?.name ?? '—',
                        })
                      }
                    }
                  }

                  const orderDeals = o.deals as Record<string, unknown> | undefined
                  const orderMerchants = orderDeals?.merchants as { name?: string } | undefined

                  const dealNames = hasItems
                    ? Array.from(uniqueDeals.values()).map((d) => d.title)
                    : [(orderDeals?.title as string) ?? '—']
                  const merchantNames = hasItems
                    ? [...new Set(Array.from(uniqueDeals.values()).map((d) => d.merchantName))]
                    : [orderMerchants?.name ?? '—']
                  const qty = hasItems ? items.length : 1

                  return (
                    <tr key={o.id} className="hover:bg-gray-50">
                      <td className="px-4 py-2 text-gray-700 font-mono">
                        <Link href={`/orders/${o.id}`} className="text-blue-600 hover:underline">
                          {o.order_number ?? o.id.slice(0, 8)}
                        </Link>
                      </td>
                      <td className="px-4 py-2 text-gray-900">
                        {dealNames.slice(0, 2).map((name, i) => (
                          <div key={i}>{name}</div>
                        ))}
                        {dealNames.length > 2 && (
                          <span className="text-xs text-gray-500">+{dealNames.length - 2} more</span>
                        )}
                      </td>
                      <td className="px-4 py-2 text-gray-600">{merchantNames.join(', ')}</td>
                      <td className="px-4 py-2 text-gray-600">{qty}</td>
                      <td className="px-4 py-2 text-gray-900 font-medium">
                        ${(Number(o.total_amount) || 0).toFixed(2)}
                      </td>
                      <td className="px-4 py-2">
                        {hasItems ? (
                          <div className="flex flex-wrap gap-1">
                            {(() => {
                              const statusCounts: Record<string, number> = {}
                              for (const item of items) {
                                const s = String(item.customer_status ?? '')
                                statusCounts[s] = (statusCounts[s] ?? 0) + 1
                              }
                              return Object.entries(statusCounts).map(([s, count]) => (
                                <OrderStatusBadge key={s} status={s} count={count > 1 ? count : undefined} />
                              ))
                            })()}
                          </div>
                        ) : (
                          <OrderStatusBadge status={String(o.status ?? '')} />
                        )}
                      </td>
                      <td className="px-4 py-2 text-gray-500">
                        {new Date(o.created_at).toLocaleDateString('en-US')}
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          ) : (
            <p className="text-center text-gray-400 py-8">No orders found</p>
          )
        ) : couponCount > 0 ? (
          <table className="w-full text-sm">
            <thead className="sticky top-0 z-10 bg-gray-50 border-b border-gray-200 shadow-[0_1px_0_0_rgb(229_231_235)]">
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
              {coupons.map((c) => {
                const d = c.deals as Record<string, unknown> | undefined
                const m = d?.merchants as { name?: string } | undefined
                return (
                  <tr key={c.id} className="hover:bg-gray-50">
                    <td className="px-4 py-2 text-gray-900">{(d?.title as string) ?? '—'}</td>
                    <td className="px-4 py-2 text-gray-600">{m?.name ?? '—'}</td>
                    <td className="px-4 py-2">
                      <CouponStatusBadge status={c.status} />
                    </td>
                    <td className="px-4 py-2 text-gray-500">
                      {c.used_at ? new Date(c.used_at).toLocaleDateString('en-US') : '—'}
                    </td>
                    <td className="px-4 py-2 text-gray-500">
                      {c.expires_at ? new Date(c.expires_at).toLocaleDateString('en-US') : '—'}
                    </td>
                    <td className="px-4 py-2 text-gray-500">
                      {new Date(c.created_at).toLocaleDateString('en-US')}
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        ) : (
          <p className="text-center text-gray-400 py-8">No coupons found</p>
        )}
      </div>
    </div>
  )
}

function OrderStatusBadge({ status, count }: { status: string; count?: number }) {
  const styles: Record<string, string> = {
    unused: 'bg-blue-100 text-blue-700',
    used: 'bg-gray-100 text-gray-600',
    expired: 'bg-red-100 text-red-700',
    refund_pending: 'bg-amber-100 text-amber-700',
    refund_review: 'bg-orange-100 text-orange-700',
    refund_reject: 'bg-amber-100 text-amber-700',
    refund_success: 'bg-purple-100 text-purple-700',
    paid: 'bg-green-100 text-green-700',
    pending: 'bg-yellow-100 text-yellow-700',
    refunded: 'bg-red-100 text-red-700',
    voided: 'bg-gray-100 text-gray-600',
    captured: 'bg-blue-100 text-blue-700',
  }
  const labels: Record<string, string> = {
    unused: 'Unused',
    used: 'Used',
    expired: 'Expired',
    refund_pending: 'Refund Pending',
    refund_review: 'Refund Review',
    refund_reject: 'Rejected',
    refund_success: 'Refunded',
  }
  return (
    <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${styles[status] ?? 'bg-gray-100 text-gray-600'}`}>
      {labels[status] ?? status}
      {count != null ? ` ×${count}` : ''}
    </span>
  )
}

function CouponStatusBadge({ status }: { status: string }) {
  const styles: Record<string, string> = {
    unused: 'bg-blue-100 text-blue-700',
    active: 'bg-green-100 text-green-700',
    used: 'bg-gray-100 text-gray-600',
    expired: 'bg-red-100 text-red-700',
    refunded: 'bg-purple-100 text-purple-700',
    voided: 'bg-gray-100 text-gray-600',
    gifted: 'bg-purple-100 text-purple-700',
  }
  return (
    <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${styles[status] ?? 'bg-gray-100 text-gray-600'}`}>
      {status}
    </span>
  )
}
