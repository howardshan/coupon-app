'use client'

import { useState } from 'react'
import Link from 'next/link'
import { useSearchParams } from 'next/navigation'
import { getEmailLogHtmlBody } from '@/app/actions/email-logs'

export type EmailLogListRow = {
  id: string
  recipient_email: string
  recipient_type: string
  email_code: string
  reference_id: string | null
  subject: string
  status: string
  smtp2go_message_id: string | null
  error_message: string | null
  sent_at: string | null
  created_at: string
}

function statusBadgeClass(status: string) {
  switch (status) {
    case 'sent':
      return 'bg-green-100 text-green-800'
    case 'failed':
    case 'bounced':
      return 'bg-red-100 text-red-800'
    case 'pending':
      return 'bg-amber-100 text-amber-800'
    default:
      return 'bg-gray-100 text-gray-700'
  }
}

function formatDt(iso: string | null) {
  if (!iso) return '—'
  try {
    return new Date(iso).toLocaleString('en-US', {
      dateStyle: 'medium',
      timeStyle: 'short',
    })
  } catch {
    return iso
  }
}

/** 计算要展示的页码列表（含省略号） */
function buildPageNumbers(current: number, total: number): (number | '...')[] {
  if (total <= 7) return Array.from({ length: total }, (_, i) => i + 1)

  const pages: (number | '...')[] = [1]

  if (current > 3) pages.push('...')

  const start = Math.max(2, current - 1)
  const end   = Math.min(total - 1, current + 1)
  for (let i = start; i <= end; i++) pages.push(i)

  if (current < total - 2) pages.push('...')

  pages.push(total)
  return pages
}

/** 弹窗内展示：列表行元数据 + 拉取后的 HTML */
type EmailPreviewState = {
  html: string
  created_at: string
  sent_at: string | null
  email_code: string
  recipient_email: string
  recipient_type: string
  status: string
  subject: string
}

