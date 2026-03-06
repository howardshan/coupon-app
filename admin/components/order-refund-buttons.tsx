'use client'

import { useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { approveRefund, rejectRefund } from '@/app/actions/orders'
import { toast } from 'sonner'

const STATUS_STYLES: Record<string, string> = {
  unused: 'bg-blue-100 text-blue-700',
  used: 'bg-gray-100 text-gray-600',
  refunded: 'bg-purple-100 text-purple-700',
  refund_requested: 'bg-orange-100 text-orange-700',
  expired: 'bg-red-100 text-red-700',
}

const STATUS_LABELS: Record<string, string> = {
  unused: 'Unused',
  used: 'Used',
  refunded: 'Refunded',
  refund_requested: 'Refund Requested',
  expired: 'Expired',
}

export default function OrderRefundButtons({
  orderId,
  initialStatus,
}: {
  orderId: string
  initialStatus: string
}) {
  const router = useRouter()
  const [status, setStatus] = useState(initialStatus)
  const [isPending, startTransition] = useTransition()

  if (status !== 'refund_requested') {
    return (
      <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${STATUS_STYLES[status] ?? STATUS_STYLES.used}`}>
        {STATUS_LABELS[status] ?? status}
      </span>
    )
  }

  function handle(action: 'approve' | 'reject') {
    startTransition(async () => {
      try {
        if (action === 'approve') {
          await approveRefund(orderId)
          setStatus('refunded')
          toast.success('Refund approved')
        } else {
          await rejectRefund(orderId)
          setStatus('used')
          toast.success('Refund rejected')
        }
        router.refresh()
      } catch (e) {
        toast.error(e instanceof Error ? e.message : 'Action failed')
      }
    })
  }

  return (
    <div className="flex items-center gap-2">
      <span className="text-xs text-orange-600 font-medium">Refund Req.</span>
      <button
        type="button"
        onClick={() => handle('approve')}
        disabled={isPending}
        className="px-2 py-1 text-xs font-medium bg-green-600 text-white rounded-lg hover:bg-green-700 disabled:opacity-50 transition-colors"
      >
        Approve
      </button>
      <button
        type="button"
        onClick={() => handle('reject')}
        disabled={isPending}
        className="px-2 py-1 text-xs font-medium bg-red-100 text-red-700 rounded-lg hover:bg-red-200 disabled:opacity-50 transition-colors"
      >
        Reject
      </button>
    </div>
  )
}
