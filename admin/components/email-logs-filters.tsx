'use client'

import { useRouter, useSearchParams } from 'next/navigation'

// 已实现的邮件编码完整列表
const EMAIL_CODES = [
  'C1','C2','C3','C4','C5','C6','C7','C8','C9','C10','C11','C12','C13','C14',
  'M1','M2','M3','M4','M5','M6','M7','M8','M9','M10','M11','M12','M13','M14','M15','M16','M17',
  'A2','A3','A4','A5','A6','A7',
]

export default function EmailLogsFilters() {
  const router = useRouter()
  const sp = useSearchParams()

  const current = {
    status: sp.get('status') ?? 'all',
    type:   sp.get('type')   ?? 'all',
    code:   sp.get('code')   ?? '',
    email:  sp.get('email')  ?? '',
    from:   sp.get('from')   ?? '',
    to:     sp.get('to')     ?? '',
  }

  const hasFilters = ['status', 'type', 'code', 'email', 'from', 'to'].some(k => sp.has(k))

  function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault()
    const fd = new FormData(e.currentTarget)
    const params = new URLSearchParams()

    const status = fd.get('status') as string
    const type   = fd.get('type')   as string
    const code   = ((fd.get('code')  as string) ?? '').trim()
    const email  = ((fd.get('email') as string) ?? '').trim()
    const from   = fd.get('from')   as string
    const to     = fd.get('to')     as string

    if (status && status !== 'all') params.set('status', status)
    if (type   && type   !== 'all') params.set('type',   type)
    if (code)  params.set('code',  code.toUpperCase())
    if (email) params.set('email', email)
    if (from)  params.set('from',  from)
    if (to)    params.set('to',    to)

    const qs = params.size > 0 ? `?${params.toString()}` : ''
    router.push(`/settings/email-logs${qs}`)
  }

  return (
    <form
      onSubmit={handleSubmit}
      className="bg-white rounded-xl border border-gray-200 p-4 mb-4"
    >
      <div className="flex flex-wrap gap-3 items-end">

        {/* Status */}
        <div className="flex flex-col gap-1">
          <label className="text-xs font-medium text-gray-500 uppercase tracking-wide">
            Status
          </label>
          <select
            name="status"
            defaultValue={current.status}
            className="text-sm border border-gray-200 rounded-lg px-3 py-1.5 bg-white focus:outline-none focus:ring-2 focus:ring-blue-500 min-w-[110px]"
          >
            <option value="all">All statuses</option>
            <option value="sent">Sent</option>
            <option value="failed">Failed</option>
            <option value="pending">Pending</option>
            <option value="bounced">Bounced</option>
          </select>
        </div>

        {/* Recipient type */}
        <div className="flex flex-col gap-1">
          <label className="text-xs font-medium text-gray-500 uppercase tracking-wide">
            Recipient type
          </label>
          <select
            name="type"
            defaultValue={current.type}
            className="text-sm border border-gray-200 rounded-lg px-3 py-1.5 bg-white focus:outline-none focus:ring-2 focus:ring-blue-500 min-w-[120px]"
          >
            <option value="all">All types</option>
            <option value="customer">Customer</option>
            <option value="merchant">Merchant</option>
            <option value="admin">Admin</option>
          </select>
        </div>

        {/* Email code */}
        <div className="flex flex-col gap-1">
          <label className="text-xs font-medium text-gray-500 uppercase tracking-wide">
            Email code
          </label>
          <select
            name="code"
            defaultValue={current.code}
            className="text-sm border border-gray-200 rounded-lg px-3 py-1.5 bg-white focus:outline-none focus:ring-2 focus:ring-blue-500 min-w-[100px]"
          >
            <option value="">All codes</option>
            {EMAIL_CODES.map(c => (
              <option key={c} value={c}>{c}</option>
            ))}
          </select>
        </div>

        {/* Recipient email */}
        <div className="flex flex-col gap-1 flex-1 min-w-[180px]">
          <label className="text-xs font-medium text-gray-500 uppercase tracking-wide">
            Recipient email
          </label>
          <input
            type="text"
            name="email"
            defaultValue={current.email}
            placeholder="Search by email…"
            className="text-sm border border-gray-200 rounded-lg px-3 py-1.5 focus:outline-none focus:ring-2 focus:ring-blue-500"
          />
        </div>

        {/* Date from */}
        <div className="flex flex-col gap-1">
          <label className="text-xs font-medium text-gray-500 uppercase tracking-wide">
            From
          </label>
          <input
            type="date"
            name="from"
            defaultValue={current.from}
            className="text-sm border border-gray-200 rounded-lg px-3 py-1.5 focus:outline-none focus:ring-2 focus:ring-blue-500"
          />
        </div>

        {/* Date to */}
        <div className="flex flex-col gap-1">
          <label className="text-xs font-medium text-gray-500 uppercase tracking-wide">
            To
          </label>
          <input
            type="date"
            name="to"
            defaultValue={current.to}
            className="text-sm border border-gray-200 rounded-lg px-3 py-1.5 focus:outline-none focus:ring-2 focus:ring-blue-500"
          />
        </div>

        {/* Actions */}
        <div className="flex gap-2 items-end pb-px">
          <button
            type="submit"
            className="px-4 py-1.5 bg-blue-600 text-white text-sm font-medium rounded-lg hover:bg-blue-700 transition-colors"
          >
            Search
          </button>
          {hasFilters && (
            <button
              type="button"
              onClick={() => router.push('/settings/email-logs')}
              className="px-3 py-1.5 text-sm text-gray-600 border border-gray-200 rounded-lg hover:bg-gray-50 transition-colors"
            >
              Clear
            </button>
          )}
        </div>

      </div>

      {/* 当前活跃筛选条件标签 */}
      {hasFilters && (
        <div className="mt-3 flex flex-wrap gap-2">
          {current.status !== 'all' && (
            <ActiveTag label="Status" value={current.status} />
          )}
          {current.type !== 'all' && (
            <ActiveTag label="Type" value={current.type} />
          )}
          {current.code && (
            <ActiveTag label="Code" value={current.code} />
          )}
          {current.email && (
            <ActiveTag label="Email" value={current.email} />
          )}
          {current.from && (
            <ActiveTag label="From" value={current.from} />
          )}
          {current.to && (
            <ActiveTag label="To" value={current.to} />
          )}
        </div>
      )}
    </form>
  )
}

function ActiveTag({ label, value }: { label: string; value: string }) {
  return (
    <span className="inline-flex items-center gap-1 px-2 py-0.5 bg-blue-50 text-blue-700 text-xs rounded-full border border-blue-200">
      <span className="font-medium">{label}:</span>
      <span>{value}</span>
    </span>
  )
}
