import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import DealsPageClient from '@/components/deals-page-client'
import { getDealsList } from '@/app/actions/deals-list'

export const dynamic = 'force-dynamic'

type SearchParams = {
  q?: string
  status?: string | string[]
  merchant?: string | string[]
  date_from?: string
  date_to?: string
  price_min?: string
  price_max?: string
  sort?: string
  page?: string
  limit?: string
}

export default async function DealsPage({
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

  const statusTokens =
    params.status != null
      ? (Array.isArray(params.status) ? params.status : [params.status]).filter(Boolean)
      : undefined
  const merchantArr =
    params.merchant != null
      ? (Array.isArray(params.merchant) ? params.merchant : [params.merchant]).filter(Boolean)
      : undefined

  const page = params.page ? parseInt(params.page, 10) : 1
  const limit = params.limit ? parseInt(params.limit, 10) : 20
  const priceMin =
    params.price_min != null && params.price_min !== '' ? parseFloat(params.price_min) : undefined
  const priceMax =
    params.price_max != null && params.price_max !== '' ? parseFloat(params.price_max) : undefined

  const sortRaw = params.sort ?? 'created_desc'
  const sort =
    sortRaw === 'created_desc' ||
    sortRaw === 'created_asc' ||
    sortRaw === 'price_desc' ||
    sortRaw === 'price_asc'
      ? sortRaw
      : 'created_desc'

  const payload = await getDealsList({
    q: params.q,
    statusTokens,
    merchantIds: merchantArr,
    dateFrom: params.date_from,
    dateTo: params.date_to,
    priceMin: Number.isFinite(priceMin) ? priceMin : undefined,
    priceMax: Number.isFinite(priceMax) ? priceMax : undefined,
    sort,
    page: Number.isFinite(page) ? page : 1,
    limit: Number.isFinite(limit) ? limit : 20,
  })

  return (
    <DealsPageClient
      deals={payload.deals}
      totalCount={payload.totalCount}
      merchantsForFilter={payload.merchantsForFilter}
      fetchError={payload.fetchError}
      initialSearchQ={params.q ?? ''}
      initialStatusTokens={statusTokens ?? []}
      initialMerchantIds={merchantArr ?? []}
      initialDateFrom={params.date_from}
      initialDateTo={params.date_to}
      initialPriceMin={params.price_min}
      initialPriceMax={params.price_max}
      initialSort={sort}
      initialPage={Number.isFinite(page) ? page : 1}
      initialLimit={Number.isFinite(limit) ? limit : 20}
    />
  )
}
