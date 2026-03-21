'use client'

import { useCallback, useEffect, useMemo, useRef } from 'react'
import Link from 'next/link'
import { useRouter, useSearchParams } from 'next/navigation'
import { useTransition } from 'react'
import AdminDebouncedSearchForm from '@/components/admin-debounced-search-form'
import AdminListScrollArea from '@/components/admin-list-scroll-area'
import DealSortOrder from '@/components/deal-sort-order'
import OrdersFilterMultiSelect from '@/components/orders-filter-multi-select'
import { buildAdminListUrl, buildAdminListUrlPage } from '@/lib/admin-list-url'
import type { DealsListPayload } from '@/app/actions/deals-list'

const DEALS_PATH = '/deals'

const DEAL_STATUS_OPTIONS = [
  { value: 'pending', label: 'Pending' },
  { value: 'active', label: 'Active' },
  { value: 'inactive', label: 'Inactive' },
  { value: 'rejected', label: 'Rejected' },
  { value: 'expired', label: 'Expired' },
]

const SORT_OPTIONS = [
  { value: 'created_desc', label: 'Created (newest)' },
  { value: 'created_asc', label: 'Created (oldest)' },
  { value: 'price_desc', label: 'Price (high–low)' },
  { value: 'price_asc', label: 'Price (low–high)' },
]

const FILTER_CONTROL =
  'w-full min-w-0 px-3 py-2 border border-gray-300 rounded-lg bg-white text-gray-900'

type DealsPageClientProps = DealsListPayload & {
  initialSearchQ?: string
  initialStatusTokens?: string[]
  initialMerchantIds?: string[]
  initialDateFrom?: string
  initialDateTo?: string
  initialPriceMin?: string
  initialPriceMax?: string
  initialSort?: string
  initialPage?: number
  initialLimit?: number
}

