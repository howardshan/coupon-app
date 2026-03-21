'use client'

import { useCallback, useEffect, useMemo, useRef } from 'react'
import Link from 'next/link'
import { useRouter, useSearchParams } from 'next/navigation'
import { useTransition } from 'react'
import AdminDebouncedSearchForm from '@/components/admin-debounced-search-form'
import AdminListScrollArea from '@/components/admin-list-scroll-area'
import OrderRefundButtons from '@/components/order-refund-buttons'
import OrdersFilterMultiSelect from '@/components/orders-filter-multi-select'
import { buildAdminListUrl, buildAdminListUrlPage } from '@/lib/admin-list-url'
import { getOrderDetailStatusTags, STATUS_STYLES, STATUS_LABELS } from '@/lib/order-display-status'
import type { OrdersListPayload } from '@/app/actions/orders'

const ORDERS_PATH = '/orders'

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

// 筛选行内控件统一高度与宽度策略（grid 子项内 w-full）
const FILTER_CONTROL =
  'w-full min-w-0 px-3 py-2 border border-gray-300 rounded-lg bg-white text-gray-900'

type OrdersPageClientProps = OrdersListPayload & {
  initialSearchQ?: string
  initialStatus?: string[]
  initialMerchantIds?: string[]
  initialDateFrom?: string
  initialDateTo?: string
  initialAmountMin?: string
  initialAmountMax?: string
  initialSort?: string
  initialPage?: number
  initialLimit?: number
}

