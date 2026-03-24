'use client'

import { useRouter, useSearchParams } from 'next/navigation'
import { useState, useRef, useEffect } from 'react'

// 邮件编码 + 可读名称完整列表
const EMAIL_CODE_OPTIONS: { code: string; name: string }[] = [
  { code: 'C1',  name: 'Welcome Email' },
  { code: 'C2',  name: 'Order Confirmation' },
  { code: 'C3',  name: 'Coupon Redeemed' },
  { code: 'C4',  name: 'Coupon Expiring Soon' },
  { code: 'C5',  name: 'Auto Refund (Expired)' },
  { code: 'C6',  name: 'Store Credit Added' },
  { code: 'C7',  name: 'Refund Request Received' },
  { code: 'C8',  name: 'Stripe Refund Completed' },
  { code: 'C9',  name: 'After-sales Submitted' },
  { code: 'C10', name: 'After-sales Approved' },
  { code: 'C11', name: 'After-sales Rejected' },
  { code: 'C12', name: 'Password Reset' },
  { code: 'C13', name: 'Merchant Replied' },
  { code: 'C14', name: 'Admin Refund Rejected' },
  { code: 'M1',  name: 'Merchant Welcome' },
  { code: 'M2',  name: 'Verification Pending' },
  { code: 'M3',  name: 'Verification Approved' },
  { code: 'M4',  name: 'Verification Rejected' },
  { code: 'M5',  name: 'New Order' },
  { code: 'M6',  name: 'Deal Expiring Soon' },
  { code: 'M7',  name: 'Coupon Redeemed (Merchant)' },
  { code: 'M8',  name: 'Pre-redemption Refund' },
  { code: 'M9',  name: 'After-sales Received' },
  { code: 'M10', name: 'After-sales Approved (Merchant)' },
  { code: 'M11', name: 'After-sales Escalated' },
  { code: 'M12', name: 'Platform Decision' },
  { code: 'M13', name: 'Monthly Settlement' },
  { code: 'M14', name: 'Withdrawal Received' },
  { code: 'M15', name: 'Withdrawal Completed' },
  { code: 'M16', name: 'Deal Rejected' },
  { code: 'M17', name: 'Deal Approved' },
  { code: 'A2',  name: 'New Merchant Application' },
  { code: 'A3',  name: 'Daily Digest' },
  { code: 'A4',  name: 'Large Refund Alert' },
  { code: 'A5',  name: 'After-sales Escalated (Admin)' },
  { code: 'A6',  name: 'After-sales Closed' },
  { code: 'A7',  name: 'Withdrawal Request' },
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

        {/* Email code — 自定义下拉，固定高度可滚动 */}
        <div className="flex flex-col gap-1">
          <label className="text-xs font-medium text-gray-500 uppercase tracking-wide">
            Email code
          </label>
          <CodeSelect name="code" defaultValue={current.code} />
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
            <ActiveTag
              label="Code"
              value={(() => {
                const opt = EMAIL_CODE_OPTIONS.find(o => o.code === current.code)
                return opt ? `${opt.code} — ${opt.name}` : current.code
              })()}
            />
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

// 自定义邮件编码下拉组件：固定高度、可滚动、显示 code + 名称
function CodeSelect({ name, defaultValue }: { name: string; defaultValue: string }) {
  const [open, setOpen]     = useState(false)
  const [value, setValue]   = useState(defaultValue)
  const containerRef        = useRef<HTMLDivElement>(null)

  const selected = EMAIL_CODE_OPTIONS.find(o => o.code === value)
  const label    = selected ? `${selected.code} — ${selected.name}` : 'All codes'

  // 点击组件外部时关闭
  useEffect(() => {
    function handleClickOutside(e: MouseEvent) {
      if (containerRef.current && !containerRef.current.contains(e.target as Node)) {
        setOpen(false)
      }
    }
    if (open) document.addEventListener('mousedown', handleClickOutside)
    return () => document.removeEventListener('mousedown', handleClickOutside)
  }, [open])

  return (
    <div ref={containerRef} className="relative">
      {/* 隐藏 input 供 form 读取 */}
      <input type="hidden" name={name} value={value} />

      {/* 触发按钮 */}
      <button
        type="button"
        onClick={() => setOpen(v => !v)}
        className={`flex items-center justify-between gap-2 text-sm border rounded-lg px-3 py-1.5 bg-white w-[220px] focus:outline-none focus:ring-2 focus:ring-blue-500 transition-colors ${
          open ? 'border-blue-500 ring-2 ring-blue-500' : 'border-gray-200 hover:border-gray-300'
        }`}
      >
        <span className={`truncate ${value ? 'text-gray-900 font-mono' : 'text-gray-500'}`}>
          {label}
        </span>
        <svg
          className={`shrink-0 w-4 h-4 text-gray-400 transition-transform ${open ? 'rotate-180' : ''}`}
          fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}
        >
          <path strokeLinecap="round" strokeLinejoin="round" d="M19 9l-7 7-7-7" />
        </svg>
      </button>

      {/* 下拉列表：固定最大高度，内部滚动 */}
      {open && (
        <div className="absolute z-20 mt-1 w-[260px] bg-white border border-gray-200 rounded-lg shadow-lg overflow-hidden">
          <div className="max-h-52 overflow-y-auto">
            {/* All codes 选项 */}
            <button
              type="button"
              onClick={() => { setValue(''); setOpen(false) }}
              className={`w-full text-left px-3 py-2 text-sm hover:bg-blue-50 transition-colors ${
                value === '' ? 'bg-blue-50 text-blue-700 font-medium' : 'text-gray-700'
              }`}
            >
              All codes
            </button>

            {/* 分隔线 */}
            <div className="h-px bg-gray-100 mx-2" />

            {EMAIL_CODE_OPTIONS.map(opt => (
              <button
                key={opt.code}
                type="button"
                onClick={() => { setValue(opt.code); setOpen(false) }}
                className={`w-full text-left px-3 py-2 text-sm hover:bg-blue-50 transition-colors flex items-baseline gap-2 ${
                  value === opt.code ? 'bg-blue-50 text-blue-700' : 'text-gray-700'
                }`}
              >
                <span className="font-mono font-medium w-8 shrink-0">{opt.code}</span>
                <span className="text-gray-500 text-xs truncate">{opt.name}</span>
              </button>
            ))}
          </div>
        </div>
      )}
    </div>
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
