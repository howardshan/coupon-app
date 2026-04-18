'use client'

import { useState, useTransition } from 'react'
import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { toast } from 'sonner'
import type { StripeUnlinkItem } from '@/app/(dashboard)/approvals/page'
import {
  approveStripeUnlinkRequest,
  rejectStripeUnlinkRequest,
} from '@/app/actions/stripe-unlink-approvals'
import { revalidateApprovalsPendingCount } from '@/app/actions/approvals'

const STATUS_BADGE: Record<string, string> = {
  pending: 'bg-amber-100 text-amber-800',
  approved: 'bg-emerald-100 text-emerald-800',
  rejected: 'bg-rose-100 text-rose-800',
}

type Props = {
  item: StripeUnlinkItem
  onClose: () => void
  /** 待办队列才显示通过/拒绝 */
  canDecide: boolean
}

function formatWhen(iso: string | null | undefined) {
  if (iso == null || String(iso).trim() === '') return '—'
  const d = new Date(iso)
  return Number.isNaN(d.getTime()) ? '—' : d.toLocaleString()
}

export default function StripeUnlinkDrawer({ item, onClose, canDecide }: Props) {
  const router = useRouter()
  const [reason, setReason] = useState('')
  const [isPending, startTransition] = useTransition()

  const shortId = item.id.replace(/-/g, '').slice(0, 8).toUpperCase()
  const scopeLine =
    item.subjectType === 'brand'
      ? `Brand: ${item.brandName ?? item.subjectId.slice(0, 8)}`
      : `Store: ${item.merchantName}`

  function onApprove() {
    startTransition(async () => {
      try {
        await approveStripeUnlinkRequest(item.id)
        await revalidateApprovalsPendingCount()
        toast.success('Approved. Platform-side Stripe data cleared.')
        onClose()
        router.refresh()
      } catch (e) {
        toast.error((e as Error).message)
      }
    })
  }

  function onReject() {
    const t = reason.trim()
    if (t.length < 10) {
      toast.error('Rejection reason must be at least 10 characters.')
      return
    }
    startTransition(async () => {
      try {
        await rejectStripeUnlinkRequest(item.id, t)
        await revalidateApprovalsPendingCount()
        toast.success('Request rejected. Merchant will be notified by email.')
        setReason('')
        onClose()
        router.refresh()
      } catch (e) {
        toast.error((e as Error).message)
      }
    })
  }

  return (
    <div className="fixed inset-0 z-50 flex justify-end">
      <button
        type="button"
        className="absolute inset-0 bg-black/30"
        aria-label="Close"
        onClick={onClose}
      />
      <div className="relative h-full w-full max-w-lg overflow-y-auto border-l border-gray-200 bg-white shadow-xl">
        <div className="sticky top-0 z-10 flex items-center justify-between border-b border-gray-100 bg-white px-4 py-3">
          <h2 className="text-lg font-semibold text-gray-900">Stripe Unlink</h2>
          <button
            type="button"
            onClick={onClose}
            className="rounded-lg p-1.5 text-gray-500 hover:bg-gray-100"
          >
            ✕
          </button>
        </div>
        <div className="space-y-4 p-4 text-sm text-gray-700">
          <div>
            <span
              className={`inline-flex rounded-full px-2.5 py-0.5 text-xs font-semibold ${
                STATUS_BADGE[item.status] ?? 'bg-gray-100 text-gray-800'
              }`}
            >
              {item.status}
            </span>
          </div>
          <p>
            <span className="text-gray-500">Request ID</span>
            <br />
            <code className="text-xs font-mono">{shortId}</code>
          </p>
          <p>
            <span className="text-gray-500">Scope</span>
            <br />
            {scopeLine} ({item.subjectType})
          </p>
          <p>
            <span className="text-gray-500">Store (row anchor)</span>
            <br />
            <Link href={`/merchants/${item.merchantId}`} className="text-blue-600 hover:underline">
              {item.merchantName}
            </Link>
          </p>
          <p>
            <span className="text-gray-500">Submitted</span>
            <br />
            {formatWhen(item.createdAt)}
          </p>
          {item.requestNote && (
            <p>
              <span className="text-gray-500">Merchant note</span>
              <br />
              <span className="whitespace-pre-wrap text-gray-800">{item.requestNote}</span>
            </p>
          )}
          {item.rejectedReason && (
            <p>
              <span className="text-gray-500">Rejection reason</span>
              <br />
              <span className="whitespace-pre-wrap text-rose-800">{item.rejectedReason}</span>
            </p>
          )}
          {item.reviewedAt && (
            <p>
              <span className="text-gray-500">Resolved at</span>
              <br />
              {formatWhen(item.reviewedAt)}
            </p>
          )}
          {item.unbindAppliedAt && (
            <p>
              <span className="text-gray-500">Platform unbind applied</span>
              <br />
              {formatWhen(item.unbindAppliedAt)}
            </p>
          )}

          {canDecide && item.status === 'pending' && (
            <div className="space-y-3 border-t border-gray-100 pt-4">
              <p className="text-xs text-amber-800">
                This only clears platform database fields. It does not close the account in Stripe.
              </p>
              <div className="flex flex-col gap-2 sm:flex-row">
                <button
                  type="button"
                  disabled={isPending}
                  onClick={onApprove}
                  className="rounded-lg bg-emerald-600 px-4 py-2.5 text-sm font-semibold text-white hover:bg-emerald-700 disabled:opacity-50"
                >
                  {isPending ? '…' : 'Approve & unlink (DB)'}
                </button>
              </div>
              <div>
                <label className="mb-1 block text-xs font-medium text-gray-500">Reject (min 10 chars)</label>
                <textarea
                  value={reason}
                  onChange={(e) => setReason(e.target.value)}
                  rows={3}
                  className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm"
                  placeholder="Reason will be emailed to the merchant (M21)."
                />
                <button
                  type="button"
                  disabled={isPending || reason.trim().length < 10}
                  onClick={onReject}
                  className="mt-2 rounded-lg border border-rose-300 bg-rose-50 px-4 py-2.5 text-sm font-semibold text-rose-800 hover:bg-rose-100 disabled:opacity-50"
                >
                  Reject request
                </button>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
