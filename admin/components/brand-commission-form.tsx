'use client'

import { useState, useTransition } from 'react'
import { toast } from 'sonner'
import { updateBrandCommissionRate } from '@/app/actions/brands'

interface Props {
  brandId: string
  currentRate: number | null  // 数据库存的小数，如 0.15
}

export default function BrandCommissionForm({ brandId, currentRate }: Props) {
  // 转为百分比展示（如 15）
  const [rate, setRate] = useState(
    currentRate !== null ? String(Math.round(currentRate * 10000) / 100) : ''
  )
  const [isPending, startTransition] = useTransition()

  function handleSave() {
    const numRate = rate.trim() ? parseFloat(rate) : 0
    if (isNaN(numRate) || numRate < 0 || numRate > 50) {
      toast.error('Rate must be between 0% and 50%')
      return
    }

    startTransition(async () => {
      try {
        await updateBrandCommissionRate(brandId, numRate)
        toast.success('Brand commission rate saved')
      } catch (e) {
        toast.error((e as Error).message)
      }
    })
  }

  return (
    <div className="flex flex-wrap items-end gap-3">
      <div>
        <label className="block text-xs font-medium text-gray-700 mb-1">Commission Rate</label>
        <div className="flex items-center gap-1">
          <input
            type="number"
            min={0}
            max={50}
            step={0.5}
            placeholder="0"
            value={rate}
            onChange={e => setRate(e.target.value)}
            className="w-24 px-2 py-1.5 text-sm border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500 placeholder:text-gray-300"
          />
          <span className="text-sm text-gray-400">%</span>
        </div>
        <p className="text-xs text-gray-400 mt-1">
          {currentRate !== null && currentRate > 0
            ? `Current: ${(currentRate * 100).toFixed(1)}% — brand earns this from each redeemed voucher`
            : 'Set to 0 or leave empty to disable brand commission'}
        </p>
      </div>
      <button
        onClick={handleSave}
        disabled={isPending}
        className="px-4 py-1.5 text-sm font-semibold rounded-lg bg-blue-600 text-white hover:bg-blue-700 disabled:opacity-50 transition-colors"
      >
        {isPending ? 'Saving…' : 'Save'}
      </button>
    </div>
  )
}
