'use client'

import { useEffect, useState, useTransition } from 'react'
import Link from 'next/link'
import { useRouter } from 'next/navigation'
import type { AfterSalesItem } from '@/app/(dashboard)/approvals/page'
import { revalidateApprovalsPendingCount } from '@/app/actions/approvals'
import AdminActivityTimelineCard from '@/components/admin-activity-timeline-card'
import { buildAfterSalesTimelineEntries } from '@/lib/after-sales-admin-timeline'

type AfterSalesDetail = {
  request: {
    id: string
    /** 平台 Edge 详情含 order_id，用于跳转订单页 */
    order_id?: string
    user_id?: string
    status: string
    created_at?: string
    escalated_at?: string | null
    reason_code?: string
    reason_detail?: string
    merchant_feedback?: string | null
    refund_amount?: number
    user_attachments?: string[]
    merchant_attachments?: string[]
    platform_feedback?: string | null
    platform_attachments?: string[]
    /** PostgREST 嵌套：单笔订单 */
    orders?: Record<string, unknown> | Record<string, unknown>[] | null
    /** 本单券核销时间 */
    coupons?: { used_at?: string | null } | { used_at?: string | null }[] | null
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

function formatLocalDateTime(value: string | null | undefined): string {
  if (value == null || String(value).trim() === '') return '—'
  const d = new Date(value)
  return Number.isNaN(d.getTime()) ? '—' : d.toLocaleString()
}

/** PostgREST 嵌套可能为对象或单元素数组 */
function pickEmbedded<T extends Record<string, unknown>>(
  raw: T | T[] | null | undefined
): T | null {
  if (raw == null) return null
  if (Array.isArray(raw)) return (raw[0] as T | undefined) ?? null
  return raw
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

  const req = detail?.request
  const orderRow = req ? pickEmbedded(req.orders as Record<string, unknown> | Record<string, unknown>[] | null) : null
  const couponRow = req ? pickEmbedded(req.coupons as { used_at?: string | null } | { used_at?: string | null }[] | null) : null
  const purchasedAt = orderRow?.created_at as string | undefined
  const redeemedAt = couponRow?.used_at ?? undefined
  const afterSalesOpenedAt = req?.created_at ?? item.createdAt
  const escalatedAt = req?.escalated_at ?? undefined

  const customerBody =
    (req?.reason_detail?.trim() || item.reasonDetail?.trim() || '').trim() || '—'
  const merchantBody = (req?.merchant_feedback?.trim() || '').trim()
  const platformBody = (req?.platform_feedback?.trim() || '').trim()
  const userAtt = req?.user_attachments ?? []
  const merchantAtt = req?.merchant_attachments ?? []
  const platformAtt = req?.platform_attachments ?? []

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

            {/* 概览：不含客户/商家长文本 */}
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
                  <dd className="font-medium text-gray-900">
                    {item.userId ? (
                      <Link
                        href={`/users/${item.userId}`}
                        className="text-blue-600 hover:underline"
                        target="_blank"
                        rel="noreferrer"
                      >
                        {item.userFullName}
                      </Link>
                    ) : (
                      item.userFullName
                    )}
                  </dd>
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
              {req?.order_id && (
                <p className="mt-3 border-t border-gray-100 pt-3 text-sm">
                  <a
                    href={`/orders/${req.order_id}`}
                    target="_blank"
                    rel="noreferrer"
                    className="font-medium text-blue-600 hover:underline"
                  >
                    Open full order detail (timelines & items) →
                  </a>
                </p>
              )}
            </section>

            {/* 订单与关键时间点 */}
            <section className="rounded-xl border border-gray-200 p-4">
              <h3 className="font-semibold text-gray-800 mb-3">Order & key dates</h3>
              {detailLoading && (
                <p className="text-sm text-gray-500">Loading order times…</p>
              )}
              {!detailLoading && (
                <dl className="grid grid-cols-1 gap-y-2 text-sm sm:grid-cols-2 sm:gap-x-4">
                  <div className="flex flex-col sm:flex-row sm:gap-2">
                    <dt className="text-gray-500 shrink-0">Purchased</dt>
                    <dd className="font-medium text-gray-900">{formatLocalDateTime(purchasedAt)}</dd>
                  </div>
                  <div className="flex flex-col sm:flex-row sm:gap-2">
                    <dt className="text-gray-500 shrink-0">Coupon redeemed</dt>
                    <dd className="font-medium text-gray-900">{formatLocalDateTime(redeemedAt)}</dd>
                  </div>
                  <div className="flex flex-col sm:flex-row sm:gap-2">
                    <dt className="text-gray-500 shrink-0">After-sales opened</dt>
                    <dd className="font-medium text-gray-900">{formatLocalDateTime(afterSalesOpenedAt)}</dd>
                  </div>
                  <div className="flex flex-col sm:flex-row sm:gap-2">
                    <dt className="text-gray-500 shrink-0">Escalated to platform</dt>
                    <dd className="font-medium text-gray-900">{formatLocalDateTime(escalatedAt)}</dd>
                  </div>
                </dl>
              )}
            </section>

            {detailLoading && (
              <p className="text-sm text-gray-500 text-center py-2">Loading evidence & timeline…</p>
            )}
            {detailError && (
              <p className="text-sm text-rose-600 bg-rose-50 rounded-lg p-3">{detailError}</p>
            )}

            {/* 客户陈述 + 附件 */}
            <section className="rounded-xl border border-gray-200 p-4">
              <h3 className="font-semibold text-gray-800 mb-2">Customer request</h3>
              <p className="text-sm text-gray-700 whitespace-pre-line">{customerBody}</p>
              {req && <AttachmentLinks label="Customer attachments" urls={userAtt} />}
            </section>

            {/* 商家拒绝说明 + 附件 */}
            {(merchantBody !== '' || merchantAtt.length > 0) && req && (
              <section className="rounded-xl border border-gray-200 p-4">
                <h3 className="font-semibold text-gray-800 mb-2">Merchant response</h3>
                {merchantBody !== '' ? (
                  <p className="text-sm text-gray-700 whitespace-pre-line">{merchantBody}</p>
                ) : (
                  <p className="text-sm text-gray-500">No written response.</p>
                )}
                <AttachmentLinks label="Merchant attachments" urls={merchantAtt} />
              </section>
            )}

            {/* 平台已填结论（若有） */}
            {(platformBody !== '' || platformAtt.length > 0) && req && (
              <section className="rounded-xl border border-gray-200 p-4">
                <h3 className="font-semibold text-gray-800 mb-2">Platform decision (recorded)</h3>
                {platformBody !== '' ? (
                  <p className="text-sm text-gray-700 whitespace-pre-line">{platformBody}</p>
                ) : null}
                <AttachmentLinks label="Platform attachments" urls={platformAtt} />
              </section>
            )}

            {req && (
              <AdminActivityTimelineCard
                title="After-sales timeline"
                footnote="Events are stored on the after-sales request record. Older requests may have incomplete history."
                events={buildAfterSalesTimelineEntries(req.timeline)}
              />
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

function AttachmentLinks({ label, urls }: { label: string; urls: string[] }) {
  const list = urls.filter((u) => typeof u === 'string' && u.trim().length > 0)
  if (!list.length) return null
  return (
    <div className="mt-3">
      <p className="text-xs font-semibold text-gray-500 mb-2">{label}</p>
      <div className="flex flex-wrap gap-2">
        {list.map((url, idx) => (
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

