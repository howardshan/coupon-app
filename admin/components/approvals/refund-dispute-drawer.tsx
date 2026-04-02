'use client'

import { useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { toast } from 'sonner'
import type { RefundDisputeItem } from '@/app/(dashboard)/approvals/page'
import { approveRefundDispute, rejectRefundDispute } from '@/app/actions/approvals'

type RefundLineItem = {
  name: string
  qty?: number
  unit_price?: number
  refund_amount?: number
}

function parseRefundItems(raw: unknown): RefundLineItem[] {
  if (!Array.isArray(raw)) return []
  return raw.map((item: unknown) => {
    if (item && typeof item === 'object') {
      const obj = item as Record<string, unknown>
      return {
        name: String(obj.name ?? ''),
        qty: obj.qty != null ? Number(obj.qty) : undefined,
        unit_price: obj.unit_price != null ? Number(obj.unit_price) : undefined,
        refund_amount: obj.refund_amount != null ? Number(obj.refund_amount) : undefined,
      }
    }
    return { name: String(item) }
  })
}

export default function RefundDisputeDrawer({
  dispute,
  onClose,
}: {
  dispute: RefundDisputeItem
  onClose: () => void
}) {
  const router = useRouter()
  const [isPending, startTransition] = useTransition()
  const [showApproveModal, setShowApproveModal] = useState(false)
  const [showRejectModal, setShowRejectModal] = useState(false)
  const [adminNote, setAdminNote] = useState('')
  const [rejectReason, setRejectReason] = useState('')

  const lineItems = parseRefundItems(dispute.refundItems)

  function handleApprove() {
    startTransition(async () => {
      try {
        await approveRefundDispute(dispute.id, adminNote.trim() || undefined)
        toast.success(`Refund of $${dispute.refundAmount.toFixed(2)} approved`)
        setShowApproveModal(false)
        onClose()
        router.refresh()
      } catch (e) {
        toast.error(e instanceof Error ? e.message : 'Action failed')
      }
    })
  }

  function handleReject() {
    startTransition(async () => {
      try {
        await rejectRefundDispute(dispute.id, rejectReason)
        toast.success('Refund dispute rejected')
        setShowRejectModal(false)
        onClose()
        router.refresh()
      } catch (e) {
        toast.error(e instanceof Error ? e.message : 'Action failed')
      }
    })
  }

  return (
    <>
      <div className="fixed inset-0 z-40 flex justify-end">
        <div className="flex-1 bg-black/30" onClick={onClose} />
        <div className="h-full w-full max-w-2xl overflow-y-auto bg-white shadow-2xl flex flex-col">

          {/* 抽屉头部 */}
          <div className="flex items-center justify-between border-b border-gray-200 px-6 py-4 sticky top-0 bg-white z-10">
            <div>
              <span className="text-xs font-semibold uppercase tracking-wide text-orange-600 bg-orange-100 px-2 py-0.5 rounded-full">
                Refund Dispute
              </span>
              <h2 className="text-lg font-bold text-gray-900 mt-1">
                ${dispute.refundAmount.toFixed(2)} — {dispute.merchantName}
              </h2>
              <p className="text-sm text-gray-500">
                Submitted {new Date(dispute.createdAt).toLocaleString()}
              </p>
            </div>
            <button type="button" onClick={onClose} className="p-2 rounded-full hover:bg-gray-100 text-gray-500">
              ✕
            </button>
          </div>

          <div className="flex-1 px-6 py-6 space-y-6">

            {/* 争议概览 */}
            <section className="rounded-xl border border-gray-200 p-4">
              <h3 className="font-semibold text-gray-800 mb-3">Overview</h3>
              <dl className="grid grid-cols-2 gap-x-4 gap-y-3 text-sm">
                <div>
                  <dt className="text-gray-500">Refund Amount</dt>
                  <dd className="font-bold text-xl text-gray-900">${dispute.refundAmount.toFixed(2)}</dd>
                </div>
                <div>
                  <dt className="text-gray-500">Customer</dt>
                  <dd className="font-medium text-gray-900">{dispute.userNameMasked}</dd>
                </div>
                <div>
                  <dt className="text-gray-500">Merchant</dt>
                  <dd className="font-medium text-gray-900">{dispute.merchantName}</dd>
                </div>
                <div>
                  <dt className="text-gray-500">Order</dt>
                  <dd>
                    <a
                      href={`/orders/${dispute.orderId}`}
                      target="_blank"
                      rel="noreferrer"
                      className="text-blue-600 hover:underline font-mono text-xs"
                    >
                      {dispute.orderId.slice(0, 8)}… ↗
                    </a>
                  </dd>
                </div>
                <div>
                  <dt className="text-gray-500">Submitted</dt>
                  <dd className="font-medium text-gray-900">{new Date(dispute.createdAt).toLocaleString()}</dd>
                </div>
                {dispute.merchantDecidedAt && (
                  <div>
                    <dt className="text-gray-500">Merchant Rejected</dt>
                    <dd className="font-medium text-gray-900">{new Date(dispute.merchantDecidedAt).toLocaleString()}</dd>
                  </div>
                )}
              </dl>
            </section>

            {/* 争议商品明细 */}
            {lineItems.length > 0 && (
              <section className="rounded-xl border border-gray-200 p-4">
                <h3 className="font-semibold text-gray-800 mb-3">Refund Items</h3>
                <table className="w-full text-sm">
                  <thead className="border-b border-gray-100">
                    <tr>
                      <th className="text-left pb-2 font-medium text-gray-500">Item</th>
                      <th className="text-right pb-2 font-medium text-gray-500">Qty</th>
                      <th className="text-right pb-2 font-medium text-gray-500">Unit Price</th>
                      <th className="text-right pb-2 font-medium text-gray-500">Refund</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-gray-50">
                    {lineItems.map((item, i) => (
                      <tr key={i}>
                        <td className="py-2 text-gray-900">{item.name}</td>
                        <td className="py-2 text-right text-gray-600">{item.qty ?? '—'}</td>
                        <td className="py-2 text-right text-gray-600">
                          {item.unit_price != null ? `$${item.unit_price.toFixed(2)}` : '—'}
                        </td>
                        <td className="py-2 text-right font-medium text-gray-900">
                          {item.refund_amount != null ? `$${item.refund_amount.toFixed(2)}` : '—'}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                  <tfoot className="border-t border-gray-200">
                    <tr>
                      <td colSpan={3} className="pt-2 text-right font-semibold text-gray-700">Total Refund</td>
                      <td className="pt-2 text-right font-bold text-gray-900">${dispute.refundAmount.toFixed(2)}</td>
                    </tr>
                  </tfoot>
                </table>
              </section>
            )}

            {/* 双方陈述 */}
            <section className="space-y-3">
              <div className="rounded-xl border border-blue-200 bg-blue-50 p-4">
                <h3 className="font-semibold text-blue-800 mb-2">Customer's Reason</h3>
                <p className="text-sm text-blue-900 whitespace-pre-line">{dispute.userReason}</p>
              </div>
              {dispute.merchantReason && (
                <div className="rounded-xl border border-red-200 bg-red-50 p-4">
                  <h3 className="font-semibold text-red-800 mb-2">Merchant's Rejection Reason</h3>
                  <p className="text-sm text-red-900 whitespace-pre-line">{dispute.merchantReason}</p>
                </div>
              )}
            </section>

          </div>

          {/* 仲裁操作区 */}
          <div className="border-t border-gray-200 px-6 py-4 space-y-3 bg-white sticky bottom-0">
            <button
              type="button"
              onClick={() => setShowApproveModal(true)}
              disabled={isPending}
              className="w-full rounded-lg bg-emerald-600 px-4 py-2.5 font-semibold text-white hover:bg-emerald-700 transition-colors text-sm disabled:opacity-50"
            >
              Approve & Refund ${dispute.refundAmount.toFixed(2)}
            </button>
            <button
              type="button"
              onClick={() => setShowRejectModal(true)}
              disabled={isPending}
              className="w-full rounded-lg border border-rose-400 px-4 py-2.5 font-semibold text-rose-700 hover:bg-rose-50 transition-colors text-sm disabled:opacity-50"
            >
              Final Rejection
            </button>
          </div>
        </div>
      </div>

      {/* Approve 确认弹窗 */}
      {showApproveModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4">
          <div className="w-full max-w-md rounded-2xl bg-white p-6 shadow-xl">
            <h3 className="text-lg font-semibold text-gray-900">Approve & Refund</h3>
            <p className="mt-2 text-sm text-gray-600">
              Refund <span className="font-bold text-gray-900">${dispute.refundAmount.toFixed(2)}</span> to the customer?
              This action cannot be undone.
            </p>
            <textarea
              value={adminNote}
              onChange={e => setAdminNote(e.target.value)}
              rows={2}
              placeholder="Optional note (not shown to customer)"
              className="mt-3 w-full rounded-lg border border-gray-300 px-3 py-2 text-sm"
            />
            <div className="mt-4 flex justify-end gap-3">
              <button
                type="button"
                onClick={() => { setShowApproveModal(false); setAdminNote('') }}
                className="px-4 py-2 rounded-lg border border-gray-300 text-sm"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleApprove}
                disabled={isPending}
                className="px-4 py-2 rounded-lg bg-emerald-600 text-sm font-semibold text-white hover:bg-emerald-700 disabled:opacity-50"
              >
                {isPending ? 'Processing…' : 'Confirm Refund'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Reject 弹窗 */}
      {showRejectModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4">
          <div className="w-full max-w-md rounded-2xl bg-white p-6 shadow-xl">
            <h3 className="text-lg font-semibold text-gray-900">Final Rejection</h3>
            <p className="mt-2 text-sm text-gray-600">
              This is the final decision. The customer will be notified via email.
            </p>
            <textarea
              value={rejectReason}
              onChange={e => setRejectReason(e.target.value)}
              rows={3}
              placeholder="Rejection reason (min 10 characters, sent to customer)"
              className="mt-3 w-full rounded-lg border border-gray-300 px-3 py-2 text-sm"
            />
            <div className="mt-4 flex justify-end gap-3">
              <button
                type="button"
                onClick={() => { setShowRejectModal(false); setRejectReason('') }}
                className="px-4 py-2 rounded-lg border border-gray-300 text-sm"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleReject}
                disabled={isPending || rejectReason.trim().length < 10}
                className="px-4 py-2 rounded-lg bg-rose-600 text-sm font-semibold text-white hover:bg-rose-700 disabled:opacity-50"
              >
                {isPending ? 'Processing…' : 'Confirm Rejection'}
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  )
}
