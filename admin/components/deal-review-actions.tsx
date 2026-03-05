'use client'

import { useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { toast } from 'sonner'
import { setDealActive } from '@/app/actions/admin'

interface DealReviewActionsProps {
  dealId: string
  isActive: boolean
}

export default function DealReviewActions({ dealId, isActive }: DealReviewActionsProps) {
  const router = useRouter()
  const [isPending, startTransition] = useTransition()

  function handleActivate() {
    startTransition(async () => {
      try {
        await setDealActive(dealId, true)
        toast.success('Deal is now live')
        router.refresh()
      } catch (e) {
        toast.error(e instanceof Error ? e.message : 'Action failed')
      }
    })
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

  return (
    <div className="flex items-center gap-2">
      {isActive ? (
        <button
          type="button"
          onClick={handleDeactivate}
          disabled={isPending}
          className="px-4 py-2 text-sm font-medium rounded-lg border border-amber-300 bg-amber-100 text-amber-800 shadow-sm hover:bg-amber-200 disabled:opacity-50 transition-colors"
        >
          Deactivate
        </button>
      ) : (
        <button
          type="button"
          onClick={handleActivate}
          disabled={isPending}
          className="px-4 py-2 text-sm font-medium rounded-lg border border-green-600 bg-green-600 text-white shadow-sm hover:bg-green-700 disabled:opacity-50 transition-colors"
        >
          Activate
        </button>
      )}
    </div>
  )
}
