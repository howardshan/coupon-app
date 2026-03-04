'use client'

import { useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { toast } from 'sonner'
import { approveMerchant, rejectMerchant, revokeMerchantApproval } from '@/app/actions/admin'

interface MerchantReviewActionsProps {
  merchantId: string
  merchantUserId: string
  status: string
  rejectionReason: string | null
}

export default function MerchantReviewActions({
  merchantId,
  merchantUserId,
  status,
  rejectionReason: initialRejectionReason,
}: MerchantReviewActionsProps) {
  const router = useRouter()
  const [isPending, startTransition] = useTransition()
  const [showRejectModal, setShowRejectModal] = useState(false)
  const [rejectionReason, setRejectionReason] = useState(initialRejectionReason ?? '')

  function handleApprove() {
    startTransition(async () => {
      try {
        await approveMerchant(merchantId, merchantUserId)
        toast.success('Merchant approved')
        router.refresh()
      } catch (e) {
        toast.error(e instanceof Error ? e.message : 'Action failed')
      }
    })
  }

  function handleReject() {
    setShowRejectModal(true)
  }

  function confirmReject() {
    startTransition(async () => {
      try {
        await rejectMerchant(merchantId, rejectionReason.trim() || null)
        toast.success('Merchant rejected')
        setShowRejectModal(false)
        setRejectionReason('')
        router.refresh()
      } catch (e) {
        toast.error(e instanceof Error ? e.message : 'Action failed')
      }
    })
  }

  function handleRevoke() {
    if (!confirm('Revoke approval and put this merchant back under review?')) return
    startTransition(async () => {
      try {
        await revokeMerchantApproval(merchantId)
        toast.success('Approval revoked. Merchant is pending review again.')
        router.refresh()
      } catch (e) {
        toast.error(e instanceof Error ? e.message : 'Action failed')
      }
    })
  }

  return (
    <div className="flex items-center gap-2">
      {status === 'pending' && (
        <>
          <button
            onClick={handleApprove}
            disabled={isPending}
            className="px-4 py-2 text-sm font-medium rounded-lg bg-green-600 text-white hover:bg-green-700 disabled:opacity-50 transition-colors"
          >
            Approve
          </button>
          <button
            onClick={handleReject}
            disabled={isPending}
            className="px-4 py-2 text-sm font-medium rounded-lg bg-red-100 text-red-700 hover:bg-red-200 disabled:opacity-50 transition-colors"
          >
            Reject
          </button>
        </>
      )}
      {status === 'approved' && (
        <button
          onClick={handleRevoke}
          disabled={isPending}
          className="px-4 py-2 text-sm font-medium rounded-lg bg-amber-100 text-amber-800 hover:bg-amber-200 disabled:opacity-50 transition-colors"
        >
          Revoke approval
        </button>
      )}
      {status === 'rejected' && (
        <button
          onClick={handleApprove}
          disabled={isPending}
          className="px-4 py-2 text-sm font-medium rounded-lg bg-green-600 text-white hover:bg-green-700 disabled:opacity-50 transition-colors"
        >
          Approve
        </button>
      )}

      {showRejectModal && (
        <div className="fixed inset-0 bg-black/40 flex items-center justify-center z-50">
          <div className="bg-white rounded-xl shadow-xl w-full max-w-md p-6">
            <h3 className="text-lg font-bold text-gray-900 mb-2">Reject application</h3>
            <p className="text-sm text-gray-500 mb-3">Optionally provide a reason (visible to the merchant).</p>
            <textarea
              value={rejectionReason}
              onChange={e => setRejectionReason(e.target.value)}
              placeholder="e.g. Incomplete documents, invalid EIN..."
              rows={3}
              className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm text-gray-900 placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-500 mb-4"
            />
            <div className="flex gap-2 justify-end">
              <button
                type="button"
                onClick={() => setShowRejectModal(false)}
                className="px-4 py-2 text-sm font-medium rounded-lg border border-gray-300 text-gray-700 hover:bg-gray-50"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={confirmReject}
                disabled={isPending}
                className="px-4 py-2 text-sm font-medium rounded-lg bg-red-600 text-white hover:bg-red-700 disabled:opacity-50"
              >
                Reject
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
