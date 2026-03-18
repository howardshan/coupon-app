'use client'

import { useCallback, useEffect, useMemo, useState } from 'react'
import { useRouter, useSearchParams } from 'next/navigation'

type AfterSalesListItem = {
  id: string
  status: string
  reasonCode: string
  reasonDetail: string
  refundAmount: number
  storeName: string | null
  userMasked: string
  createdAt: string
  expiresAt: string | null
}

type AfterSalesPageClientProps = {
  requests: AfterSalesListItem[]
  total: number
  page: number
  perPage: number
  statusFilter: string
  fetchError?: string | null
}

type AfterSalesDetail = {
  request: {
    id: string
    status: string
    reason_code?: string
    reason_detail?: string
    refund_amount?: number
    user_attachments?: string[]
    merchant_attachments?: string[]
    platform_attachments?: string[]
    timeline?: Array<{
      status: string
      actor: string
      note?: string
      attachments?: string[]
      at: string
    }>
  }
}

const STATUS_OPTIONS = [
  { label: 'Awaiting Platform', value: 'awaiting_platform' },
  { label: 'Merchant Reviewed', value: 'merchant_rejected,merchant_approved' },
  { label: 'Resolved', value: 'refunded,platform_rejected,closed' },
  { label: 'All', value: '' },
]

const STATUS_COLORS: Record<string, string> = {
  pending: 'bg-yellow-100 text-yellow-800',
  awaiting_platform: 'bg-blue-100 text-blue-800',
  merchant_rejected: 'bg-rose-100 text-rose-800',
  merchant_approved: 'bg-emerald-100 text-emerald-800',
  platform_rejected: 'bg-rose-100 text-rose-800',
  refunded: 'bg-emerald-100 text-emerald-800',
  closed: 'bg-gray-200 text-gray-700',
}

function formatStatus(status: string) {
  return status.replaceAll('_', ' ')
}

function formatSla(expiresAt: string | null, status: string) {
  if (!expiresAt) return '—'
  const expires = new Date(expiresAt)
  const diff = expires.getTime() - Date.now()
  if (diff <= 0) {
    return status === 'pending' || status === 'awaiting_platform' ? 'Expired' : 'Complete'
  }
  const days = Math.floor(diff / (24 * 3600 * 1000))
  const hours = Math.floor((diff % (24 * 3600 * 1000)) / (3600 * 1000))
  const minutes = Math.floor((diff % (3600 * 1000)) / (60 * 1000))
  if (days > 0) return `${days}d ${hours}h`
  if (hours > 0) return `${hours}h ${minutes}m`
  return `${minutes}m`
}

function buildUrl(params: URLSearchParams, updates: Record<string, string | undefined | number>) {
  const next = new URLSearchParams(params)
  Object.entries(updates).forEach(([key, value]) => {
    if (value === undefined || value === '') {
      next.delete(key)
    } else {
      next.set(key, String(value))
    }
  })
  return `/after-sales?${next.toString()}`
}