export default function OrdersPageClient({
  orders: initialOrders,
  totalCount: initialTotalCount,
  redeemedMerchantNames: initialRedeemedMerchantNames,
  fetchError: initialFetchError,
  refundCount: initialRefundCount,
  merchantsForFilter = [],
  initialSearchQ = '',
  initialStatus = [],
  initialMerchantIds = [],
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
  useEffect(() => {
    searchParamsRef.current = searchParams
  }, [searchParams])

  const returnToOrders = useMemo(() => {
    const qs = searchParams.toString()
    return `/orders${qs ? `?${qs}` : ''}`
  }, [searchParams])

  const handleSearch = useCallback((q: string) => {
    startTransition(() => {
      router.replace(
        buildAdminListUrl(ORDERS_PATH, searchParamsRef.current, { q: q || undefined })
      )
    })
  }, [router])

  const updateFilter = useCallback((updates: Record<string, string | number | undefined | string[]>) => {
    startTransition(() => {
      router.replace(buildAdminListUrl(ORDERS_PATH, searchParamsRef.current, updates))
    })
  }, [router])

  const goToPage = useCallback((page: number) => {
    startTransition(() => {
      router.replace(buildAdminListUrlPage(ORDERS_PATH, searchParamsRef.current, page))
    })
  }, [router])

  const clearFilters = useCallback(() => {
    startTransition(() => {
      router.replace(ORDERS_PATH)
    })
  }, [router])

  const hasFilters = useMemo(() => {
    const q = searchParams.get('q')
    const hasStatus = searchParams.getAll('status').some(Boolean)
    const hasMerchant = searchParams.getAll('merchant').some(Boolean)
    const dateFrom = searchParams.get('date_from')
    const dateTo = searchParams.get('date_to')
    const amountMin = searchParams.get('amount_min')
    const amountMax = searchParams.get('amount_max')
    const sort = searchParams.get('sort')
    const pageNum = parseInt(searchParams.get('page') ?? '1', 10)
    return !!(
      q?.trim() ||
      hasStatus ||
      hasMerchant ||
      dateFrom ||
      dateTo ||
      amountMin ||
      amountMax ||
      (sort && sort !== 'date_desc') ||
      pageNum > 1
    )
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
        <div className="flex items-center gap-3 flex-wrap">
          <h1 className="text-2xl font-bold text-gray-900">Orders</h1>
          {initialRefundCount > 0 && (
            <span className="text-sm bg-orange-100 text-orange-700 px-3 py-1 rounded-full font-medium">
              {initialRefundCount} refund {initialRefundCount === 1 ? 'request' : 'requests'}
            </span>
          )}
        </div>

        <div className="w-full max-w-3xl">
          <AdminDebouncedSearchForm
            fullWidth
            initialValue={initialSearchQ}
            onQueryChange={handleSearch}
            isQueryPending={isPending}
            placeholder="Order #, email, or deal…"
            ariaLabel="Search orders by order number, email, or deal title"
            inlineLoadingText="Searching…"
          />
        </div>

        {/* Filters — URL persisted；网格保证各列控件同宽 */}
        <div className="flex flex-col gap-3 text-sm">
          <div className="grid grid-cols-2 sm:grid-cols-4 xl:grid-cols-7 gap-3 items-start">
            <div className="min-w-0">
              <OrdersFilterMultiSelect
                fieldLabel="Status"
                options={STATUS_OPTIONS}
                selectedValues={initialStatus ?? []}
                triggerClassName={FILTER_CONTROL}
                onChange={(next) => updateFilter({ status: next.length ? next : undefined })}
              />
            </div>
            <div className="min-w-0">
              <OrdersFilterMultiSelect
                fieldLabel="Merchant"
                options={merchantsForFilter.map((m) => ({ value: m.id, label: m.name }))}
                selectedValues={initialMerchantIds}
                triggerClassName={FILTER_CONTROL}
                onChange={(next) => updateFilter({ merchant: next.length ? next : undefined })}
              />
            </div>
            <label className="flex min-w-0 flex-col gap-1">
              <span className="text-gray-600 font-medium">Date from</span>
              <input
                type="date"
                value={initialDateFrom}
                onChange={(e) => updateFilter({ date_from: e.target.value || undefined })}
                className={FILTER_CONTROL}
              />
            </label>
            <label className="flex min-w-0 flex-col gap-1">
              <span className="text-gray-600 font-medium">Date to</span>
              <input
                type="date"
                value={initialDateTo}
                onChange={(e) => updateFilter({ date_to: e.target.value || undefined })}
                className={FILTER_CONTROL}
              />
            </label>
            <label className="flex min-w-0 flex-col gap-1">
              <span className="text-gray-600 font-medium">Amount min</span>
              <input
                type="number"
                min={0}
                step={0.01}
                placeholder="0"
                value={initialAmountMin}
                onChange={(e) => updateFilter({ amount_min: e.target.value || undefined })}
                className={FILTER_CONTROL}
              />
            </label>
            <label className="flex min-w-0 flex-col gap-1">
              <span className="text-gray-600 font-medium">Amount max</span>
              <input
                type="number"
                min={0}
                step={0.01}
                placeholder="—"
                value={initialAmountMax}
                onChange={(e) => updateFilter({ amount_max: e.target.value || undefined })}
                className={FILTER_CONTROL}
              />
            </label>
            <label className="flex min-w-0 flex-col gap-1">
              <span className="text-gray-600 font-medium">Sort</span>
              <select
                value={initialSort}
                onChange={(e) => updateFilter({ sort: e.target.value || undefined })}
                className={FILTER_CONTROL}
              >
                {SORT_OPTIONS.map((o) => (
                  <option key={o.value} value={o.value}>{o.label}</option>
                ))}
              </select>
            </label>
          </div>
          <div className="flex flex-wrap items-center gap-3">
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
              <span className="text-gray-500 text-sm">Updating…</span>
            )}
          </div>
        </div>

        <p className="text-sm text-gray-600">
          {totalCount === 0
            ? 'No orders'
            : `Showing ${start}–${end} of ${totalCount}`}
        </p>
      </div>

      <AdminListScrollArea>
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
              {(initialOrders as unknown[] | null | undefined)?.map((row) => {
                const o = row as {
                  id: string
                  order_number?: string
                  status: string
                  total_amount: number
                  quantity: number
                  created_at: string
                  refund_rejected_at?: string | null
                  coupon_expires_at?: string | null
                  deal_expires_at?: string | null
                  coupons?: unknown
                  deals?: {
                    id?: string
                    title?: string
                    expires_at?: string | null
                    merchants?: { name?: string }
                  } | null
                  users?: { email?: string } | null
                }
                const couponRaw = o.coupons
                const first = Array.isArray(couponRaw) ? couponRaw[0] : couponRaw
                const redeemedId = first?.redeemed_at_merchant_id
                const redeemedName = redeemedId ? initialRedeemedMerchantNames[redeemedId] : null
                const orderForDisplay = {
                  status: o.status,
                  refund_rejected_at: o.refund_rejected_at,
                  coupon_expires_at: first?.expires_at ?? o.coupon_expires_at ?? null,
                  deal_expires_at: o.deal_expires_at,
                  deals: o.deals,
                }
                const statusTags = getOrderDetailStatusTags(orderForDisplay)
                const showTags = statusTags.slice(0, 2)
                const extraCount = statusTags.length - 2

                return (
                  <tr key={o.id} className={o.status === 'refund_requested' ? 'bg-orange-50/60' : 'hover:bg-gray-50'}>
                    <td className="px-4 py-3 font-mono text-gray-700">
                      <Link href={`/orders/${o.id}`} className="text-blue-600 hover:underline">
                        {o.order_number ?? `DJ-${String(o.id).slice(0, 8).toUpperCase()}`}
                      </Link>
                    </td>
                    <td className="px-4 py-3 font-medium text-gray-900">
                      {o.deals?.id ? (
                        <Link href={`/deals/${o.deals.id}?returnTo=${encodeURIComponent(returnToOrders)}`} className="text-blue-600 hover:underline">
                          {o.deals?.title ?? '—'}
                        </Link>
                      ) : (
                        <Link href={`/orders/${o.id}`} className="text-blue-600 hover:underline">
                          {o.deals?.title ?? '—'}
                        </Link>
                      )}
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
                        {o.status === 'refund_requested' && (
                          <OrderRefundButtons orderId={o.id} initialStatus={o.status} />
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
                {initialSearchQ !== '' || initialStatus?.length || initialMerchantIds.length > 0 || initialDateFrom || initialDateTo ? 'No orders match your filters.' : 'No orders yet'}
              </p>
            </div>
          )}
        </div>
      </AdminListScrollArea>

        {/* Pagination — 放在滚动区外便于始终可见 */}
        {totalPages > 1 && (
          <div className="mt-4 flex flex-wrap items-center justify-center gap-2">
            <button
              type="button"
              onClick={() => goToPage(page - 1)}
              disabled={page <= 1 || isPending}
              className="rounded-lg border border-gray-300 bg-white px-3 py-1.5 text-sm font-medium text-gray-700 hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50"
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
              className="rounded-lg border border-gray-300 bg-white px-3 py-1.5 text-sm font-medium text-gray-700 hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50"
            >
              Next
            </button>
          </div>
        )}
    </div>
  )
}
