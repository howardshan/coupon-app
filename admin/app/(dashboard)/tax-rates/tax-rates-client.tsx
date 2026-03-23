'use client'

import { useState, useTransition } from 'react'
import { upsertTaxRate, deleteTaxRate, updateMerchantMetro, bulkAssignMetroByCity } from './actions'

type TaxRate = {
  id: string
  metro_area: string
  tax_rate: number
  is_active: boolean
  created_at: string
  updated_at: string
}

type Merchant = {
  id: string
  name: string
  city: string | null
  metro_area: string | null
}

export default function TaxRatesClient({
  initialTaxRates,
  merchants,
}: {
  initialTaxRates: TaxRate[]
  merchants: Merchant[]
}) {
  const [isPending, startTransition] = useTransition()

  // 添加/编辑表单
  const [newMetro, setNewMetro] = useState('')
  const [newRate, setNewRate] = useState('')
  const [editingId, setEditingId] = useState<string | null>(null)
  const [editRate, setEditRate] = useState('')

  // 批量分配
  const [bulkCity, setBulkCity] = useState('')
  const [bulkMetro, setBulkMetro] = useState('')

  // 统计每个 metro 的 merchant 数量
  const metroCounts: Record<string, number> = {}
  for (const m of merchants) {
    if (m.metro_area) {
      metroCounts[m.metro_area] = (metroCounts[m.metro_area] ?? 0) + 1
    }
  }

  // 收集所有唯一 city
  const uniqueCities = [...new Set(merchants.map(m => m.city).filter(Boolean))] as string[]

  function handleAdd() {
    const metro = newMetro.trim()
    const rate = parseFloat(newRate)
    if (!metro || isNaN(rate) || rate < 0 || rate > 100) return
    startTransition(async () => {
      await upsertTaxRate(metro, rate / 100) // UI 输入百分比，存小数
      setNewMetro('')
      setNewRate('')
    })
  }

  function handleSaveEdit(metroArea: string) {
    const rate = parseFloat(editRate)
    if (isNaN(rate) || rate < 0 || rate > 100) return
    startTransition(async () => {
      await upsertTaxRate(metroArea, rate / 100)
      setEditingId(null)
      setEditRate('')
    })
  }

  function handleDelete(id: string, metroArea: string) {
    if (!confirm(`Delete tax rate for "${metroArea}"?`)) return
    startTransition(async () => {
      await deleteTaxRate(id)
    })
  }

  function handleMerchantMetroChange(merchantId: string, metro: string) {
    startTransition(async () => {
      await updateMerchantMetro(merchantId, metro || null)
    })
  }

  function handleBulkAssign() {
    if (!bulkCity || !bulkMetro) return
    const count = merchants.filter(m => m.city?.toLowerCase() === bulkCity.toLowerCase()).length
    if (!confirm(`Assign "${bulkMetro}" metro to all ${count} merchants in "${bulkCity}"?`)) return
    startTransition(async () => {
      await bulkAssignMetroByCity(bulkCity, bulkMetro)
      setBulkCity('')
      setBulkMetro('')
    })
  }

  return (
    <div>
      <h1 className="text-2xl font-bold text-gray-900 mb-6">Tax Rates by Metro</h1>

      {isPending && (
        <div className="mb-4 text-sm text-blue-600">Updating…</div>
      )}

      {/* 添加新 Metro 税率 */}
      <div className="bg-white rounded-xl border border-gray-200 p-6 mb-6">
        <h2 className="text-base font-semibold text-gray-800 mb-4">Add Metro Tax Rate</h2>
        <div className="flex items-end gap-3 flex-wrap">
          <label className="flex flex-col gap-1">
            <span className="text-sm text-gray-600">Metro Area</span>
            <input
              type="text"
              value={newMetro}
              onChange={e => setNewMetro(e.target.value)}
              placeholder="e.g. Dallas"
              className="px-3 py-2 border border-gray-300 rounded-lg min-w-[200px]"
            />
          </label>
          <label className="flex flex-col gap-1">
            <span className="text-sm text-gray-600">Tax Rate (%)</span>
            <input
              type="number"
              step="0.01"
              min="0"
              max="100"
              value={newRate}
              onChange={e => setNewRate(e.target.value)}
              placeholder="8.25"
              className="px-3 py-2 border border-gray-300 rounded-lg w-28"
            />
          </label>
          <button
            onClick={handleAdd}
            disabled={isPending || !newMetro.trim() || !newRate}
            className="px-4 py-2 bg-blue-600 text-white rounded-lg text-sm font-medium hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            Add
          </button>
        </div>
      </div>

      {/* 税率列表 */}
      <div className="bg-white rounded-xl border border-gray-200 overflow-hidden mb-6">
        <table className="w-full text-sm">
          <thead className="bg-gray-50 border-b border-gray-200">
            <tr>
              <th className="text-left px-4 py-3 font-medium text-gray-600">Metro Area</th>
              <th className="text-left px-4 py-3 font-medium text-gray-600">Tax Rate</th>
              <th className="text-left px-4 py-3 font-medium text-gray-600">Merchants</th>
              <th className="text-left px-4 py-3 font-medium text-gray-600">Updated</th>
              <th className="text-left px-4 py-3 font-medium text-gray-600">Actions</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100">
            {initialTaxRates.map(tr => (
              <tr key={tr.id} className="hover:bg-gray-50">
                <td className="px-4 py-3 font-medium text-gray-900">{tr.metro_area}</td>
                <td className="px-4 py-3 text-gray-700">
                  {editingId === tr.id ? (
                    <div className="flex items-center gap-2">
                      <input
                        type="number"
                        step="0.01"
                        min="0"
                        max="100"
                        value={editRate}
                        onChange={e => setEditRate(e.target.value)}
                        className="px-2 py-1 border border-gray-300 rounded w-20 text-sm"
                        autoFocus
                      />
                      <span className="text-gray-500">%</span>
                    </div>
                  ) : (
                    <span>{(tr.tax_rate * 100).toFixed(2)}%</span>
                  )}
                </td>
                <td className="px-4 py-3 text-gray-500">{metroCounts[tr.metro_area] ?? 0}</td>
                <td className="px-4 py-3 text-gray-400 text-xs">
                  {new Date(tr.updated_at).toLocaleDateString('en-US')}
                </td>
                <td className="px-4 py-3">
                  <div className="flex items-center gap-2">
                    {editingId === tr.id ? (
                      <>
                        <button
                          onClick={() => handleSaveEdit(tr.metro_area)}
                          disabled={isPending}
                          className="text-xs text-blue-600 hover:underline disabled:opacity-50"
                        >
                          Save
                        </button>
                        <button
                          onClick={() => { setEditingId(null); setEditRate('') }}
                          className="text-xs text-gray-500 hover:underline"
                        >
                          Cancel
                        </button>
                      </>
                    ) : (
                      <>
                        <button
                          onClick={() => {
                            setEditingId(tr.id)
                            setEditRate((tr.tax_rate * 100).toFixed(2))
                          }}
                          className="text-xs text-blue-600 hover:underline"
                        >
                          Edit
                        </button>
                        <button
                          onClick={() => handleDelete(tr.id, tr.metro_area)}
                          disabled={isPending}
                          className="text-xs text-red-600 hover:underline disabled:opacity-50"
                        >
                          Delete
                        </button>
                      </>
                    )}
                  </div>
                </td>
              </tr>
            ))}
            {initialTaxRates.length === 0 && (
              <tr>
                <td colSpan={5} className="px-4 py-8 text-center text-gray-400">
                  No tax rates configured yet
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      {/* 批量分配 Metro */}
      <div className="bg-white rounded-xl border border-gray-200 p-6 mb-6">
        <h2 className="text-base font-semibold text-gray-800 mb-4">Bulk Assign Metro by City</h2>
        <p className="text-sm text-gray-500 mb-4">
          Assign a metro area to all merchants in a specific city at once.
        </p>
        <div className="flex items-end gap-3 flex-wrap">
          <label className="flex flex-col gap-1">
            <span className="text-sm text-gray-600">City</span>
            <select
              value={bulkCity}
              onChange={e => setBulkCity(e.target.value)}
              className="px-3 py-2 border border-gray-300 rounded-lg bg-white min-w-[160px]"
            >
              <option value="">Select city</option>
              {uniqueCities.map(c => (
                <option key={c} value={c}>{c}</option>
              ))}
            </select>
          </label>
          <label className="flex flex-col gap-1">
            <span className="text-sm text-gray-600">Metro Area</span>
            <select
              value={bulkMetro}
              onChange={e => setBulkMetro(e.target.value)}
              className="px-3 py-2 border border-gray-300 rounded-lg bg-white min-w-[160px]"
            >
              <option value="">Select metro</option>
              {initialTaxRates.map(tr => (
                <option key={tr.id} value={tr.metro_area}>{tr.metro_area}</option>
              ))}
            </select>
          </label>
          <button
            onClick={handleBulkAssign}
            disabled={isPending || !bulkCity || !bulkMetro}
            className="px-4 py-2 bg-gray-800 text-white rounded-lg text-sm font-medium hover:bg-gray-900 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            Assign All
          </button>
        </div>
      </div>

      {/* Merchant Metro 分配表格 */}
      <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
        <div className="px-4 py-3 border-b border-gray-200 bg-gray-50">
          <h2 className="text-base font-semibold text-gray-800">Merchant Metro Assignments</h2>
          <p className="text-xs text-gray-500 mt-0.5">
            Each merchant&apos;s metro determines which tax rate applies at checkout.
          </p>
        </div>
        <table className="w-full text-sm">
          <thead className="bg-gray-50 border-b border-gray-200">
            <tr>
              <th className="text-left px-4 py-3 font-medium text-gray-600">Merchant</th>
              <th className="text-left px-4 py-3 font-medium text-gray-600">City</th>
              <th className="text-left px-4 py-3 font-medium text-gray-600">Metro Area</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100">
            {merchants.map(m => (
              <tr key={m.id} className="hover:bg-gray-50">
                <td className="px-4 py-3 font-medium text-gray-900">{m.name}</td>
                <td className="px-4 py-3 text-gray-600">{m.city ?? '—'}</td>
                <td className="px-4 py-3">
                  <select
                    value={m.metro_area ?? ''}
                    onChange={e => handleMerchantMetroChange(m.id, e.target.value)}
                    className={`px-2 py-1 border rounded-lg text-sm ${
                      m.metro_area
                        ? 'border-gray-300 bg-white'
                        : 'border-orange-300 bg-orange-50 text-orange-700'
                    }`}
                  >
                    <option value="">Not assigned</option>
                    {initialTaxRates.map(tr => (
                      <option key={tr.id} value={tr.metro_area}>{tr.metro_area}</option>
                    ))}
                  </select>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  )
}
