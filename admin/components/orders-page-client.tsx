'use client'

import { useCallback, useMemo, useRef } from 'react'
import Link from 'next/link'
import { useRouter, useSearchParams } from 'next/navigation'
import { useTransition } from 'react'
import OrderRefundButtons from '@/components/order-refund-buttons'
import OrderSearchForm from '@/components/order-search-form'
import OrdersTableContainer from '@/components/orders-table-container'
import { getOrderDetailStatusTags, STATUS_STYLES, STATUS_LABELS } from '@/lib/order-display-status'
import type { OrdersListPayload } from '@/app/actions/orders'

const STATUS_OPTIONS = [
  { value: 'unused', label: 'Unused' },
  { value: 'used', label: 'Used' },
  { value: 'refunded', label: 'Refunded' },
  { value: 'refund_requested', label: 'Refund Requested' },
  { value: 'expired', label: 'Expired' },
  { value: 'pending_refund', label: 'Pending Refund' },
  { value: 'refund_rejected', label: 'Refund Rejected' },
  { value: 'refund_failed', label: 'Refund Failed' },
]

const SORT_OPTIONS = [
  { value: 'date_desc', label: 'Date (newest)' },
  { value: 'date_asc', label: 'Date (oldest)' },
  { value: 'amount_desc', label: 'Amount (high–low)' },
  { value: 'amount_asc', label: 'Amount (low–high)' },
]

type OrdersPageClientProps = OrdersListPayload & {
  initialSearchQ?: string
  initialStatus?: string[]
  initialMerchantId?: string
  initialCustomerId?: string
  initialDateFrom?: string
  initialDateTo?: string
  initialAmountMin?: string
  initialAmountMax?: string
  initialSort?: string
  initialPage?: number
  initialLimit?: number
}

function buildOrdersUrl(params: URLSearchParams, updates: Record<string, string | number | undefined | string[]>) {
  const next = new URLSearchParams(params)
  for (const [key, val] of Object.entries(updates)) {
    if (val === undefined || val === '') {
      next.delete(key)
    } else if (Array.isArray(val)) {
      next.delete(key)
      val.forEach((v) => next.append(key, v))
    } else {
      next.set(key, String(val))
    }
  }
  next.delete('page')
  next.set('page', '1')
  return `/orders?${next.toString()}`
}

function buildOrdersUrlPage(params: URLSearchParams, page: number) {
  const next = new URLSearchParams(params)
  next.set('page', String(Math.max(1, page)))
  return `/orders?${next.toString()}`
}

