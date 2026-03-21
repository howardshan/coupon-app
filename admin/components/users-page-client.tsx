'use client'

import { useCallback, useEffect, useMemo, useRef } from 'react'
import Link from 'next/link'
import { useRouter, useSearchParams } from 'next/navigation'
import { useTransition } from 'react'
import AdminDebouncedSearchForm from '@/components/admin-debounced-search-form'
import AdminListScrollArea from '@/components/admin-list-scroll-area'
import OrdersFilterMultiSelect from '@/components/orders-filter-multi-select'
import RoleSelect from '@/components/role-select'
import { buildAdminListUrl, buildAdminListUrlPage } from '@/lib/admin-list-url'
import type { UsersListPayload } from '@/app/actions/users-list'

const USERS_PATH = '/users'

const ROLE_OPTIONS = [
  { value: 'user', label: 'User' },
  { value: 'merchant', label: 'Merchant' },
  { value: 'admin', label: 'Admin' },
]

const SORT_OPTIONS = [
  { value: 'created_desc', label: 'Joined (newest)' },
  { value: 'created_asc', label: 'Joined (oldest)' },
  { value: 'email_asc', label: 'Email (A–Z)' },
  { value: 'email_desc', label: 'Email (Z–A)' },
  { value: 'name_asc', label: 'Name (A–Z)' },
  { value: 'name_desc', label: 'Name (Z–A)' },
]

const FILTER_CONTROL =
  'w-full min-w-0 px-3 py-2 border border-gray-300 rounded-lg bg-white text-gray-900'

type UsersPageClientProps = UsersListPayload & {
  viewerUserId: string
  initialSearchQ?: string
  initialRoles?: string[]
  initialDateFrom?: string
  initialDateTo?: string
  initialSort?: string
  initialPage?: number
  initialLimit?: number
}

export default function UsersPageClient({
  users: initialUsers,
  totalCount: initialTotalCount,
  fetchError: initialFetchError,
  viewerUserId,
  initialSearchQ = '',
  initialRoles = [],
  initialDateFrom = '',
  initialDateTo = '',
  initialSort = 'created_desc',
  initialPage = 1,
  initialLimit = 20,
}: UsersPageClientProps) {
  const router = useRouter()
  const searchParams = useSearchParams()
  const [isPending, startTransition] = useTransition()
  const searchParamsRef = useRef(searchParams)
  useEffect(() => {
    searchParamsRef.current = searchParams
  }, [searchParams])

  const handleSearch = useCallback(
    (q: string) => {
      startTransition(() => {
        router.replace(buildAdminListUrl(USERS_PATH, searchParamsRef.current, { q: q || undefined }))
      })
    },
    [router]
  )

  const updateFilter = useCallback(
    (updates: Record<string, string | number | undefined | string[]>) => {
      startTransition(() => {
        router.replace(buildAdminListUrl(USERS_PATH, searchParamsRef.current, updates))
      })
    },
    [router]
  )

  const goToPage = useCallback(
    (p: number) => {
      startTransition(() => {
        router.replace(buildAdminListUrlPage(USERS_PATH, searchParamsRef.current, p))
      })
    },
    [router]
  )

  const clearFilters = useCallback(() => {
    startTransition(() => {
      router.replace(USERS_PATH)
    })
  }, [router])

  const hasFilters = useMemo(() => {
    const q = searchParams.get('q')
    const hasRole = searchParams.getAll('role').some(Boolean)
    const dateFrom = searchParams.get('date_from')
    const dateTo = searchParams.get('date_to')
    const sort = searchParams.get('sort')
    const pageNum = parseInt(searchParams.get('page') ?? '1', 10)
    return !!(
      q?.trim() ||
      hasRole ||
      dateFrom ||
      dateTo ||
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
        <h1 className="text-2xl font-bold text-gray-900">Users</h1>

        <div className="w-full max-w-3xl">
          <AdminDebouncedSearchForm
            fullWidth
            initialValue={initialSearchQ}
            onQueryChange={handleSearch}
            isQueryPending={isPending}
            placeholder="Search by email, name, username, or user ID…"
            ariaLabel="Search users by email, name, username, or user ID"
            inlineLoadingText="Searching…"
          />
        </div>

        <div className="flex flex-col gap-3 text-sm">
          <div className="grid grid-cols-2 items-start gap-3 sm:grid-cols-4">
            <div className="min-w-0">
              <OrdersFilterMultiSelect
                fieldLabel="Role"
                options={ROLE_OPTIONS}
                selectedValues={initialRoles}
                triggerClassName={FILTER_CONTROL}
                onChange={(next) => updateFilter({ role: next.length ? next : undefined })}
              />
            </div>
            <label className="flex min-w-0 flex-col gap-1">
              <span className="font-medium text-gray-600">Joined from</span>
              <input
                type="date"
                value={initialDateFrom}
                onChange={(e) => updateFilter({ date_from: e.target.value || undefined })}
                className={FILTER_CONTROL}
              />
            </label>
            <label className="flex min-w-0 flex-col gap-1">
              <span className="font-medium text-gray-600">Joined to</span>
              <input
                type="date"
                value={initialDateTo}
                onChange={(e) => updateFilter({ date_to: e.target.value || undefined })}
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
          {totalCount === 0 ? 'No users' : `Showing ${start}–${end} of ${totalCount}`}
        </p>
      </div>

      <AdminListScrollArea>
        <div className="overflow-hidden rounded-xl border border-gray-200 bg-white">
          <table className="w-full text-sm">
            <thead className="border-b border-gray-200 bg-gray-50">
              <tr>
                <th className="px-4 py-3 text-left font-medium text-gray-600">Name</th>
                <th className="px-4 py-3 text-left font-medium text-gray-600">Email</th>
                <th className="px-4 py-3 text-left font-medium text-gray-600">Role</th>
                <th className="px-4 py-3 text-left font-medium text-gray-600">Joined</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {(initialUsers as UserRow[] | null | undefined)?.map((u) => (
                <tr key={u.id} className="hover:bg-gray-50">
                  <td className="px-4 py-3 font-medium text-gray-900">
                    <Link href={`/users/${u.id}`} className="text-blue-600 hover:underline">
                      {u.full_name || '—'}
                    </Link>
                  </td>
                  <td className="px-4 py-3 text-gray-600">{u.email}</td>
                  <td className="px-4 py-3">
                    {u.id === viewerUserId ? (
                      <span className="rounded-full bg-red-100 px-2 py-0.5 text-xs font-medium text-red-700">
                        admin (you)
                      </span>
                    ) : (
                      <RoleSelect userId={u.id} currentRole={u.role} />
                    )}
                  </td>
                  <td className="px-4 py-3 text-gray-500">
                    {u.created_at ? new Date(u.created_at).toLocaleDateString('en-US') : '—'}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          {(!initialUsers || initialUsers.length === 0) && (
            <div className="py-8 text-center">
              {initialFetchError ? (
                <p className="mb-2 text-sm text-red-600">Failed to load users: {initialFetchError}</p>
              ) : null}
              <p className="text-gray-400">
                {initialSearchQ !== '' ||
                initialRoles.length > 0 ||
                initialDateFrom ||
                initialDateTo
                  ? 'No users match your filters.'
                  : 'No users found'}
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

type UserRow = {
  id: string
  email: string
  full_name: string | null
  role: string
  created_at: string
  username?: string | null
}
