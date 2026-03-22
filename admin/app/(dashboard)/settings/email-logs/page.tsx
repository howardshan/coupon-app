import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import EmailLogsTable from '@/components/email-logs-table'

const PAGE_SIZE = 25

export default async function EmailLogsPage({
  searchParams,
}: {
  searchParams: Promise<{ page?: string }>
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
  const from = (page - 1) * PAGE_SIZE
  const to = from + PAGE_SIZE - 1

  const { data: rows, count, error } = await supabase
    .from('email_logs')
    .select(
      'id, recipient_email, recipient_type, email_code, reference_id, subject, status, smtp2go_message_id, error_message, sent_at, created_at',
      { count: 'exact' }
    )
    .order('created_at', { ascending: false })
    .range(from, to)

  if (error) {
    return (
      <div className="bg-red-50 border border-red-200 rounded-xl p-6 text-red-800 text-sm">
        Failed to load email logs: {error.message}
      </div>
    )
  }

  const totalCount = count ?? 0
  const totalPages = Math.max(1, Math.ceil(totalCount / PAGE_SIZE))

  return (
    <div>
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-gray-900">Email Log</h1>
        <p className="text-sm text-gray-500 mt-1">
          Sent email history from Edge Functions and Admin actions. Open a row to preview stored HTML.
        </p>
      </div>

      <EmailLogsTable
        rows={rows ?? []}
        page={page}
        totalPages={totalPages}
        totalCount={totalCount}
      />
    </div>
  )
}
