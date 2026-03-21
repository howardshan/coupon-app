import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import UsersPageClient from '@/components/users-page-client'
import { getUsersList } from '@/app/actions/users-list'

export const dynamic = 'force-dynamic'

type SearchParams = {
  q?: string
  role?: string | string[]
  date_from?: string
  date_to?: string
  sort?: string
  page?: string
  limit?: string
}

export default async function UsersPage({
  searchParams,
}: {
  searchParams: Promise<SearchParams>
}) {
  const params = await searchParams
  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()
  const { data: profile } = await supabase.from('users').select('role').eq('id', user!.id).single()

  if (profile?.role !== 'admin') redirect('/dashboard')

  const roleArr =
    params.role != null
      ? (Array.isArray(params.role) ? params.role : [params.role]).filter(Boolean)
      : undefined

  const page = params.page ? parseInt(params.page, 10) : 1
  const limit = params.limit ? parseInt(params.limit, 10) : 20

  const sortRaw = params.sort ?? 'created_desc'
  const sort =
    sortRaw === 'created_desc' ||
    sortRaw === 'created_asc' ||
    sortRaw === 'email_asc' ||
    sortRaw === 'email_desc' ||
    sortRaw === 'name_asc' ||
    sortRaw === 'name_desc'
      ? sortRaw
      : 'created_desc'

  const payload = await getUsersList({
    q: params.q,
    roles: roleArr,
    dateFrom: params.date_from,
    dateTo: params.date_to,
    sort,
    page: Number.isFinite(page) ? page : 1,
    limit: Number.isFinite(limit) ? limit : 20,
  })

  return (
    <UsersPageClient
      users={payload.users}
      totalCount={payload.totalCount}
      fetchError={payload.fetchError}
      viewerUserId={user!.id}
      initialSearchQ={params.q ?? ''}
      initialRoles={roleArr ?? []}
      initialDateFrom={params.date_from ?? ''}
      initialDateTo={params.date_to ?? ''}
      initialSort={sort}
      initialPage={Number.isFinite(page) ? page : 1}
      initialLimit={Number.isFinite(limit) ? limit : 20}
    />
  )
}
