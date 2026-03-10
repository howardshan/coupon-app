'use client'

import { useState, useTransition } from 'react'
import { toast } from 'sonner'
import { addStoreToBrand } from '@/app/actions/brands'

interface Store {
  id: string
  name: string
  category: string | null
  address: string | null
}

export default function AddStoreToBrand({
  brandId,
  availableStores,
}: {
  brandId: string
  availableStores: Store[]
}) {
  const [selectedId, setSelectedId] = useState('')
  const [isPending, startTransition] = useTransition()

  function handleAdd() {
    if (!selectedId) return

    startTransition(async () => {
      try {
        await addStoreToBrand(brandId, selectedId)
        setSelectedId('')
        toast.success('Store added to brand')
      } catch (err: any) {
        toast.error(err.message || 'Failed to add store')
      }
    })
  }

  if (availableStores.length === 0) return null

  return (
    <div className="flex items-end gap-2">
      <div>
        <label className="block text-xs text-gray-500 mb-1">Add Store</label>
        <select
          value={selectedId}
          onChange={e => setSelectedId(e.target.value)}
          className="px-3 py-1.5 text-sm border border-gray-300 rounded-lg bg-white focus:ring-2 focus:ring-blue-500 outline-none min-w-[200px]"
        >
          <option value="">Select a store...</option>
          {availableStores.map(s => (
            <option key={s.id} value={s.id}>
              {s.name} ({s.category || 'N/A'})
            </option>
          ))}
        </select>
      </div>
      <button
        onClick={handleAdd}
        disabled={isPending || !selectedId}
        className="px-3 py-1.5 text-sm font-medium rounded-lg bg-blue-600 text-white hover:bg-blue-700 disabled:opacity-50 transition-colors"
      >
        {isPending ? 'Adding...' : 'Add'}
      </button>
    </div>
  )
}