export default function OrdersPageClient({
  orders: initialOrders,
  totalCount: initialTotalCount,
  redeemedMerchantNames: initialRedeemedMerchantNames,
  fetchError: initialFetchError,
  refundCount: initialRefundCount,
  merchantsForFilter = [],
  customersForFilter = [],
  initialSearchQ = '',
  initialStatus = [],
  initialMerchantId = '',
  initialCustomerId = '',
  initialDateFrom = '',
  initialDateTo = '',
  initialAmountMin = '',
  initialAmountMax = '',
  initialSort = 'date_desc',
  initialPage = 1,
  initialLimit = 20,
}: OrdersPageClientProps) {
  const router = useRouter()
  const searchParams = useSearchParams()
  const [isPending, startTransition] = useTransition()
  const searchParamsRef = useRef(searchParams)
  searchParamsRef.current = searchParams

  const returnToOrders = useMemo(() => {
    const qs = searchParams.toString()
    return `/orders${qs ? `?${qs}` : ''}`
  }, [searchParams])

  const handleSearch = useCallback((q: string) => {
    startTransition(() => {
      router.replace(buildOrdersUrl(searchParamsRef.current, { q: q || undefined }))
    })
  }, [router])

  const updateFilter = useCallback((updates: Record<string, string | number | undefined | string[]>) => {
    startTransition(() => {
      router.replace(buildOrdersUrl(searchParamsRef.current, updates))
    })
  }, [router])

  const goToPage = useCallback((page: number) => {
    startTransition(() => {
      router.replace(buildOrdersUrlPage(searchParamsRef.current, page))
    })
  }, [router])

  const clearFilters = useCallback(() => {
    startTransition(() => {
      router.replace('/orders')
    })
  }, [router])

  const hasFilters = useMemo(() => {
    const q = searchParams.get('q')
    const status = searchParams.get('status')
    const merchant = searchParams.get('merchant')
    const customer = searchParams.get('customer')
    const dateFrom = searchParams.get('date_from')
    const dateTo = searchParams.get('date_to')
    const amountMin = searchParams.get('amount_min')
    const amountMax = searchParams.get('amount_max')
    const sort = searchParams.get('sort')
    const pageNum = parseInt(searchParams.get('page') ?? '1', 10)
    return !!(q?.trim() || status || merchant || customer || dateFrom || dateTo || amountMin || amountMax || (sort && sort !== 'date_desc') || pageNum > 1)
  }, [searchParams])

  const totalCount = initialTotalCount
  const page = initialPage
  const limit = initialLimit
  const totalPages = Math.max(1, Math.ceil(totalCount / limit))
  const start = totalCount === 0 ? 0 : (page - 1) * limit + 1
  const end = Math.min(page * limit, totalCount)

  return (
    <div>
      <div className="flex flex-col gap-4 mb-6">
        <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
          <div className="flex items-center gap-3 flex-wrap">
            <h1 className="text-2xl font-bold text-gray-900">Orders</h1>
            {initialRefundCount > 0 && (
              <span className="text-sm bg-orange-100 text-orange-700 px-3 py-1 rounded-full font-medium">
                {initialRefundCount} refund {initialRefundCount === 1 ? 'request' : 'requests'}
              </span>
            )}
          </div>
          <OrderSearchForm
            initialValue={initialSearchQ}
            onSearch={handleSearch}
            isSearching={isPending}
          />
        </div>

        {/* Filters — URL persisted */}
        <div className="flex flex-wrap items-end gap-3 text-sm">
          <label className="flex flex-col gap-1">
            <span className="text-gray-600 font-medium">Status</span>
            <select
              value={initialStatus[0] ?? ''}
              onChange={(e) => updateFilter({ status: e.target.value ? [e.target.value] : undefined })}
              className="px-3 py-2 border border-gray-300 rounded-lg bg-white min-w-[140px]"
            >
              <option value="">All</option>
              {STATUS_OPTIONS.map((o) => (
                <option key={o.value} value={o.value}>{o.label}</option>
              ))}
            </select>
          </label>
          <label className="flex flex-col gap-1">
            <span className="text-gray-600 font-medium">Merchant</span>
            <select
              value={initialMerchantId}
              onChange={(e) => updateFilter({ merchant: e.target.value || undefined })}
              className="px-3 py-2 border border-gray-300 rounded-lg bg-white min-w-[160px]"
            >
              <option value="">All</option>
              {merchantsForFilter.map((m) => (
                <option key={m.id} value={m.id}>{m.name}</option>
              ))}
            </select>
          </label>
          <label className="flex flex-col gap-1">
            <span className="text-gray-600 font-medium">Customer</span>
            <input
              type="text"
              list="customer-filter-list"
              placeholder="Email or ID"
              defaultValue={
                initialCustomerId
                  ? customersForFilter.find((c) => c.id === initialCustomerId)?.email ?? initialCustomerId
                  : ''
              }
              onBlur={(e) => {
                const val = e.target.value.trim()
                if (!val) {
                  updateFilter({ customer: undefined })
                  return
                }
                // 先匹配下拉列表中的 email → id
                const match = customersForFilter.find((c) => c.email === val)
                updateFilter({ customer: match ? match.id : val })
              }}
              onKeyDown={(e) => {
                if (e.key === 'Enter') {
                  (e.target as HTMLInputElement).blur()
                }
              }}
              className="px-3 py-2 border border-gray-300 rounded-lg bg-white min-w-[200px]"
            />
            <datalist id="customer-filter-list">
              {customersForFilter.map((c) => (
                <option key={c.id} value={c.email} />
              ))}
            </datalist>
          </label>
          <label className="flex flex-col gap-1">
            <span className="text-gray-600 font-medium">Date from</span>
            <input
              type="date"
              value={initialDateFrom}
              onChange={(e) => updateFilter({ date_from: e.target.value || undefined })}
              className="px-3 py-2 border border-gray-300 rounded-lg"
            />
          </label>
          <label className="flex flex-col gap-1">
            <span className="text-gray-600 font-medium">Date to</span>
            <input
              type="date"
              value={initialDateTo}
              onChange={(e) => updateFilter({ date_to: e.target.value || undefined })}
              className="px-3 py-2 border border-gray-300 rounded-lg"
            />
          </label>
          <label className="flex flex-col gap-1">
            <span className="text-gray-600 font-medium">Amount min</span>
            <input
              type="number"
              min={0}
              step={0.01}
              placeholder="0"
              value={initialAmountMin}
              onChange={(e) => updateFilter({ amount_min: e.target.value || undefined })}
              className="px-3 py-2 border border-gray-300 rounded-lg w-24"
            />
          </label>
          <label className="flex flex-col gap-1">
            <span className="text-gray-600 font-medium">Amount max</span>
            <input
              type="number"
              min={0}
              step={0.01}
              placeholder="—"
              value={initialAmountMax}
              onChange={(e) => updateFilter({ amount_max: e.target.value || undefined })}
              className="px-3 py-2 border border-gray-300 rounded-lg w-24"
            />
          </label>
          <label className="flex flex-col gap-1">
            <span className="text-gray-600 font-medium">Sort</span>
            <select
              value={initialSort}
              onChange={(e) => updateFilter({ sort: e.target.value || undefined })}
              className="px-3 py-2 border border-gray-300 rounded-lg bg-white min-w-[140px]"
            >
              {SORT_OPTIONS.map((o) => (
                <option key={o.value} value={o.value}>{o.label}</option>
              ))}
            </select>
          </label>
          {hasFilters && (
            <button
              type="button"
              onClick={clearFilters}
              disabled={isPending}
              className="px-3 py-2 text-sm font-medium border border-gray-300 rounded-lg bg-white text-gray-700 hover:bg-gray-50 disabled:opacity-50 transition-colors"
            >
              Clear filters
            </button>
          )}
          {isPending && (
            <span className="text-gray-500 text-sm py-2">Updating…</span>
          )}
        </div>

        <p className="text-sm text-gray-600">
          {totalCount === 0
            ? 'No orders'
            : `Showing ${start}–${end} of ${totalCount}`}
        </p>
      </div>

      <OrdersTableContainer>
        <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
          <table className="w-full text-sm">
            <thead className="bg-gray-50 border-b border-gray-200">
              <tr>
                <th className="text-left px-4 py-3 font-medium text-gray-600">Order #</th>
                <th className="text-left px-4 py-3 font-medium text-gray-600">Merchant</th>
                <th className="text-left px-4 py-3 font-medium text-gray-600">Redeemed At</th>
                <th className="text-left px-4 py-3 font-medium text-gray-600">Customer</th>
                <th className="text-left px-4 py-3 font-medium text-gray-600">Amount</th>
                <th className="text-left px-4 py-3 font-medium text-gray-600">Status</th>
                <th className="text-left px-4 py-3 font-medium text-gray-600">Date</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {(initialOrders as any[])?.map((o: any) => {
                const raw = o.coupons
                const first = Array.isArray(raw) ? raw[0] : raw
                const redeemedId = first?.redeemed_at_merchant_id
                const redeemedName = redeemedId ? initialRedeemedMerchantNames[redeemedId] : null
                // V3 订单从 order_items 推导聚合状态；旧订单沿用 orders.status
                const items = o.order_items as { customer_status?: string }[] | null
                const v3Status = (() => {
                  if (!items || items.length === 0) return null
                  const statuses = items.map(i => i.customer_status ?? 'unused')
                  if (statuses.every(s => s === 'refund_success')) return 'refunded'
                  // 仅 refund_review 视为需人工 Approve；refund_processing / refund_pending 为等 Stripe webhook
                  if (statuses.some(s => s === 'refund_review')) return 'refund_requested'
                  if (statuses.some(s => s === 'refund_processing' || s === 'refund_pending')) {
                    return 'refund_processing'
                  }
                  if (statuses.every(s => s === 'used')) return 'used'
                  if (statuses.some(s => s === 'used')) return 'used'
                  return null
                })()
                const effectiveStatus = v3Status ?? o.status
                const orderForDisplay = {
                  status: effectiveStatus,
                  refund_rejected_at: o.refund_rejected_at,
                  coupon_expires_at: first?.expires_at ?? o.coupon_expires_at ?? null,
                  deal_expires_at: o.deal_expires_at,
                  deals: o.deals,
                }
                const statusTags = getOrderDetailStatusTags(orderForDisplay)
                const showTags = statusTags.slice(0, 2)
                const extraCount = statusTags.length - 2

                const highlightRefundAttention = effectiveStatus === 'refund_requested'
                return (
                  <tr key={o.id} className={highlightRefundAttention ? 'bg-orange-50/60' : 'hover:bg-gray-50'}>
                    <td className="px-4 py-3 font-mono text-gray-700">
                      <Link href={`/orders/${o.id}`} className="text-blue-600 hover:underline">
                        {o.order_number ?? `DJ-${String(o.id).slice(0, 8).toUpperCase()}`}
                      </Link>
                    </td>
                    <td className="px-4 py-3 text-gray-600">
                      {(() => {
                        const items = o.order_items as any[] | null
                        if (items && items.length > 0) {
                          const uniqueMerchants = new Map<string, string>()
                          for (const item of items) {
                            const m = Array.isArray(item.deals?.merchants) ? item.deals.merchants[0] : item.deals?.merchants
                            if (m?.id && !uniqueMerchants.has(m.id)) {
                              uniqueMerchants.set(m.id, m.name)
                            }
                          }
                          return Array.from(uniqueMerchants.values()).join(', ') || '—'
                        }
                        return o.deals?.merchants?.name ?? '—'
                      })()}
                    </td>
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
                      {(() => {
                        const items = o.order_items as any[] | null
                        const qty = items && items.length > 0 ? items.length : o.quantity
                        return qty > 1 ? <span className="text-gray-400 text-xs ml-1">×{qty}</span> : null
                      })()}
                    </td>
                    <td className="px-4 py-3">
                      <div className="flex items-center gap-1.5 flex-wrap">
                        {showTags.map((tag) => (
                          <span
                            key={tag}
                            className={`px-2 py-0.5 rounded-full text-xs font-medium ${STATUS_STYLES[tag] ?? 'bg-gray-100 text-gray-600'}`}
                          >
                            {STATUS_LABELS[tag] ?? tag}
                          </span>
                        ))}
                        {extraCount > 0 && (
                          <Link
                            href={`/orders/${o.id}`}
                            className="px-2 py-0.5 rounded-full text-xs font-medium bg-gray-200 text-gray-600 hover:bg-gray-300 transition-colors"
                            title={`+${extraCount} more — view detail`}
                          >
                            +{extraCount}
                          </Link>
                        )}
                        {highlightRefundAttention && (
                          <OrderRefundButtons orderId={o.id} initialStatus="refund_requested" />
                        )}
                      </div>
                    </td>
                    <td className="px-4 py-3 text-gray-500">
                      {new Date(o.created_at).toLocaleDateString('en-US')}
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
          {(!initialOrders || initialOrders.length === 0) && (
            <div className="text-center py-8">
              {initialFetchError ? (
                <p className="text-red-600 text-sm mb-2">Failed to load orders: {initialFetchError}</p>
              ) : null}
              <p className="text-gray-400">
                {initialSearchQ !== '' || initialStatus?.length || initialMerchantId || initialCustomerId || initialDateFrom || initialDateTo ? 'No orders match your filters.' : 'No orders yet'}
              </p>
            </div>
          )}
        </div>

        {/* Pagination */}
        {totalPages > 1 && (
          <div className="mt-4 flex items-center justify-center gap-2 flex-wrap">
            <button
              type="button"
              onClick={() => goToPage(page - 1)}
              disabled={page <= 1 || isPending}
              className="px-3 py-1.5 text-sm font-medium border border-gray-300 rounded-lg bg-white text-gray-700 disabled:opacity-50 disabled:cursor-not-allowed hover:bg-gray-50"
            >
              Previous
            </button>
            <span className="px-3 py-1.5 text-sm text-gray-600">
              Page {page} of {totalPages}
            </span>
            <button
              type="button"
              onClick={() => goToPage(page + 1)}
              disabled={page >= totalPages || isPending}
              className="px-3 py-1.5 text-sm font-medium border border-gray-300 rounded-lg bg-white text-gray-700 disabled:opacity-50 disabled:cursor-not-allowed hover:bg-gray-50"
            >
              Next
            </button>
          </div>
        )}
      </OrdersTableContainer>
    </div>
  )
}
