'use client'

import { useState, useTransition } from 'react'
import { approveMerchant, rejectMerchant } from '@/app/actions/admin'

interface MerchantActionButtonsProps {
  merchantId: string
  merchantUserId: string
  status: string
}

export default function MerchantActionButtons({
  merchantId,
  merchantUserId,
  status: initialStatus,
}: MerchantActionButtonsProps) {
  const [status, setStatus] = useState(initialStatus)
  const [isPending, startTransition] = useTransition()
  const [error, setError] = useState('')

  if (status !== 'pending') {
    const styles: Record<string, string> = {
      approved: 'text-green-700 bg-green-50',
      rejected: 'text-red-700 bg-red-50',
    }
    return (
      <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${styles[status] ?? 'bg-gray-100 text-gray-600'}`}>
        {status}
      </span>
    )
  }

  function handleApprove() {
    setError('')
    startTransition(async () => {
      try {
        await approveMerchant(merchantId, merchantUserId)
        setStatus('approved')
      } catch {
        setError('Failed')
      }
    })
  }

  function handleReject() {
    setError('')
    startTransition(async () => {
      try {
        await rejectMerchant(merchantId)
        setStatus('rejected')
      } catch {
        setError('Failed')
      }
    })
  }

  return (
    <div className="flex items-center gap-2">
      <button
        onClick={handleApprove}
        disabled={isPending}
        className="px-3 py-1 text-xs font-medium rounded-lg bg-green-600 text-white hover:bg-green-700 disabled:opacity-50 transition-colors"
      >
        Approve
      </button>
      <button
        onClick={handleReject}
        disabled={isPending}
        className="px-3 py-1 text-xs font-medium rounded-lg bg-red-100 text-red-700 hover:bg-red-200 disabled:opacity-50 transition-colors"
      >
        Reject
      </button>
      {error && <span className="text-xs text-red-500">{error}</span>}
    </div>
  )
}
