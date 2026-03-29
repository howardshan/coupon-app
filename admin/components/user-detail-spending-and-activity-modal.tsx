'use client'

import { useCallback, useEffect, useId, useRef, useState } from 'react'
import { createPortal } from 'react-dom'
import UserDetailActivityTabs from '@/components/user-detail-activity-tabs'
import type { ComponentProps } from 'react'

type TabProps = ComponentProps<typeof UserDetailActivityTabs>

export default function UserDetailSpendingAndActivityModal({
  totalOrders,
  totalSpent,
  avgOrder,
  activeCoupons,
  usedCoupons,
  orders,
  coupons,
}: {
  totalOrders: number
  totalSpent: number
  avgOrder: number
  activeCoupons: number
  usedCoupons: number
  orders: TabProps['orders']
  coupons: TabProps['coupons']
}) {
  const [open, setOpen] = useState(false)
  const openBtnRef = useRef<HTMLButtonElement>(null)
  const closeBtnRef = useRef<HTMLButtonElement>(null)
  const titleId = useId()

  const close = useCallback(() => {
    setOpen(false)
    queueMicrotask(() => openBtnRef.current?.focus())
  }, [])

  useEffect(() => {
    if (!open) return
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') close()
    }
    document.addEventListener('keydown', onKey)
    const prevOverflow = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    queueMicrotask(() => closeBtnRef.current?.focus())
    return () => {
      document.removeEventListener('keydown', onKey)
      document.body.style.overflow = prevOverflow
    }
  }, [open, close])

  const modal =
    open && typeof document !== 'undefined'
      ? createPortal(
          <div className="fixed inset-0 z-[100] flex items-center justify-center p-3 sm:p-6">
            <button
              type="button"
              className="absolute inset-0 bg-black/50"
              aria-label="Close dialog"
              onClick={close}
            />
            <div
              role="dialog"
              aria-modal="true"
              aria-labelledby={titleId}
              className="relative z-[1] flex max-h-[min(92vh,920px)] w-full max-w-5xl flex-col overflow-hidden rounded-xl bg-white shadow-xl"
            >
              <div className="flex shrink-0 items-center justify-between gap-3 border-b border-gray-200 px-4 py-3">
                <h2 id={titleId} className="text-base font-semibold text-gray-900">
                  Purchase history & coupon records
                </h2>
                <button
                  ref={closeBtnRef}
                  type="button"
                  onClick={close}
                  className="rounded-lg px-3 py-1.5 text-sm font-medium text-gray-700 hover:bg-gray-100"
                >
                  Close
                </button>
              </div>
              <div className="min-h-0 flex-1 overflow-y-auto p-3">
                <UserDetailActivityTabs
                  orders={orders}
                  coupons={coupons}
                  className="rounded-lg shadow-sm"
                />
              </div>
            </div>
          </div>,
          document.body
        )
      : null

  return (
    <div className="bg-white rounded-lg border border-gray-200 shadow-sm p-3">
      <h2 className="text-sm font-semibold text-gray-900">Spending summary</h2>
      <ul className="mt-2 space-y-2 text-sm">
        <li className="flex justify-between gap-2 text-gray-600">
          <span>Orders (loaded)</span>
          <span className="font-medium text-gray-900 tabular-nums">{totalOrders}</span>
        </li>
        <li className="flex justify-between gap-2 text-gray-600">
          <span>Total spent</span>
          <span className="font-medium text-gray-900 tabular-nums">${totalSpent.toFixed(2)}</span>
        </li>
        <li className="flex justify-between gap-2 text-gray-600">
          <span>Avg. order</span>
          <span className="font-medium text-gray-900 tabular-nums">${avgOrder.toFixed(2)}</span>
        </li>
        <li className="flex justify-between gap-2 text-gray-600">
          <span>Active / used coupons</span>
          <span className="font-medium text-gray-900 tabular-nums">
            {activeCoupons} / {usedCoupons}
          </span>
        </li>
      </ul>
      <button
        ref={openBtnRef}
        type="button"
        onClick={() => setOpen(true)}
        className="mt-3 flex w-full items-center justify-center rounded-lg border border-gray-300 px-3 py-2 text-xs font-medium text-gray-700 hover:bg-gray-50"
      >
        View purchase & coupons
      </button>
      {modal}
    </div>
  )
}
