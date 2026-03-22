'use client'

import { useState, useTransition } from 'react'
import Link from 'next/link'
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

export default function EmailLogsTable({
  rows,
  page,
  totalPages,
  totalCount,
}: {
  rows: EmailLogListRow[]
  page: number
  totalPages: number
  totalCount: number
}) {
  const [preview, setPreview] = useState<{ subject: string; html: string } | null>(null)
  const [pending, startTransition] = useTransition()

  function openPreview(id: string) {
    startTransition(async () => {
      const res = await getEmailLogHtmlBody(id)
      if ('error' in res && res.error === 'Forbidden') {
        alert('Access denied.')
        return
      }
      if ('error' in res) {
        alert(res.error)
        return
      }
      setPreview({ subject: res.subject, html: res.htmlBody })
    })
  }

  return (
    <>
      <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
        <div className="px-5 py-3 border-b border-gray-100 flex justify-between items-center">
          <p className="text-sm text-gray-500">
            Total <span className="font-semibold text-gray-900">{totalCount}</span> records
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
                    No email logs yet. Sent mail will appear here.
                  </td>
                </tr>
              ) : (
                rows.map(row => (
                  <tr key={row.id} className="hover:bg-gray-50/80">
                    <td className="px-4 py-3 whitespace-nowrap text-gray-600">
                      {formatDt(row.created_at)}
                    </td>
                    <td className="px-4 py-3 font-mono text-gray-900">{row.email_code}</td>
                    <td className="px-4 py-3 text-gray-700 max-w-[200px] truncate" title={row.recipient_email}>
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
                    <td className="px-4 py-3 text-gray-700 max-w-xs truncate" title={row.subject}>
                      {row.subject}
                    </td>
                    <td className="px-4 py-3">
                      <button
                        type="button"
                        onClick={() => openPreview(row.id)}
                        disabled={pending}
                        className="text-blue-600 hover:text-blue-800 text-xs font-medium disabled:opacity-50"
                      >
                        {pending ? 'Loading…' : 'View HTML'}
                      </button>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
        {totalPages > 1 && (
          <div className="px-5 py-3 border-t border-gray-100 flex items-center justify-between text-sm">
            <span className="text-gray-500">
              Page {page} of {totalPages}
            </span>
            <div className="flex gap-2">
              {page > 1 && (
                <Link
                  href={`/settings/email-logs?page=${page - 1}`}
                  className="px-3 py-1 rounded-lg border border-gray-200 hover:bg-gray-50"
                >
                  Previous
                </Link>
              )}
              {page < totalPages && (
                <Link
                  href={`/settings/email-logs?page=${page + 1}`}
                  className="px-3 py-1 rounded-lg border border-gray-200 hover:bg-gray-50"
                >
                  Next
                </Link>
              )}
            </div>
          </div>
        )}
      </div>

      {preview && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
          role="dialog"
          aria-modal="true"
          aria-labelledby="email-preview-title"
        >
          <div className="bg-white rounded-xl shadow-xl max-w-4xl w-full max-h-[90vh] flex flex-col">
            <div className="px-5 py-4 border-b border-gray-200 flex justify-between items-start gap-4">
              <div>
                <h2 id="email-preview-title" className="text-lg font-semibold text-gray-900">
                  Email preview
                </h2>
                <p className="text-sm text-gray-500 mt-1 break-all">{preview.subject}</p>
              </div>
              <button
                type="button"
                onClick={() => setPreview(null)}
                className="text-gray-400 hover:text-gray-700 text-xl leading-none px-2"
                aria-label="Close"
              >
                ×
              </button>
            </div>
            <div className="flex-1 min-h-0 p-4">
              {preview.html ? (
                <iframe
                  title="Email HTML preview"
                  className="w-full h-[min(70vh,600px)] border border-gray-200 rounded-lg bg-white"
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