export default function AfterSalesPageClient({
  requests,
  total,
  page,
  perPage,
  statusFilter,
  fetchError,
}: AfterSalesPageClientProps) {
  const router = useRouter()
  const searchParams = useSearchParams()
  const [selected, setSelected] = useState<AfterSalesListItem | null>(null)
  const [detail, setDetail] = useState<AfterSalesDetail | null>(null)
  const [detailLoading, setDetailLoading] = useState(false)
  const [detailError, setDetailError] = useState<string | null>(null)
  const [actionMessage, setActionMessage] = useState<string | null>(null)
  const [decisionState, setDecisionState] = useState<null | { action: 'approve' | 'reject' }>(null)
  const [decisionNote, setDecisionNote] = useState('')
  const [decisionFiles, setDecisionFiles] = useState<File[]>([])
  const [actionLoading, setActionLoading] = useState(false)

  useEffect(() => {
    if (!selected) return
    setDetail(null)
    setDetailError(null)
    setDetailLoading(true)
    fetch(`/api/platform-after-sales/${selected.id}`)
      .then(async (res) => {
        if (!res.ok) {
          const body = await res.json().catch(() => ({}))
          throw new Error(body?.message ?? 'Failed to load detail')
        }
        return res.json()
      })
      .then((data) => {
        setDetail(data as AfterSalesDetail)
      })
      .catch((err) => {
        setDetailError(err.message)
      })
      .finally(() => setDetailLoading(false))
  }, [selected])

  const onChangeFilter = useCallback((value: string) => {
    const next = buildUrl(searchParams, { status: value || undefined, page: undefined })
    router.replace(next)
  }, [router, searchParams])

  const onChangePage = useCallback((nextPage: number) => {
    const next = buildUrl(searchParams, { page: nextPage })
    router.replace(next)
  }, [router, searchParams])

  const totalPages = Math.max(1, Math.ceil(total / perPage))

  async function uploadEvidence(files: File[]) {
    const limited = files.slice(0, 3)
    if (!limited.length) return []
    const slotRes = await fetch('/api/platform-after-sales/uploads', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ files: limited.map((file) => ({ filename: file.name })) }),
    })
    const slotPayload = await slotRes.json().catch(() => ({}))
    if (!slotRes.ok) {
      throw new Error(slotPayload?.message ?? 'Failed to request upload slots')
    }
    const uploads = Array.isArray(slotPayload?.uploads) ? slotPayload.uploads : []
    const uploaded: string[] = []
    for (let i = 0; i < uploads.length; i += 1) {
      const slot = uploads[i]
      const file = limited[i]
      const putRes = await fetch(slot.signedUrl, {
        method: 'PUT',
        headers: {
          'Content-Type': file?.type || 'application/octet-stream',
          Authorization: `Bearer ${slot.token}`,
          'x-upsert': 'false',
        },
        body: file,
      })
      if (!putRes.ok) {
        throw new Error('Failed to upload evidence')
      }
      uploaded.push(slot.path)
    }
    return uploaded
  }

  async function submitDecision(action: 'approve' | 'reject') {
    if (!selected) return
    setActionLoading(true)
    setActionMessage(null)
    try {
      let attachments: string[] = []
      if (action === 'reject') {
        attachments = await uploadEvidence(decisionFiles)
        if (!attachments.length) {
          throw new Error('At least one attachment is required for rejection')
        }
      }
      const response = await fetch(`/api/platform-after-sales/${selected.id}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          action,
          note: decisionNote,
          attachments,
        }),
      })
      if (!response.ok) {
        const body = await response.json().catch(() => ({}))
        throw new Error(body?.message ?? 'Failed to submit decision')
      }
      setActionMessage(action === 'approve' ? 'Request approved' : 'Request rejected')
      setDecisionState(null)
      setDecisionNote('')
      setDecisionFiles([])
      setSelected((prev) => (prev ? { ...prev, status: action === 'approve' ? 'refunded' : 'platform_rejected' } : prev))
      router.refresh()
    } catch (err) {
      setActionMessage((err as Error).message)
    } finally {
      setActionLoading(false)
    }
  }

  const closeDrawer = () => {
    setSelected(null)
    setDetail(null)
    setDetailError(null)
    setActionMessage(null)
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">After-Sales Queue</h1>
          <p className="text-sm text-gray-600">Track escalations and merchant disputes.</p>
        </div>
        <label className="text-sm text-gray-600">
          <span className="mr-2 font-medium">Status</span>
          <select
            value={statusFilter}
            onChange={(e) => onChangeFilter(e.target.value)}
            className="rounded-lg border border-gray-300 px-3 py-2"
          >
            {STATUS_OPTIONS.map((option) => (
              <option key={option.value} value={option.value}>{option.label}</option>
            ))}
          </select>
        </label>
      </div>

      {fetchError && (
        <div className="rounded-lg border border-rose-200 bg-rose-50 px-4 py-3 text-sm text-rose-700">
          Failed to load after-sales requests: {fetchError}
        </div>
      )}

      <div className="rounded-xl border border-gray-200 bg-white">
        <table className="w-full text-sm">
          <thead className="bg-gray-50 text-gray-600">
            <tr>
              <th className="px-4 py-3 text-left font-medium">Request</th>
              <th className="px-4 py-3 text-left font-medium">Store</th>
              <th className="px-4 py-3 text-left font-medium">User</th>
              <th className="px-4 py-3 text-left font-medium">Status</th>
              <th className="px-4 py-3 text-left font-medium">Submitted</th>
              <th className="px-4 py-3 text-left font-medium">SLA</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100">
            {requests.map((row) => (
              <tr
                key={row.id}
                className="hover:bg-orange-50 cursor-pointer"
                onClick={() => setSelected(row)}
              >
                <td className="px-4 py-3 font-mono text-sm text-gray-800">{row.id.slice(0, 8)}</td>
                <td className="px-4 py-3 text-gray-700">{row.storeName || '—'}</td>
                <td className="px-4 py-3 text-gray-700">{row.userMasked}</td>
                <td className="px-4 py-3">
                  <span className={`rounded-full px-2 py-0.5 text-xs font-semibold ${STATUS_COLORS[row.status] ?? 'bg-gray-200 text-gray-700'}`}>
                    {formatStatus(row.status)}
                  </span>
                </td>
                <td className="px-4 py-3 text-gray-600">{new Date(row.createdAt).toLocaleString()}</td>
                <td className="px-4 py-3 text-gray-600">{formatSla(row.expiresAt, row.status)}</td>
              </tr>
            ))}
          </tbody>
        </table>
        {requests.length === 0 && (
          <div className="py-8 text-center text-gray-500">No requests in this bucket.</div>
        )}
      </div>

      {totalPages > 1 && (
        <div className="flex items-center justify-center gap-4">
          <button
            type="button"
            onClick={() => onChangePage(Math.max(1, page - 1))}
            disabled={page <= 1}
            className="rounded-lg border border-gray-300 px-3 py-1.5 text-sm disabled:opacity-40"
          >
            Previous
          </button>
          <span className="text-sm text-gray-600">Page {page} of {totalPages}</span>
          <button
            type="button"
            onClick={() => onChangePage(Math.min(totalPages, page + 1))}
            disabled={page >= totalPages}
            className="rounded-lg border border-gray-300 px-3 py-1.5 text-sm disabled:opacity-40"
          >
            Next
          </button>
        </div>
      )}

      {selected && (
        <div className="fixed inset-0 z-40 flex">
          <div className="flex-1 bg-black/30" onClick={closeDrawer} />
          <div className="h-full w-full max-w-xl overflow-y-auto bg-white shadow-2xl">
            <div className="flex items-center justify-between border-b border-gray-200 px-6 py-4">
              <div>
                <p className="text-xs text-gray-500">Request ID</p>
                <p className="font-semibold text-gray-900">{selected.id}</p>
              </div>
              <button type="button" onClick={closeDrawer} className="rounded-full p-2 hover:bg-gray-100">
                <span className="sr-only">Close</span>
                ✕
              </button>
            </div>
            <div className="space-y-6 px-6 py-6">
              <div className="rounded-xl border border-gray-200 p-4">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-sm text-gray-500">Store</p>
                    <p className="font-semibold text-gray-900">{selected.storeName || '—'}</p>
                  </div>
                  <span className={`rounded-full px-2 py-0.5 text-xs font-semibold ${STATUS_COLORS[selected.status] ?? 'bg-gray-200 text-gray-700'}`}>
                    {formatStatus(selected.status)}
                  </span>
                </div>
                <div className="mt-4 grid grid-cols-2 gap-4 text-sm">
                  <div>
                    <p className="text-gray-500">Reason</p>
                    <p className="font-medium text-gray-900">{selected.reasonCode.replaceAll('_', ' ')}</p>
                  </div>
                  <div>
                    <p className="text-gray-500">Refund</p>
                    <p className="font-medium text-gray-900">${selected.refundAmount.toFixed(2)}</p>
                  </div>
                </div>
                <p className="mt-4 text-gray-700">{selected.reasonDetail}</p>
              </div>

              {detailLoading && <p className="text-sm text-gray-500">Loading detail…</p>}
              {detailError && <p className="text-sm text-rose-600">{detailError}</p>}

              {detail?.request && (
                <>
                  <AttachmentBlock title="User attachments" attachments={detail.request.user_attachments ?? []} />
                  <AttachmentBlock title="Merchant attachments" attachments={detail.request.merchant_attachments ?? []} />
                  <AttachmentBlock title="Platform attachments" attachments={detail.request.platform_attachments ?? []} />
                  <TimelineBlock entries={detail.request.timeline ?? []} />
                </>
              )}

              {(selected.status === 'awaiting_platform') && (
                <div className="space-y-3">
                  <button
                    type="button"
                    onClick={() => setDecisionState({ action: 'approve' })}
                    className="w-full rounded-lg bg-emerald-600 px-4 py-2 font-semibold text-white hover:bg-emerald-700"
                  >
                    Approve & refund
                  </button>
                  <button
                    type="button"
                    onClick={() => setDecisionState({ action: 'reject' })}
                    className="w-full rounded-lg border border-rose-400 px-4 py-2 font-semibold text-rose-700 hover:bg-rose-50"
                  >
                    Reject with evidence
                  </button>
                </div>
              )}

              {actionMessage && (
                <p className="text-sm text-gray-600">{actionMessage}</p>
              )}
            </div>
          </div>
        </div>
      )}

      {decisionState && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/30 p-4">
          <div className="w-full max-w-lg rounded-2xl bg-white p-6 shadow-xl">
            <h2 className="text-lg font-semibold text-gray-900">
              {decisionState.action === 'approve' ? 'Approve request' : 'Reject request'}
            </h2>
            <p className="mt-2 text-sm text-gray-600">
              {decisionState.action === 'approve'
                ? 'Add a note that will be shared with the merchant log.'
                : 'Provide a detailed rejection reason (min 10 characters) and supporting files.'}
            </p>
            <textarea
              value={decisionNote}
              onChange={(e) => setDecisionNote(e.target.value)}
              rows={4}
              className="mt-4 w-full rounded-lg border border-gray-300 px-3 py-2"
              placeholder="Decision note"
            />
            {decisionState.action === 'reject' && (
              <div className="mt-4">
                <input
                  type="file"
                  accept="image/*"
                  multiple
                  onChange={(e) => setDecisionFiles(Array.from(e.target.files ?? []))}
                />
                <p className="mt-2 text-xs text-gray-500">
                  Evidence is required for rejection. Maximum 3 images will be uploaded.
                </p>
              </div>
            )}
            <div className="mt-6 flex justify-end gap-3">
              <button
                type="button"
                onClick={() => {
                  setDecisionState(null)
                  setDecisionNote('')
                  setDecisionFiles([])
                }}
                className="rounded-lg border border-gray-300 px-4 py-2 text-sm"
              >
                Cancel
              </button>
              <button
                type="button"
                disabled={actionLoading || decisionNote.trim().length < (decisionState.action === 'approve' ? 5 : 10)}
                onClick={() => submitDecision(decisionState.action)}
                className="rounded-lg bg-orange-600 px-4 py-2 text-sm font-semibold text-white disabled:opacity-50"
              >
                {actionLoading ? 'Submitting…' : 'Submit'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}

function AttachmentBlock({ title, attachments }: { title: string; attachments: string[] }) {
  if (!attachments.length) return null
  return (
    <div>
      <h3 className="font-semibold text-gray-800">{title}</h3>
      <div className="mt-2 flex flex-wrap gap-2">
        {attachments.map((url, idx) => (
          <a
            key={`${url}-${idx}`}
            href={url}
            target="_blank"
            rel="noreferrer"
            className="rounded-full border border-gray-300 px-3 py-1 text-xs text-gray-700 hover:bg-gray-50"
          >
            Attachment {idx + 1}
          </a>
        ))}
      </div>
    </div>
  )
}

function TimelineBlock({ entries }: { entries: Array<{ status: string; actor: string; note?: string; attachments?: string[]; at: string }> }) {
  if (!entries.length) return null
  return (
    <div>
      <h3 className="font-semibold text-gray-800">Timeline</h3>
      <div className="mt-3 space-y-4">
        {entries.map((entry, idx) => (
          <div key={`${entry.status}-${idx}`} className="rounded-lg border border-gray-200 p-3">
            <div className="flex items-center justify-between text-sm text-gray-600">
              <span className="font-semibold text-gray-900">{entry.status.replaceAll('_', ' ')}</span>
              <span>{new Date(entry.at).toLocaleString()}</span>
            </div>
            <p className="mt-2 text-sm text-gray-700">Actor: {entry.actor}</p>
            {entry.note && <p className="mt-1 text-sm text-gray-600">{entry.note}</p>}
            {(entry.attachments?.length ?? 0) > 0 && (
              <div className="mt-2 flex flex-wrap gap-2">
                {entry.attachments?.map((url, innerIdx) => (
                  <a
                    key={`${url}-${innerIdx}`}
                    href={url}
                    target="_blank"
                    rel="noreferrer"
                    className="rounded-full border border-gray-300 px-3 py-1 text-xs hover:bg-gray-50"
                  >
                    Timeline file {innerIdx + 1}
                  </a>
                ))}
              </div>
            )}
          </div>
        ))}
      </div>
    </div>
  )
}
