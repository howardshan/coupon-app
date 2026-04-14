'use client'

import { useRouter } from 'next/navigation'
import { useTransition, useState } from 'react'
import type { TaxRevenueRow } from '@/app/actions/tax-revenue'
import { exportTaxRevenueCsv } from '@/app/actions/tax-revenue'

type Totals = {
  redeemedCount: number
  grossRevenue: number
  taxCollected: number
  platformCommission: number
  brandCommission: number
  stripeFee: number
  netToMerchants: number
}

type Props = {
  yearMonth: string
  rows: TaxRevenueRow[]
  totals: Totals
  errorMessage?: string
}

// 生成过去 12 个月的选项
function monthOptions(): { value: string; label: string }[] {
  const opts: { value: string; label: string }[] = []
  const now = new Date()
  for (let i = 0; i < 12; i++) {
    const d = new Date(now.getFullYear(), now.getMonth() - i, 1)
    const value = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`
    const label = d.toLocaleDateString('en-US', { year: 'numeric', month: 'long' })
    opts.push({ value, label })
  }
  return opts
}

function fmt(n: number): string {
  return `$${n.toFixed(2)}`
}

export default function TaxRevenueTable({ yearMonth, rows, totals, errorMessage }: Props) {
  const router = useRouter()
  const [isPending, startTransition] = useTransition()
  const [exporting, setExporting] = useState(false)

  const handleMonthChange = (value: string) => {
    startTransition(() => {
      router.push(`/finance/tax-revenue?month=${value}`)
    })
  }

  const handleExport = async () => {
    setExporting(true)
    try {
      const result = await exportTaxRevenueCsv(yearMonth)
      if (result.error || !result.csv) {
        alert(`Export failed: ${result.error ?? 'Unknown'}`)
        return
      }
      const blob = new Blob([result.csv], { type: 'text/csv;charset=utf-8;' })
      const url = URL.createObjectURL(blob)
      const a = document.createElement('a')
      a.href = url
      a.download = result.filename ?? `tax-revenue-${yearMonth}.csv`
      document.body.appendChild(a)
      a.click()
      document.body.removeChild(a)
      URL.revokeObjectURL(url)
    } finally {
      setExporting(false)
    }
  }

  return (
    <div>
      <div className="flex items-center justify-between mb-4">
        <div className="flex items-center gap-3">
          <label className="text-sm text-gray-600">Month:</label>
          <select
            value={yearMonth}
            onChange={(e) => handleMonthChange(e.target.value)}
            disabled={isPending}
            className="border border-gray-300 rounded-md px-3 py-1.5 text-sm"
          >
            {monthOptions().map((opt) => (
              <option key={opt.value} value={opt.value}>
                {opt.label}
              </option>
            ))}
          </select>
        </div>
        <button
          onClick={handleExport}
          disabled={exporting || rows.length === 0}
          className="bg-blue-600 hover:bg-blue-700 disabled:bg-gray-300 text-white text-sm font-medium px-4 py-1.5 rounded-md"
        >
          {exporting ? 'Exporting...' : 'Export CSV'}
        </button>
      </div>

      {errorMessage && (
        <div className="mb-4 p-3 bg-red-50 border border-red-200 text-red-700 text-sm rounded">
          {errorMessage}
        </div>
      )}

      <div className="bg-white rounded-lg shadow overflow-x-auto">
        <table className="min-w-full divide-y divide-gray-200 text-sm">
          <thead className="bg-gray-50">
            <tr>
              <th className="px-4 py-3 text-left font-semibold text-gray-700">City (Metro)</th>
              <th className="px-4 py-3 text-right font-semibold text-gray-700">Redeemed</th>
              <th className="px-4 py-3 text-right font-semibold text-gray-700">Gross Revenue</th>
              <th className="px-4 py-3 text-right font-semibold text-gray-700">Tax Collected</th>
              <th className="px-4 py-3 text-right font-semibold text-gray-700">Platform Commission</th>
              <th className="px-4 py-3 text-right font-semibold text-gray-700">Brand Commission</th>
              <th className="px-4 py-3 text-right font-semibold text-gray-700">Stripe Fee</th>
              <th className="px-4 py-3 text-right font-semibold text-gray-700">Net to Merchants</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-200">
            {rows.length === 0 && (
              <tr>
                <td colSpan={8} className="px-4 py-10 text-center text-gray-400">
                  No redeemed vouchers for this month.
                </td>
              </tr>
            )}
            {rows.map((row) => (
              <tr key={row.metroArea} className="hover:bg-gray-50">
                <td className="px-4 py-3 font-medium text-gray-900">{row.metroArea}</td>
                <td className="px-4 py-3 text-right">{row.redeemedCount}</td>
                <td className="px-4 py-3 text-right">{fmt(row.grossRevenue)}</td>
                <td className="px-4 py-3 text-right font-semibold text-blue-700">
                  {fmt(row.taxCollected)}
                </td>
                <td className="px-4 py-3 text-right">{fmt(row.platformCommission)}</td>
                <td className="px-4 py-3 text-right">{fmt(row.brandCommission)}</td>
                <td className="px-4 py-3 text-right">{fmt(row.stripeFee)}</td>
                <td className="px-4 py-3 text-right text-green-700">{fmt(row.netToMerchants)}</td>
              </tr>
            ))}
          </tbody>
          {rows.length > 0 && (
            <tfoot className="bg-gray-50 border-t-2 border-gray-200">
              <tr className="font-semibold">
                <td className="px-4 py-3 text-gray-900">TOTAL</td>
                <td className="px-4 py-3 text-right">{totals.redeemedCount}</td>
                <td className="px-4 py-3 text-right">{fmt(totals.grossRevenue)}</td>
                <td className="px-4 py-3 text-right text-blue-700">{fmt(totals.taxCollected)}</td>
                <td className="px-4 py-3 text-right">{fmt(totals.platformCommission)}</td>
                <td className="px-4 py-3 text-right">{fmt(totals.brandCommission)}</td>
                <td className="px-4 py-3 text-right">{fmt(totals.stripeFee)}</td>
                <td className="px-4 py-3 text-right text-green-700">{fmt(totals.netToMerchants)}</td>
              </tr>
            </tfoot>
          )}
        </table>
      </div>
    </div>
  )
}
