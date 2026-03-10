'use client'

import { useTransition } from 'react'
import { toast } from 'sonner'
import { removeBrandAdmin } from '@/app/actions/brands'

export default function RemoveBrandAdminButton({
  brandAdminId,
  brandId,
  userName,
}: {
  brandAdminId: string
  brandId: string
  userName: string
}) {
  const [isPending, startTransition] = useTransition()

  function handleRemove() {
    if (!confirm(`Remove ${userName} from brand admins?`)) return

    startTransition(async () => {
      try {
        await removeBrandAdmin(brandAdminId, brandId)
        toast.success('Admin removed')
      } catch (err: any) {
        toast.error(err.message || 'Failed to remove admin')
      }
    })
  }

  return (
    <button
      onClick={handleRemove}
      disabled={isPending}
      className="text-xs text-red-600 hover:text-red-800 disabled:opacity-50"
    >
      {isPending ? 'Removing...' : 'Remove'}
    </button>
  )
}
