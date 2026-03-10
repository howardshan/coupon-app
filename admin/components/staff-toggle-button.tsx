'use client'

import { useState } from 'react'
import { toggleStaffActive } from '@/app/actions/brands'

export default function StaffToggleButton({ staffId, isActive }: { staffId: string; isActive: boolean }) {
  const [loading, setLoading] = useState(false)

  async function handleToggle() {
    setLoading(true)
    try {
      await toggleStaffActive(staffId, !isActive)
      // 页面会通过 revalidatePath 自动刷新
    } catch (e) {
      alert(e instanceof Error ? e.message : 'Failed')
    } finally {
      setLoading(false)
    }
  }

  return (
    <button
      onClick={handleToggle}
      disabled={loading}
      className={`px-2 py-1 rounded text-xs font-medium transition-colors ${
        isActive
          ? 'border border-red-200 bg-red-50 text-red-700 hover:bg-red-100'
          : 'border border-green-200 bg-green-50 text-green-700 hover:bg-green-100'
      } disabled:opacity-50`}
    >
      {loading ? '...' : isActive ? 'Disable' : 'Enable'}
    </button>
  )
}
