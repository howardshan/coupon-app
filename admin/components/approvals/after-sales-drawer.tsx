'use client'

import { useEffect, useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import type { AfterSalesItem } from '@/app/(dashboard)/approvals/page'
import { revalidateApprovalsPendingCount } from '@/app/actions/approvals'

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
    if (!putRes.ok) throw new Error('Failed to upload evidence')
    uploaded.push(slot.path)
  }
  return uploaded
}

export default function AfterSalesDrawer({
  item,
  onClose,
}: {
  item: AfterSalesItem
  onClose: () => void
}) {
  const router = useRouter()
  const [, startTransition] = useTransition()
  const [detail, setDetail] = useState<AfterSalesDetail | null>(null)
  const [detailLoading, setDetailLoading] = useState(false)
  const [detailError, setDetailError] = useState<string | null>(null)
  const [actionMessage, setActionMessage] = useState<string | null>(null)
  const [decisionState, setDecisionState] = useState<null | { action: 'approve' | 'reject' }>(null)
  const [decisionNote, setDecisionNote] = useState('')
  const [decisionFiles, setDecisionFiles] = useState<File[]>([])
  const [actionLoading, setActionLoading] = useState(false)
  // 乐观更新状态
  const [currentStatus, setCurrentStatus] = useState(item.status)

  // 加载详情
  useEffect(() => {
    setDetail(null)
    setDetailError(null)
    setDetailLoading(true)
    fetch(`/api/platform-after-sales/${item.id}`)
      .then(async (res) => {
        if (!res.ok) {
          const body = await res.json().catch(() => ({}))
          throw new Error(body?.message ?? 'Failed to load detail')
        }
        return res.json()
      })
      .then((data) => setDetail(data as AfterSalesDetail))
      .catch((err) => setDetailError(err.message))
      .finally(() => setDetailLoading(false))
  }, [item.id])

  async function submitDecision(action: 'approve' | 'reject') {
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
      const response = await fetch(`/api/platform-after-sales/${item.id}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ action, note: decisionNote, attachments }),
      })
      if (!response.ok) {
        const body = await response.json().catch(() => ({}))
        throw new Error(body?.message ?? 'Failed to submit decision')
      }
      setActionMessage(action === 'approve' ? 'Request approved' : 'Request rejected')
      setDecisionState(null)
      setDecisionNote('')
      setDecisionFiles([])
      setCurrentStatus(action === 'approve' ? 'refunded' : 'platform_rejected')
      await revalidateApprovalsPendingCount()
      startTransition(() => { router.refresh() })
    } catch (err) {
      setActionMessage((err as Error).message)
    } finally {
      setActionLoading(false)
    }
  }

  return (
    <>
      <div className="fixed inset-0 z-40 flex justify-end">
        <div className="flex-1 bg-black/30" onClick={onClose} />
        <div className="h-full w-full max-w-2xl overflow-y-auto bg-white shadow-2xl flex flex-col">

          {/* 抽屉头部 */}
          <div className="flex items-center justify-between border-b border-gray-200 px-6 py-4 sticky top-0 bg-white z-10">
            <div>
              <span className="text-xs font-semibold uppercase tracking-wide text-purple-600 bg-purple-100 px-2 py-0.5 rounded-full">
                After-Sales
              </span>
              <h2 className="text-lg font-bold text-gray-900 mt-1">
                ${item.refundAmount.toFixed(2)} — {item.storeName ?? '—'}
              </h2>
              <p className="text-sm text-gray-500">
                Submitted {new Date(item.createdAt).toLocaleString()}
              </p>
            </div>
            <button type="button" onClick={onClose} className="p-2 rounded-full hover:bg-gray-100 text-gray-500">
              ✕
            </button>
          </div>

          <div className="flex-1 px-6 py-6 space-y-6">

            {/* 概览卡片 */}
            <section className="rounded-xl border border-gray-200 p-4">
              <div className="flex items-center justify-between mb-3">
                <h3 className="font-semibold text-gray-800">Overview</h3>
                <span className={`rounded-full px-2 py-0.5 text-xs font-semibold ${STATUS_COLORS[currentStatus] ?? 'bg-gray-200 text-gray-700'}`}>
                  {formatStatus(currentStatus)}
                </span>
              </div>
              <dl className="grid grid-cols-2 gap-x-4 gap-y-3 text-sm">
                <div>
                  <dt className="text-gray-500">Refund Amount</dt>
                  <dd className="font-bold text-xl text-gray-900">${item.refundAmount.toFixed(2)}</dd>
                </div>
                <div>
                  <dt className="text-gray-500">Customer</dt>
                  <dd className="font-medium text-gray-900">{item.userMasked}</dd>
                </div>
                <div>
                  <dt className="text-gray-500">Reason</dt>
                  <dd className="font-medium text-gray-900">{item.reasonCode.replaceAll('_', ' ')}</dd>
                </div>
                <div>
                  <dt className="text-gray-500">SLA</dt>
                  <dd className="font-medium text-gray-900">{formatSla(item.expiresAt, currentStatus)}</dd>
                </div>
              </dl>
              {item.reasonDetail && (
                <p className="mt-3 text-sm text-gray-700 whitespace-pre-line border-t border-gray-100 pt-3">
                  {item.reasonDetail}
                </p>
              )}
            </section>

            {/* 懒加载详情 */}
            {detailLoading && (
              <p className="text-sm text-gray-500 text-center py-4">Loading detail…</p>
            )}
            {detailError && (
              <p className="text-sm text-rose-600 bg-rose-50 rounded-lg p-3">{detailError}</p>
            )}

            {detail?.request && (
              <>
                <AttachmentBlock title="User Attachments" attachments={detail.request.user_attachments ?? []} />
                <AttachmentBlock title="Merchant Attachments" attachments={detail.request.merchant_attachments ?? []} />
                <AttachmentBlock title="Platform Attachments" attachments={detail.request.platform_attachments ?? []} />
                <TimelineBlock entries={detail.request.timeline ?? []} />
              </>
            )}

            {/* 操作反馈 */}
            {actionMessage && (
              <p className={`text-sm rounded-lg p-3 ${actionMessage.includes('approved') || actionMessage.includes('rejected') ? 'bg-emerald-50 text-emerald-700' : 'bg-rose-50 text-rose-700'}`}>
                {actionMessage}
              </p>
            )}
          </div>

          {/* 仲裁操作区（仅 awaiting_platform 状态可操作） */}
          {currentStatus === 'awaiting_platform' && (
            <div className="border-t border-gray-200 px-6 py-4 space-y-3 bg-white sticky bottom-0">
              <button
                type="button"
                onClick={() => setDecisionState({ action: 'approve' })}
                className="w-full rounded-lg bg-emerald-600 px-4 py-2.5 font-semibold text-white hover:bg-emerald-700 transition-colors text-sm"
              >
                Approve & Refund ${item.refundAmount.toFixed(2)}
              </button>
              <button
                type="button"
                onClick={() => setDecisionState({ action: 'reject' })}
                className="w-full rounded-lg border border-rose-400 px-4 py-2.5 font-semibold text-rose-700 hover:bg-rose-50 transition-colors text-sm"
              >
                Reject with Evidence
              </button>
            </div>
          )}
        </div>
      </div>

      {/* 决策确认弹窗 */}
      {decisionState && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4">
          <div className="w-full max-w-lg rounded-2xl bg-white p-6 shadow-xl">
            <h3 className="text-lg font-semibold text-gray-900">
              {decisionState.action === 'approve' ? 'Approve & Refund' : 'Reject with Evidence'}
            </h3>
            <p className="mt-2 text-sm text-gray-600">
              {decisionState.action === 'approve'
                ? 'Add a note that will be logged in the merchant timeline.'
                : 'Provide a detailed rejection reason (min 10 characters) and at least one supporting image.'}
            </p>
            <textarea
              value={decisionNote}
              onChange={(e) => setDecisionNote(e.target.value)}
              rows={4}
              placeholder={decisionState.action === 'approve' ? 'Decision note (optional)' : 'Rejection reason (required)'}
              className="mt-4 w-full rounded-lg border border-gray-300 px-3 py-2 text-sm"
            />
            {decisionState.action === 'reject' && (
              <div className="mt-4">
                <input
                  type="file"
                  accept="image/*"
                  multiple
                  onChange={(e) => setDecisionFiles(Array.from(e.target.files ?? []))}
                  className="text-sm"
                />
                <p className="mt-1 text-xs text-gray-500">
                  Evidence is required for rejection. Maximum 3 images.
                </p>
              </div>
            )}
            <div className="mt-6 flex justify-end gap-3">
              <button
                type="button"
                onClick={() => { setDecisionState(null); setDecisionNote(''); setDecisionFiles([]) }}
                className="px-4 py-2 rounded-lg border border-gray-300 text-sm"
              >
                Cancel
              </button>
              <button
                type="button"
                disabled={
                  actionLoading ||
                  (decisionState.action === 'approve'
                    ? false
                    : decisionNote.trim().length < 10 || decisionFiles.length === 0)
                }
                onClick={() => submitDecision(decisionState.action)}
                className="px-4 py-2 rounded-lg bg-orange-600 text-sm font-semibold text-white hover:bg-orange-700 disabled:opacity-50"
              >
                {actionLoading ? 'Submitting…' : 'Submit'}
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  )
}

function AttachmentBlock({ title, attachments }: { title: string; attachments: string[] }) {
  if (!attachments.length) return null
  return (
    <section className="rounded-xl border border-gray-200 p-4">
      <h3 className="font-semibold text-gray-800 mb-2">{title}</h3>
      <div className="flex flex-wrap gap-2">
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
    </section>
  )
}

function TimelineBlock({
  entries,
}: {
  entries: Array<{ status: string; actor: string; note?: string; attachments?: string[]; at: string }>
}) {
  if (!entries.length) return null
  return (
    <section className="rounded-xl border border-gray-200 p-4">
      <h3 className="font-semibold text-gray-800 mb-3">Timeline</h3>
      <div className="space-y-3">
        {entries.map((entry, idx) => (
          <div key={`${entry.status}-${idx}`} className="rounded-lg border border-gray-100 bg-gray-50 p-3">
            <div className="flex items-center justify-between text-sm">
              <span className="font-semibold text-gray-900">{entry.status.replaceAll('_', ' ')}</span>
              <span className="text-gray-500">{new Date(entry.at).toLocaleString()}</span>
            </div>
            <p className="mt-1 text-xs text-gray-600">Actor: {entry.actor}</p>
            {entry.note && <p className="mt-1 text-sm text-gray-700">{entry.note}</p>}
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
                    File {innerIdx + 1}
                  </a>
                ))}
              </div>
            )}
          </div>
        ))}
      </div>
    </section>
  )
}
