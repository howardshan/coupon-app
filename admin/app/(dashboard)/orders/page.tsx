import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import OrdersPageClient from '@/components/orders-page-client'
import { OrdersSearchProvider } from '@/contexts/orders-search-context'
import { getOrdersList } from '@/app/actions/orders'

export const dynamic = 'force-dynamic'

type SearchParams = {
  q?: string
  status?: string | string[]
  merchant?: string
  customer?: string
  date_from?: string
  date_to?: string
  amount_min?: string
  amount_max?: string
  sort?: string
  page?: string
  limit?: string
}

export default async function OrdersPage({
  searchParams,
}: {
  searchParams: Promise<SearchParams>
}) {
  const params = await searchParams
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  const { data: profile } = await supabase
    .from('users')
    .select('role')
    .eq('id', user!.id)
    .single()

  if (profile?.role !== 'admin') redirect('/dashboard')

  const statusArr = params.status != null
    ? (Array.isArray(params.status) ? params.status : [params.status]).filter(Boolean)
    : undefined
  const page = params.page ? parseInt(params.page, 10) : 1
  const limit = params.limit ? parseInt(params.limit, 10) : 20
  const amountMin = params.amount_min != null && params.amount_min !== '' ? parseFloat(params.amount_min) : undefined
  const amountMax = params.amount_max != null && params.amount_max !== '' ? parseFloat(params.amount_max) : undefined

  const payload = await getOrdersList({
    q: params.q,
    status: statusArr,
    merchantId: params.merchant,
    customerId: params.customer,
    dateFrom: params.date_from,
    dateTo: params.date_to,
    amountMin: Number.isFinite(amountMin) ? amountMin : undefined,
    amountMax: Number.isFinite(amountMax) ? amountMax : undefined,
    sort: params.sort as 'date_desc' | 'date_asc' | 'amount_desc' | 'amount_asc' | undefined,
    page: Number.isFinite(page) ? page : 1,
    limit: Number.isFinite(limit) ? limit : 20,
  })

  return (
    <OrdersSearchProvider>
      <OrdersPageClient
        orders={payload.orders}
        totalCount={payload.totalCount}
        redeemedMerchantNames={payload.redeemedMerchantNames}
        fetchError={payload.fetchError}
        refundCount={payload.refundCount}
        merchantsForFilter={payload.merchantsForFilter}
        customersForFilter={payload.customersForFilter}
        initialSearchQ={params.q ?? ''}
        initialStatus={statusArr}
        initialMerchantId={params.merchant}
        initialCustomerId={params.customer}
        initialDateFrom={params.date_from}
        initialDateTo={params.date_to}
        initialAmountMin={params.amount_min}
        initialAmountMax={params.amount_max}
        initialSort={params.sort ?? 'date_desc'}
        initialPage={Number.isFinite(page) ? page : 1}
        initialLimit={Number.isFinite(limit) ? limit : 20}
      />
    </OrdersSearchProvider>
  )
}
