'use client'

import { useTransition } from 'react'
import { toast } from 'sonner'
import { removeStoreFromBrand } from '@/app/actions/brands'

export default function RemoveStoreButton({
  merchantId,
  brandId,
  storeName,
}: {
  merchantId: string
  brandId: string
  storeName: string
}) {
  const [isPending, startTransition] = useTransition()

  function handleRemove() {
    if (!confirm(`Remove "${storeName}" from this brand?`)) return

    startTransition(async () => {
      try {
        await removeStoreFromBrand(merchantId, brandId)
        toast.success('Store removed from brand')
      } catch (err: any) {
        toast.error(err.message || 'Failed to remove store')
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
