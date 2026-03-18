import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getServiceRoleClient } from '@/lib/supabase/service'
import AfterSalesPageClient from '@/components/after-sales-page-client'

export const dynamic = 'force-dynamic'

type SearchParams = {
  status?: string
  page?: string
  per_page?: string
}

type AfterSalesRow = {
  id: string
  status: string
  reason_code: string
  reason_detail: string
  refund_amount: number | string | null
  store_name: string | null
  user_name: string | null
  created_at: string
  expires_at: string | null
}

function maskName(name: string | null) {
  if (!name) return 'User'
  if (name.length === 1) return `${name}*`
  return `${name[0]}***${name[name.length - 1]}`
}

async function fetchAfterSalesList(params: { status: string; page: number; perPage: number }) {
  const adminDb = getServiceRoleClient()
  const offset = (params.page - 1) * params.perPage
  let query = adminDb
    .from('view_merchant_after_sales_requests')
    .select('id, status, reason_code, reason_detail, refund_amount, store_name, user_name, created_at, expires_at', { count: 'exact' })
    .order('created_at', { ascending: false })
    .range(offset, offset + params.perPage - 1)

  if (params.status) {
    const statuses = params.status.split(',').map((s) => s.trim()).filter(Boolean)
    if (statuses.length) {
      query = query.in('status', statuses)
    }
  }

  const { data, error, count } = await query
  if (error) {
    return { rows: [], total: 0, error: error.message }
  }
  const mapped = (data ?? []).map((row: AfterSalesRow) => ({
    id: row.id,
    status: row.status,
    reasonCode: row.reason_code,
    reasonDetail: row.reason_detail,
    refundAmount: typeof row.refund_amount === 'number' ? row.refund_amount : Number(row.refund_amount ?? 0),
    storeName: row.store_name,
    userMasked: maskName(row.user_name),
    createdAt: row.created_at,
    expiresAt: row.expires_at,
  }))
  return { rows: mapped, total: count ?? 0, error: null as string | null }
}

export default async function AfterSalesPage({ searchParams }: { searchParams: Promise<SearchParams> }) {
  const params = await searchParams
  const supabase = await createClient()
  const { data: { session } } = await supabase.auth.getSession()
  if (!session) redirect('/login')
  const { data: profile } = await supabase
    .from('users')
    .select('role')
    .eq('id', session.user.id)
    .single()
  if (!profile || (profile.role !== 'admin' && profile.role !== 'super_admin')) {
    redirect('/dashboard')
  }

  const page = Math.max(1, Number.parseInt(params.page ?? '1', 10) || 1)
  const perPage = Math.min(50, Math.max(10, Number.parseInt(params.per_page ?? '20', 10) || 20))
  const status = params.status ?? 'awaiting_platform'

  const { rows, total, error } = await fetchAfterSalesList({ status, page, perPage })

  return (
    <AfterSalesPageClient
      requests={rows}
      total={total}
      page={page}
      perPage={perPage}
      statusFilter={status}
      fetchError={error}
    />
  )
}
