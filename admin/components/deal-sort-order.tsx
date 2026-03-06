'use client'

import { useState, useTransition } from 'react'
import { updateDealSortOrder } from '@/app/actions/admin'

interface DealSortOrderProps {
  dealId: string
  sortOrder: number | null
}

export default function DealSortOrder({ dealId, sortOrder }: DealSortOrderProps) {
  const [editing, setEditing] = useState(false)
  const [value, setValue] = useState(sortOrder?.toString() ?? '')
  const [isPending, startTransition] = useTransition()

  function handleSave() {
    const parsed = value.trim() === '' ? null : parseInt(value, 10)
    if (parsed !== null && isNaN(parsed)) return

    startTransition(async () => {
      try {
        await updateDealSortOrder(dealId, parsed)
        setEditing(false)
      } catch {
        // 静默失败
      }
    })
  }

  if (editing) {
    return (
      <div className="flex items-center gap-1">
        <input
          type="number"
          value={value}
          onChange={(e) => setValue(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter') handleSave()
            if (e.key === 'Escape') setEditing(false)
          }}
          className="w-16 px-2 py-1 text-sm border border-gray-300 rounded focus:outline-none focus:ring-1 focus:ring-blue-500"
          placeholder="—"
          autoFocus
          disabled={isPending}
        />
        <button
          onClick={handleSave}
          disabled={isPending}
          className="px-2 py-1 text-xs font-medium rounded bg-blue-600 text-white hover:bg-blue-700 disabled:opacity-50"
        >
          OK
        </button>
        <button
          onClick={() => { setEditing(false); setValue(sortOrder?.toString() ?? '') }}
          className="px-2 py-1 text-xs font-medium rounded border border-gray-300 text-gray-600 hover:bg-gray-100"
        >
          X
        </button>
      </div>
    )
  }

  return (
    <button
      onClick={() => setEditing(true)}
      className="inline-flex items-center gap-1 px-2 py-1 text-sm rounded hover:bg-gray-100 transition-colors"
      title="Click to edit sort order"
    >
      {sortOrder != null ? (
        <span className="font-medium text-blue-600">{sortOrder}</span>
      ) : (
        <span className="text-gray-400">—</span>
      )}
      <svg className="w-3 h-3 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15.232 5.232l3.536 3.536m-2.036-5.036a2.5 2.5 0 113.536 3.536L6.5 21.036H3v-3.572L16.732 3.732z" />
      </svg>
    </button>
  )
}
