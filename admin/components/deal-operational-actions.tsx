'use client'

import { useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { toast } from 'sonner'
import { setDealActive, rejectDeal } from '@/app/actions/admin'

interface DealOperationalActionsProps {
  dealId: string
  isActive: boolean
  dealStatus: string
}

/**
 * Deal 详情页运营操作：上架/待审在统一审批中心处理，此处仅保留已上线后的下架、
 * 以及非 pending 状态下的驳回（与旧 DealReviewActions 一致，但排除 pending 避免重复）。
 */
export default function DealOperationalActions({
  dealId,
  isActive,
  dealStatus,
}: DealOperationalActionsProps) {
  const router = useRouter()
  const [isPending, startTransition] = useTransition()
  const [showRejectForm, setShowRejectForm] = useState(false)
  const [rejectionReason, setRejectionReason] = useState('')

  if (dealStatus === 'pending') {
    return null
  }

  function handleDeactivate() {
    if (!confirm('Deactivate this deal? It will no longer be visible to users.')) return
    startTransition(async () => {
      try {
        await setDealActive(dealId, false)
        toast.success('Deal has been deactivated')
        router.refresh()
      } catch (e) {
        toast.error(e instanceof Error ? e.message : 'Action failed')
      }
    })
  }

  function handleReject() {
    if (!rejectionReason.trim()) {
      toast.error('Please enter a rejection reason')
      return
    }
    startTransition(async () => {
      try {
        await rejectDeal(dealId, rejectionReason)
        toast.success('Deal has been rejected')
        setShowRejectForm(false)
        setRejectionReason('')
        router.refresh()
      } catch (e) {
        toast.error(e instanceof Error ? e.message : 'Action failed')
      }
    })
  }

  const showDeactivate = isActive
  const showReject = dealStatus !== 'rejected'

  if (!showDeactivate && !showReject) {
    return null
  }

  return (
    <div className="flex flex-col items-end gap-3">
      <div className="flex flex-wrap items-center justify-end gap-2">
        {showDeactivate && (
          <button
            type="button"
            onClick={handleDeactivate}
            disabled={isPending}
            className="px-4 py-2 text-sm font-medium rounded-lg border border-gray-400 bg-gray-500 text-white shadow-sm hover:bg-gray-600 disabled:opacity-50 transition-colors"
          >
            Deactivate
          </button>
        )}
        {showReject && (
          <button
            type="button"
            onClick={() => setShowRejectForm(!showRejectForm)}
            disabled={isPending}
            className="px-4 py-2 text-sm font-medium rounded-lg border border-red-600 bg-red-600 text-white shadow-sm hover:bg-red-700 disabled:opacity-50 transition-colors"
          >
            Reject
          </button>
        )}
      </div>

      {showRejectForm && (
        <div className="w-full max-w-md flex flex-col gap-2 p-4 bg-red-50 border border-red-200 rounded-lg">
          <label className="text-sm font-medium text-red-800">Rejection Reason</label>
          <textarea
            value={rejectionReason}
            onChange={(e) => setRejectionReason(e.target.value)}
            placeholder="Enter the reason for rejecting this deal..."
            rows={3}
            className="w-full px-3 py-2 text-sm border border-red-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-red-500 focus:border-red-500 resize-none"
          />
          <div className="flex justify-end gap-2">
            <button
              type="button"
              onClick={() => { setShowRejectForm(false); setRejectionReason('') }}
              className="px-3 py-1.5 text-sm font-medium rounded-lg border border-gray-300 bg-white text-gray-700 hover:bg-gray-50 transition-colors"
            >
              Cancel
            </button>
            <button
              type="button"
              onClick={handleReject}
              disabled={isPending || !rejectionReason.trim()}
              className="px-3 py-1.5 text-sm font-medium rounded-lg border border-red-600 bg-red-600 text-white hover:bg-red-700 disabled:opacity-50 transition-colors"
            >
              Confirm Reject
            </button>
          </div>
        </div>
      )}
    </div>
  )
}
