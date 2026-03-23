import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import { Suspense } from 'react'
import EmailLogsTable from '@/components/email-logs-table'
import EmailLogsFilters from '@/components/email-logs-filters'

const PAGE_SIZE = 25

export default async function EmailLogsPage({
  searchParams,
}: {
  searchParams: Promise<{
    page?:   string
    status?: string
    type?:   string
    code?:   string
    email?:  string
    from?:   string
    to?:     string
  }>
}) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const { data: profile } = await supabase
    .from('users')
    .select('role')
    .eq('id', user.id)
    .single()

  if (profile?.role !== 'admin') redirect('/dashboard')

  const params = await searchParams
  const page = Math.max(1, parseInt(params.page ?? '1', 10) || 1)
  const rangeFrom = (page - 1) * PAGE_SIZE
  const rangeTo   = rangeFrom + PAGE_SIZE - 1

  // 构建带筛选条件的查询
  let query = supabase
    .from('email_logs')
    .select(
      'id, recipient_email, recipient_type, email_code, reference_id, subject, status, smtp2go_message_id, error_message, sent_at, created_at',
      { count: 'exact' }
    )
    .order('created_at', { ascending: false })

  if (params.status && params.status !== 'all') {
    query = query.eq('status', params.status)
  }
  if (params.type && params.type !== 'all') {
    query = query.eq('recipient_type', params.type)
  }
  if (params.code) {
    query = query.eq('email_code', params.code.toUpperCase())
  }
  if (params.email) {
    query = query.ilike('recipient_email', `%${params.email}%`)
  }
  if (params.from) {
    query = query.gte('created_at', `${params.from}T00:00:00.000Z`)
  }
  if (params.to) {
    query = query.lte('created_at', `${params.to}T23:59:59.999Z`)
  }

  const { data: rows, count, error } = await query.range(rangeFrom, rangeTo)

  if (error) {
    return (
      <div className="bg-red-50 border border-red-200 rounded-xl p-6 text-red-800 text-sm">
        Failed to load email logs: {error.message}
      </div>
    )
  }

  const totalCount = count ?? 0
  const totalPages = Math.max(1, Math.ceil(totalCount / PAGE_SIZE))

  // 是否存在活跃筛选条件
  const isFiltered = !!(
    (params.status && params.status !== 'all') ||
    (params.type   && params.type   !== 'all') ||
    params.code || params.email || params.from || params.to
  )

  return (
    <div>
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-gray-900">Email Log</h1>
        <p className="text-sm text-gray-500 mt-1">
          Sent email history from Edge Functions and Admin actions. Open a row to preview stored HTML.
        </p>
      </div>

      {/* 筛选栏（useSearchParams 需要 Suspense 包裹） */}
      <Suspense>
        <EmailLogsFilters />
      </Suspense>

      <EmailLogsTable
        rows={rows ?? []}
        page={page}
        totalPages={totalPages}
        totalCount={totalCount}
        isFiltered={isFiltered}
      />
    </div>
  )
}