export default function EmailLogsTable({
  rows,
  page,
  totalPages,
  totalCount,
  isFiltered,
}: {
  rows: EmailLogListRow[]
  page: number
  totalPages: number
  totalCount: number
  isFiltered: boolean
}) {
  const [preview, setPreview] = useState<EmailPreviewState | null>(null)
  // 仅当前点击行显示 Loading，避免 useTransition 全局 isPending 牵连所有按钮
  const [previewLoadingId, setPreviewLoadingId] = useState<string | null>(null)

  // 用于构建保留筛选参数的分页链接
  const sp = useSearchParams()

  function buildPageUrl(newPage: number) {
    const params = new URLSearchParams(sp.toString())
    if (newPage === 1) {
      params.delete('page')
    } else {
      params.set('page', String(newPage))
    }
    const qs = params.size > 0 ? `?${params.toString()}` : ''
    return `/settings/email-logs${qs}`
  }

  async function openPreview(row: EmailLogListRow) {
    const { id } = row
    setPreviewLoadingId(id)
    try {
      const res = await getEmailLogHtmlBody(id)
      if ('error' in res && res.error === 'Forbidden') {
        alert('Access denied.')
        return
      }
      if ('error' in res) {
        alert(res.error)
        return
      }
      setPreview({
        html:            res.htmlBody,
        created_at:      row.created_at,
        sent_at:         row.sent_at,
        email_code:      row.email_code,
        recipient_email: row.recipient_email,
        recipient_type:  row.recipient_type,
        status:          row.status,
        subject:         row.subject,
      })
    } finally {
      // 避免并发点击时先完成的请求把后发起的 loading 清掉
      setPreviewLoadingId(cur => (cur === id ? null : cur))
    }
  }

  const pageNumbers = buildPageNumbers(page, totalPages)
  const rangeStart  = totalCount === 0 ? 0 : (page - 1) * 25 + 1
  const rangeEnd    = Math.min(page * 25, totalCount)

  return (
    <>
      <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
        <div className="px-5 py-3 border-b border-gray-100 flex justify-between items-center">
          <p className="text-sm text-gray-500">
            {totalCount === 0 ? (
              'No records found'
            ) : (
              <>
                Showing{' '}
                <span className="font-semibold text-gray-900">
                  {rangeStart}–{rangeEnd}
                </span>{' '}
                of{' '}
                <span className="font-semibold text-gray-900">{totalCount}</span>{' '}
                {isFiltered ? 'filtered records' : 'records'}
              </>
            )}
          </p>
        </div>
        <div className="overflow-x-auto">
          <table className="min-w-full text-sm">
            <thead>
              <tr className="bg-gray-50 text-left text-xs font-medium text-gray-500 uppercase tracking-wide">
                <th className="px-4 py-3">Created</th>
                <th className="px-4 py-3">Code</th>
                <th className="px-4 py-3">Recipient</th>
                <th className="px-4 py-3">Type</th>
                <th className="px-4 py-3">Status</th>
                <th className="px-4 py-3">Subject</th>
                <th className="px-4 py-3 w-28">Preview</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {rows.length === 0 ? (
                <tr>
                  <td colSpan={7} className="px-4 py-12 text-center text-gray-400">
                    {isFiltered
                      ? 'No records match the current filters.'
                      : 'No email logs yet. Sent mail will appear here.'}
                  </td>
                </tr>
              ) : (
                rows.map(row => (
                  <tr key={row.id} className="hover:bg-gray-50/80">
                    <td className="px-4 py-3 whitespace-nowrap text-gray-600">
                      {formatDt(row.created_at)}
                    </td>
                    <td className="px-4 py-3 font-mono text-gray-900">{row.email_code}</td>
                    <td
                      className="px-4 py-3 text-gray-700 max-w-[200px] truncate"
                      title={row.recipient_email}
                    >
                      {row.recipient_email}
                    </td>
                    <td className="px-4 py-3 capitalize text-gray-600">{row.recipient_type}</td>
                    <td className="px-4 py-3">
                      <span
                        className={`inline-flex px-2 py-0.5 rounded text-xs font-medium ${statusBadgeClass(row.status)}`}
                      >
                        {row.status}
                      </span>
                    </td>
                    <td
                      className="px-4 py-3 text-gray-700 max-w-xs truncate"
                      title={row.subject}
                    >
                      {row.subject}
                    </td>
                    <td className="px-4 py-3">
                      <button
                        type="button"
                        onClick={() => openPreview(row)}
                        disabled={previewLoadingId === row.id}
                        className="text-blue-600 hover:text-blue-800 text-xs font-medium disabled:opacity-50"
                      >
                        {previewLoadingId === row.id ? 'Loading…' : 'View HTML'}
                      </button>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>

        {/* 分页 */}
        {totalPages > 1 && (
          <div className="px-5 py-3 border-t border-gray-100 flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2 text-sm">
            <span className="text-gray-500">
              Page {page} of {totalPages}
            </span>
            <div className="flex items-center gap-1">
              {/* Previous */}
              {page > 1 ? (
                <Link
                  href={buildPageUrl(page - 1)}
                  className="px-3 py-1 rounded-lg border border-gray-200 hover:bg-gray-50 text-gray-700"
                >
                  ←
                </Link>
              ) : (
                <span className="px-3 py-1 rounded-lg border border-gray-100 text-gray-300 cursor-default">←</span>
              )}

              {/* 页码 */}
              {pageNumbers.map((n, idx) =>
                n === '...' ? (
                  <span key={`ellipsis-${idx}`} className="px-2 py-1 text-gray-400">…</span>
                ) : (
                  <Link
                    key={n}
                    href={buildPageUrl(n)}
                    className={`px-3 py-1 rounded-lg border text-sm transition-colors ${
                      n === page
                        ? 'bg-blue-600 text-white border-blue-600 font-medium'
                        : 'border-gray-200 hover:bg-gray-50 text-gray-700'
                    }`}
                  >
                    {n}
                  </Link>
                )
              )}

              {/* Next */}
              {page < totalPages ? (
                <Link
                  href={buildPageUrl(page + 1)}
                  className="px-3 py-1 rounded-lg border border-gray-200 hover:bg-gray-50 text-gray-700"
                >
                  →
                </Link>
              ) : (
                <span className="px-3 py-1 rounded-lg border border-gray-100 text-gray-300 cursor-default">→</span>
              )}
            </div>
          </div>
        )}
      </div>

      {/* 邮件 HTML 预览弹窗 */}
      {preview && (
        <div
          className="fixed inset-0 z-50 flex items-start sm:items-center justify-center bg-black/50 p-4 sm:p-6 overflow-y-auto"
          role="dialog"
          aria-modal="true"
          aria-labelledby="email-preview-title"
        >
          <div className="bg-white rounded-xl shadow-xl w-full max-w-2xl sm:max-w-3xl min-w-0 max-h-[min(90dvh,56rem)] my-auto flex flex-col overflow-hidden">
            <div className="shrink-0 px-5 py-4 border-b border-gray-200 flex justify-between items-start gap-4">
              <div className="min-w-0 pr-2">
                <h2 id="email-preview-title" className="text-lg font-semibold text-gray-900">
                  Email preview
                </h2>
                <p className="text-xs text-gray-400 mt-1">Same fields as the log list, plus rendered HTML below.</p>
              </div>
              <button
                type="button"
                onClick={() => setPreview(null)}
                className="shrink-0 text-gray-400 hover:text-gray-700 text-xl leading-none px-2"
                aria-label="Close"
              >
                ×
              </button>
            </div>
            {/* 元数据区 */}
            <div className="shrink-0 px-5 py-3 border-b border-gray-100 bg-gray-50/80">
              <dl className="grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-2 text-sm">
                <div>
                  <dt className="text-xs font-medium text-gray-500 uppercase tracking-wide">Created</dt>
                  <dd className="mt-0.5 text-gray-900 tabular-nums">{formatDt(preview.created_at)}</dd>
                </div>
                <div>
                  <dt className="text-xs font-medium text-gray-500 uppercase tracking-wide">Sent</dt>
                  <dd className="mt-0.5 text-gray-900 tabular-nums">{formatDt(preview.sent_at)}</dd>
                </div>
                <div>
                  <dt className="text-xs font-medium text-gray-500 uppercase tracking-wide">Code</dt>
                  <dd className="mt-0.5 font-mono text-gray-900">{preview.email_code}</dd>
                </div>
                <div>
                  <dt className="text-xs font-medium text-gray-500 uppercase tracking-wide">Type</dt>
                  <dd className="mt-0.5 capitalize text-gray-900">{preview.recipient_type}</dd>
                </div>
                <div className="sm:col-span-2">
                  <dt className="text-xs font-medium text-gray-500 uppercase tracking-wide">Recipient</dt>
                  <dd className="mt-0.5 text-gray-900 break-all">{preview.recipient_email}</dd>
                </div>
                <div>
                  <dt className="text-xs font-medium text-gray-500 uppercase tracking-wide">Status</dt>
                  <dd className="mt-0.5">
                    <span className={`inline-flex px-2 py-0.5 rounded text-xs font-medium ${statusBadgeClass(preview.status)}`}>
                      {preview.status}
                    </span>
                  </dd>
                </div>
                <div className="sm:col-span-2">
                  <dt className="text-xs font-medium text-gray-500 uppercase tracking-wide">Subject</dt>
                  <dd className="mt-0.5 text-gray-900 break-words">{preview.subject}</dd>
                </div>
              </dl>
            </div>
            {/* HTML 预览 */}
            <div className="flex-1 min-h-0 p-4">
              {preview.html ? (
                <iframe
                  title="Email HTML preview"
                  className="w-full min-h-[min(45dvh,280px)] h-[min(70dvh,calc(90dvh_-_18rem))] border border-gray-200 rounded-lg bg-white"
                  sandbox="allow-same-origin"
                  srcDoc={preview.html}
                />
              ) : (
                <p className="text-gray-400 text-sm">No HTML body stored for this log.</p>
              )}
            </div>
          </div>
        </div>
      )}
    </>
  )
}