export default function DealsPageClient({
  deals: initialDeals,
  totalCount: initialTotalCount,
  merchantsForFilter = [],
  fetchError: initialFetchError,
  initialSearchQ = '',
  initialStatusTokens = [],
  initialMerchantIds = [],
  initialDateFrom = '',
  initialDateTo = '',
  initialPriceMin = '',
  initialPriceMax = '',
  initialSort = 'created_desc',
  initialPage = 1,
  initialLimit = 20,
}: DealsPageClientProps) {
  const router = useRouter()
  const searchParams = useSearchParams()
  const [isPending, startTransition] = useTransition()
  const searchParamsRef = useRef(searchParams)
  useEffect(() => {
    searchParamsRef.current = searchParams
  }, [searchParams])

  const returnToDeals = useMemo(() => {
    const qs = searchParams.toString()
    return `/deals${qs ? `?${qs}` : ''}`
  }, [searchParams])

  const handleSearch = useCallback(
    (q: string) => {
      startTransition(() => {
        router.replace(
          buildAdminListUrl(DEALS_PATH, searchParamsRef.current, { q: q || undefined })
        )
      })
    },
    [router]
  )

  const updateFilter = useCallback(
    (updates: Record<string, string | number | undefined | string[]>) => {
      startTransition(() => {
        router.replace(buildAdminListUrl(DEALS_PATH, searchParamsRef.current, updates))
      })
    },
    [router]
  )

  const goToPage = useCallback(
    (p: number) => {
      startTransition(() => {
        router.replace(buildAdminListUrlPage(DEALS_PATH, searchParamsRef.current, p))
      })
    },
    [router]
  )

  const clearFilters = useCallback(() => {
    startTransition(() => {
      router.replace(DEALS_PATH)
    })
  }, [router])

  const hasFilters = useMemo(() => {
    const q = searchParams.get('q')
    const hasStatus = searchParams.getAll('status').some(Boolean)
    const hasMerchant = searchParams.getAll('merchant').some(Boolean)
    const dateFrom = searchParams.get('date_from')
    const dateTo = searchParams.get('date_to')
    const priceMin = searchParams.get('price_min')
    const priceMax = searchParams.get('price_max')
    const sort = searchParams.get('sort')
    const pageNum = parseInt(searchParams.get('page') ?? '1', 10)
    return !!(
      q?.trim() ||
      hasStatus ||
      hasMerchant ||
      dateFrom ||
      dateTo ||
      priceMin ||
      priceMax ||
      (sort && sort !== 'created_desc') ||
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
      <div className="mb-6 flex flex-col gap-4">
        <h1 className="text-2xl font-bold text-gray-900">Deals</h1>

        <div className="w-full max-w-3xl">
          <AdminDebouncedSearchForm
            fullWidth
            initialValue={initialSearchQ}
            onQueryChange={handleSearch}
            isQueryPending={isPending}
            placeholder="Search by title or deal ID…"
            ariaLabel="Search deals by title or deal ID"
            inlineLoadingText="Searching…"
          />
        </div>

        <div className="flex flex-col gap-3 text-sm">
          <div className="grid grid-cols-2 items-start gap-3 sm:grid-cols-4 xl:grid-cols-7">
            <div className="min-w-0">
              <OrdersFilterMultiSelect
                fieldLabel="Deal status"
                options={DEAL_STATUS_OPTIONS}
                selectedValues={initialStatusTokens}
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
              <span className="font-medium text-gray-600">Created from</span>
              <input
                type="date"
                value={initialDateFrom}
                onChange={(e) => updateFilter({ date_from: e.target.value || undefined })}
                className={FILTER_CONTROL}
              />
            </label>
            <label className="flex min-w-0 flex-col gap-1">
              <span className="font-medium text-gray-600">Created to</span>
              <input
                type="date"
                value={initialDateTo}
                onChange={(e) => updateFilter({ date_to: e.target.value || undefined })}
                className={FILTER_CONTROL}
              />
            </label>
            <label className="flex min-w-0 flex-col gap-1">
              <span className="font-medium text-gray-600">Price min</span>
              <input
                type="number"
                min={0}
                step={0.01}
                placeholder="0"
                value={initialPriceMin}
                onChange={(e) => updateFilter({ price_min: e.target.value || undefined })}
                className={FILTER_CONTROL}
              />
            </label>
            <label className="flex min-w-0 flex-col gap-1">
              <span className="font-medium text-gray-600">Price max</span>
              <input
                type="number"
                min={0}
                step={0.01}
                placeholder="—"
                value={initialPriceMax}
                onChange={(e) => updateFilter({ price_max: e.target.value || undefined })}
                className={FILTER_CONTROL}
              />
            </label>
            <label className="flex min-w-0 flex-col gap-1">
              <span className="font-medium text-gray-600">Sort</span>
              <select
                value={initialSort}
                onChange={(e) => updateFilter({ sort: e.target.value || undefined })}
                className={FILTER_CONTROL}
              >
                {SORT_OPTIONS.map((o) => (
                  <option key={o.value} value={o.value}>
                    {o.label}
                  </option>
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
                className="rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm font-medium text-gray-700 transition-colors hover:bg-gray-50 disabled:opacity-50"
              >
                Clear filters
              </button>
            )}
            {isPending && <span className="text-sm text-gray-500">Updating…</span>}
          </div>
        </div>

        <p className="text-sm text-gray-600">
          {totalCount === 0 ? 'No deals' : `Showing ${start}–${end} of ${totalCount}`}
        </p>
      </div>

      <AdminListScrollArea>
      <div className="overflow-hidden rounded-xl border border-gray-200 bg-white">
        <table className="w-full text-sm">
          <thead className="border-b border-gray-200 bg-gray-50">
            <tr>
              <th className="px-4 py-3 text-left font-medium text-gray-600">Title</th>
              <th className="px-4 py-3 text-left font-medium text-gray-600">Merchant</th>
              <th className="px-4 py-3 text-left font-medium text-gray-600">Sale Price</th>
              <th className="px-4 py-3 text-left font-medium text-gray-600">Scope</th>
              <th className="px-4 py-3 text-left font-medium text-gray-600">Status</th>
              <th className="px-4 py-3 text-left font-medium text-gray-600">Created</th>
              <th className="px-4 py-3 text-left font-medium text-gray-600">Sort Order</th>
              <th className="px-4 py-3 text-left font-medium text-gray-600"></th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100">
            {(initialDeals as Record<string, unknown>[])?.map((d) => {
              const applicableIds = d.applicable_merchant_ids as string[] | null
              const isMultiStore = applicableIds && applicableIds.length > 0
              const merchants = d.merchants as { name?: string; brands?: { name?: string } } | null | undefined
              const brandName = merchants?.brands?.name

              return (
                <tr key={String(d.id)} className="hover:bg-gray-50">
                  <td className="px-4 py-3 font-medium text-gray-900">
                    <Link
                      href={`/deals/${d.id}`}
                      className="text-blue-600 hover:text-blue-800 hover:underline"
                    >
                      {String(d.title ?? '')}
                    </Link>
                  </td>
                  <td className="px-4 py-3 text-gray-600">
                    {merchants?.name ?? '—'}
                    {brandName ? (
                      <span className="ml-1 text-xs text-purple-600">({brandName})</span>
                    ) : null}
                  </td>
                  <td className="px-4 py-3 text-gray-900">
                    ${d.discount_price as number}
                    {d.original_price != null && (
                      <span className="ml-2 text-gray-400 line-through">${d.original_price as number}</span>
                    )}
                  </td>
                  <td className="px-4 py-3">
                    {isMultiStore ? (
                      <span className="rounded-full bg-purple-100 px-2 py-0.5 text-xs font-medium text-purple-700">
                        {applicableIds!.length} stores
                      </span>
                    ) : (
                      <span className="rounded-full bg-gray-100 px-2 py-0.5 text-xs font-medium text-gray-600">
                        Single
                      </span>
                    )}
                  </td>
                  <td className="px-4 py-3">
                    <DealStatusBadge
                      isActive={Boolean(d.is_active)}
                      expiresAt={String(d.expires_at ?? '')}
                    />
                  </td>
                  <td className="px-4 py-3 text-gray-500">
                    {d.created_at ? new Date(String(d.created_at)).toLocaleDateString() : '—'}
                  </td>
                  <td className="px-4 py-3">
                    <DealSortOrder
                      dealId={String(d.id)}
                      sortOrder={typeof d.sort_order === 'number' ? d.sort_order : null}
                    />
                  </td>
                  <td className="px-4 py-3">
                    <Link
                      href={`/deals/${d.id}?returnTo=${encodeURIComponent(returnToDeals)}`}
                      className="inline-flex items-center justify-center rounded-lg border border-blue-200 bg-blue-50 px-3 py-1.5 text-sm font-medium text-blue-700 transition-colors hover:bg-blue-100"
                    >
                      {d.is_active || d.deal_status === 'inactive' ? 'View' : 'Review'}
                    </Link>
                  </td>
                </tr>
              )
            })}
          </tbody>
        </table>
        {(!initialDeals || initialDeals.length === 0) && (
          <div className="py-8 text-center">
            {initialFetchError ? (
              <p className="mb-2 text-sm text-red-600">Failed to load deals: {initialFetchError}</p>
            ) : null}
            <p className="text-gray-400">
              {initialSearchQ !== '' ||
              initialStatusTokens.length > 0 ||
              initialMerchantIds.length > 0 ||
              initialDateFrom ||
              initialDateTo ||
              initialPriceMin ||
              initialPriceMax
                ? 'No deals match your filters.'
                : 'No deals found'}
            </p>
          </div>
        )}
      </div>
      </AdminListScrollArea>

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

function DealStatusBadge({ isActive, expiresAt }: { isActive: boolean; expiresAt: string }) {
  const now = new Date()
  const exp = expiresAt ? new Date(expiresAt) : null
  const expired = exp != null && !Number.isNaN(exp.getTime()) && exp < now
  const status = expired ? 'expired' : isActive ? 'active' : 'inactive'
  const styles: Record<string, string> = {
    active: 'bg-green-100 text-green-700',
    inactive: 'bg-gray-100 text-gray-600',
    expired: 'bg-red-100 text-red-700',
  }
  return (
    <span
      className={`rounded-full px-2 py-0.5 text-xs font-medium ${styles[status] ?? 'bg-gray-100 text-gray-600'}`}
    >
      {status}
    </span>
  )
}
