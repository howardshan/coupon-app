'use client'

import { useCallback, useEffect, useId, useRef, useState } from 'react'
import { createPortal } from 'react-dom'
import { useRouter } from 'next/navigation'
import { toast } from 'sonner'
import { adminAdjustStoreCredit, adminSetStoreCreditBalance } from '@/app/actions/user-store-credit'
import type { StoreCreditTransactionRow } from '@/lib/store-credit-map'

export type { StoreCreditTransactionRow } from '@/lib/store-credit-map'

export default function UserStoreCreditPanel({
  userId,
  balance,
  transactions,
}: {
  userId: string
  balance: number
  transactions: StoreCreditTransactionRow[]
}) {
  const router = useRouter()
  const [addAmt, setAddAmt] = useState('')
  const [deductAmt, setDeductAmt] = useState('')
  const [setAmt, setSetAmt] = useState('')
  const [note, setNote] = useState('')
  const [busy, setBusy] = useState(false)
  const [historyOpen, setHistoryOpen] = useState(false)
  const historyBtnRef = useRef<HTMLButtonElement>(null)
  const closeHistoryRef = useRef<HTMLButtonElement>(null)
  const historyTitleId = useId()

  const refresh = () => router.refresh()

  const run = async (fn: () => Promise<void>) => {
    setBusy(true)
    try {
      await fn()
      toast.success('Updated')
      setAddAmt('')
      setDeductAmt('')
      setSetAmt('')
      refresh()
    } catch (e: unknown) {
      toast.error(e instanceof Error ? e.message : 'Failed')
    } finally {
      setBusy(false)
    }
  }

  const onAdd = () => {
    const v = Number(addAmt)
    if (!Number.isFinite(v) || v <= 0) {
      toast.error('Enter a positive amount to add')
      return
    }
    void run(() => adminAdjustStoreCredit(userId, Math.round(v * 100) / 100, note || null))
  }

  const onDeduct = () => {
    const v = Number(deductAmt)
    if (!Number.isFinite(v) || v <= 0) {
      toast.error('Enter a positive amount to deduct')
      return
    }
    void run(() => adminAdjustStoreCredit(userId, -Math.round(v * 100) / 100, note || null))
  }

  const onSet = () => {
    const v = Number(setAmt)
    if (!Number.isFinite(v) || v < 0) {
      toast.error('Enter a valid target balance (0 or more)')
      return
    }
    void run(() => adminSetStoreCreditBalance(userId, Math.round(v * 100) / 100, note || null))
  }

  const closeHistory = useCallback(() => {
    setHistoryOpen(false)
    queueMicrotask(() => historyBtnRef.current?.focus())
  }, [])

  useEffect(() => {
    if (!historyOpen) return
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') closeHistory()
    }
    document.addEventListener('keydown', onKey)
    const prev = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    queueMicrotask(() => closeHistoryRef.current?.focus())
    return () => {
      document.removeEventListener('keydown', onKey)
      document.body.style.overflow = prev
    }
  }, [historyOpen, closeHistory])

  const historyModal =
    historyOpen && typeof document !== 'undefined'
      ? createPortal(
          <div className="fixed inset-0 z-[100] flex items-center justify-center p-3 sm:p-6">
            <button
              type="button"
              className="absolute inset-0 bg-black/50"
              aria-label="Close dialog"
              onClick={closeHistory}
            />
            <div
              role="dialog"
              aria-modal="true"
              aria-labelledby={historyTitleId}
              className="relative z-[1] flex max-h-[min(90vh,800px)] w-full max-w-3xl flex-col overflow-hidden rounded-xl bg-white shadow-xl"
            >
              <div className="flex shrink-0 items-center justify-between gap-3 border-b border-gray-200 px-4 py-3">
                <h2 id={historyTitleId} className="text-base font-semibold text-gray-900">
                  Store credit history
                </h2>
                <button
                  ref={closeHistoryRef}
                  type="button"
                  onClick={closeHistory}
                  className="rounded-lg px-3 py-1.5 text-sm font-medium text-gray-700 hover:bg-gray-100"
                >
                  Close
                </button>
              </div>
              <div className="min-h-0 flex-1 overflow-auto p-3">
                {transactions.length === 0 ? (
                  <p className="text-sm text-gray-500">No transactions yet.</p>
                ) : (
                  <table className="w-full text-sm">
                    <thead className="sticky top-0 z-10 border-b border-gray-200 bg-gray-50">
                      <tr>
                        <th className="px-2 py-2 text-left font-medium text-gray-600">Date</th>
                        <th className="px-2 py-2 text-left font-medium text-gray-600">Type</th>
                        <th className="px-2 py-2 text-right font-medium text-gray-600">Amount</th>
                        <th className="px-2 py-2 text-left font-medium text-gray-600">Note</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-gray-100">
                      {transactions.map((t) => (
                        <tr key={t.id} className="hover:bg-gray-50">
                          <td className="px-2 py-2 whitespace-nowrap text-gray-600">
                            {new Date(t.created_at).toLocaleString('en-US')}
                          </td>
                          <td className="px-2 py-2 text-gray-800">{t.type}</td>
                          <td
                            className={`px-2 py-2 text-right font-medium tabular-nums ${
                              t.amount >= 0 ? 'text-green-700' : 'text-red-700'
                            }`}
                          >
                            {t.amount >= 0 ? '+' : ''}
                            ${t.amount.toFixed(2)}
                          </td>
                          <td className="px-2 py-2 text-gray-600 break-all max-w-[200px]">
                            {t.description ?? '—'}
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                )}
              </div>
            </div>
          </div>,
          document.body
        )
      : null

  return (
    <div className="bg-white rounded-lg border border-gray-200 shadow-sm p-3">
      <h2 className="text-sm font-semibold text-gray-900">Store credit</h2>
      <p className="mt-1 text-2xl font-semibold tabular-nums text-gray-900">${balance.toFixed(2)}</p>
      <p className="mt-0.5 text-xs text-gray-500">Adjust balance or set an exact amount. Optional note is stored in history.</p>

      <label className="mt-3 block text-xs font-medium text-gray-600">
        Note (optional)
        <input
          className="mt-0.5 w-full rounded-md border border-gray-300 px-2 py-1.5 text-sm"
          value={note}
          onChange={(e) => setNote(e.target.value)}
          disabled={busy}
          placeholder="Reason for adjustment"
        />
      </label>

      <div className="mt-3 flex gap-2">
        <input
          type="number"
          min="0"
          step="0.01"
          className="min-w-0 flex-1 rounded-md border border-gray-300 px-2 py-1.5 text-sm"
          value={addAmt}
          onChange={(e) => setAddAmt(e.target.value)}
          disabled={busy}
          placeholder="Add amount"
        />
        <button
          type="button"
          disabled={busy}
          onClick={onAdd}
          className="shrink-0 rounded-md bg-green-600 px-3 py-1.5 text-xs font-medium text-white hover:bg-green-700 disabled:opacity-50"
        >
          Add
        </button>
      </div>

      <div className="mt-2 flex gap-2">
        <input
          type="number"
          min="0"
          step="0.01"
          className="min-w-0 flex-1 rounded-md border border-gray-300 px-2 py-1.5 text-sm"
          value={deductAmt}
          onChange={(e) => setDeductAmt(e.target.value)}
          disabled={busy}
          placeholder="Deduct amount"
        />
        <button
          type="button"
          disabled={busy}
          onClick={onDeduct}
          className="shrink-0 rounded-md border border-red-300 px-3 py-1.5 text-xs font-medium text-red-700 hover:bg-red-50 disabled:opacity-50"
        >
          Deduct
        </button>
      </div>

      <div className="mt-2 flex gap-2">
        <input
          type="number"
          min="0"
          step="0.01"
          className="min-w-0 flex-1 rounded-md border border-gray-300 px-2 py-1.5 text-sm"
          value={setAmt}
          onChange={(e) => setSetAmt(e.target.value)}
          disabled={busy}
          placeholder="Set balance to"
        />
        <button
          type="button"
          disabled={busy}
          onClick={onSet}
          className="shrink-0 rounded-md bg-gray-900 px-3 py-1.5 text-xs font-medium text-white hover:bg-gray-800 disabled:opacity-50"
        >
          Set
        </button>
      </div>

      <button
        ref={historyBtnRef}
        type="button"
        disabled={busy}
        onClick={() => setHistoryOpen(true)}
        className="mt-3 flex w-full items-center justify-center rounded-lg border border-gray-300 px-3 py-2 text-xs font-medium text-gray-700 hover:bg-gray-50 disabled:opacity-50"
      >
        View transaction history
      </button>

      {historyModal}
    </div>
  )
}
