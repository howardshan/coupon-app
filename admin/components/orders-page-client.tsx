'use client'

import { useState, useCallback } from 'react'
import Link from 'next/link'
import OrderRefundButtons from '@/components/order-refund-buttons'
import OrderSearchForm from '@/components/order-search-form'
import OrdersTableContainer from '@/components/orders-table-container'
import { getOrdersList, type OrdersListPayload } from '@/app/actions/orders'

type OrdersPageClientProps = OrdersListPayload & {
  initialSearchQ?: string
}

export default function OrdersPageClient({
  orders: initialOrders,
  redeemedMerchantNames: initialRedeemedMerchantNames,
  fetchError: initialFetchError,
  refundCount: initialRefundCount,
  initialSearchQ = '',
}: OrdersPageClientProps) {
  const [orders, setOrders] = useState(initialOrders)
  const [redeemedMerchantNames, setRedeemedMerchantNames] = useState(initialRedeemedMerchantNames)
  const [fetchError, setFetchError] = useState(initialFetchError)
  const [refundCount, setRefundCount] = useState(initialRefundCount)
  const [isSearching, setIsSearching] = useState(false)
  const [currentSearchQ, setCurrentSearchQ] = useState(initialSearchQ)

  const handleSearch = useCallback(async (q: string) => {
    setCurrentSearchQ(q)
    setIsSearching(true)
    try {
      const payload = await getOrdersList(q)
      setOrders(payload.orders)
      setRedeemedMerchantNames(payload.redeemedMerchantNames)
      setFetchError(payload.fetchError)
      setRefundCount(payload.refundCount)
    } finally {
      setIsSearching(false)
    }
  }, [])

  return (
    <div>
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4 mb-6">
        <div className="flex items-center gap-3 flex-wrap">
          <h1 className="text-2xl font-bold text-gray-900">Orders</h1>
          {refundCount > 0 && (
            <span className="text-sm bg-orange-100 text-orange-700 px-3 py-1 rounded-full font-medium">
              {refundCount} refund {refundCount === 1 ? 'request' : 'requests'}
            </span>
          )}
        </div>
        <OrderSearchForm
          initialValue={initialSearchQ}
          onSearch={handleSearch}
          isSearching={isSearching}
        />
      </div>

      <OrdersTableContainer>
        <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
          <table className="w-full text-sm">
            <thead className="bg-gray-50 border-b border-gray-200">
              <tr>
                <th className="text-left px-4 py-3 font-medium text-gray-600">Order #</th>
                <th className="text-left px-4 py-3 font-medium text-gray-600">Deal</th>
                <th className="text-left px-4 py-3 font-medium text-gray-600">Merchant</th>
                <th className="text-left px-4 py-3 font-medium text-gray-600">Redeemed At</th>
                <th className="text-left px-4 py-3 font-medium text-gray-600">Customer</th>
                <th className="text-left px-4 py-3 font-medium text-gray-600">Amount</th>
                <th className="text-left px-4 py-3 font-medium text-gray-600">Status</th>
                <th className="text-left px-4 py-3 font-medium text-gray-600">Date</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {(orders as any[])?.map((o: any) => {
                const raw = o.coupons
                const first = Array.isArray(raw) ? raw[0] : raw
                const redeemedId = first?.redeemed_at_merchant_id
                const redeemedName = redeemedId ? redeemedMerchantNames[redeemedId] : null

                return (
                  <tr key={o.id} className={o.status === 'refund_requested' ? 'bg-orange-50/60' : 'hover:bg-gray-50'}>
                    <td className="px-4 py-3 font-mono text-gray-700">
                      <Link href={`/orders/${o.id}`} className="text-blue-600 hover:underline">
                        {o.order_number ?? `DJ-${String(o.id).slice(0, 8).toUpperCase()}`}
                      </Link>
                    </td>
                    <td className="px-4 py-3 font-medium text-gray-900">
                      <Link href={`/orders/${o.id}`} className="text-blue-600 hover:underline">
                        {o.deals?.title ?? '—'}
                      </Link>
                    </td>
                    <td className="px-4 py-3 text-gray-600">{o.deals?.merchants?.name ?? '—'}</td>
                    <td className="px-4 py-3 text-gray-600">
                      {redeemedName ? (
                        <span className="text-xs">{redeemedName}</span>
                      ) : (
                        <span className="text-gray-400">—</span>
                      )}
                    </td>
                    <td className="px-4 py-3 text-gray-600">{o.users?.email ?? '—'}</td>
                    <td className="px-4 py-3 text-gray-900">
                      ${o.total_amount}
                      {o.quantity > 1 && (
                        <span className="text-gray-400 text-xs ml-1">×{o.quantity}</span>
                      )}
                    </td>
                    <td className="px-4 py-3">
                      <OrderRefundButtons orderId={o.id} initialStatus={o.status} />
                    </td>
                    <td className="px-4 py-3 text-gray-500">
                      {new Date(o.created_at).toLocaleDateString()}
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
          {(!orders || orders.length === 0) && (
            <div className="text-center py-8">
              {fetchError ? (
                <p className="text-red-600 text-sm mb-2">Failed to load orders: {fetchError}</p>
              ) : null}
              <p className="text-gray-400">
                {currentSearchQ !== '' ? 'No orders match your search.' : 'No orders yet'}
              </p>
            </div>
          )}
        </div>
      </OrdersTableContainer>
    </div>
  )
}
