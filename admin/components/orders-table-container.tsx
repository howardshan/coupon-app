'use client'

import { useOrdersSearch } from '@/contexts/orders-search-context'
import { useState, useEffect } from 'react'
import type { ReactNode } from 'react'

function SpinnerIcon({ className, size = 24 }: { className?: string; size?: number }) {
  const [angle, setAngle] = useState(0)
  useEffect(() => {
    let rafId: number
    const tick = () => {
      setAngle((a) => (a + 6) % 360)
      rafId = requestAnimationFrame(tick)
    }
    rafId = requestAnimationFrame(tick)
    return () => cancelAnimationFrame(rafId)
  }, [])
  return (
    <svg
      className={className}
      width={size}
      height={size}
      style={{ display: 'block', transform: `rotate(${angle}deg)` }}
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
      aria-hidden
    >
      <circle
        cx="12"
        cy="12"
        r="10"
        stroke="#6b7280"
        strokeWidth="3"
        strokeLinecap="round"
        strokeDasharray="31.4 31.4"
        strokeDashoffset="10"
      />
    </svg>
  )
}

export default function OrdersTableContainer({ children }: { children: ReactNode }) {
  const ordersSearch = useOrdersSearch()
  const isSearching = ordersSearch?.isSearching ?? false

  return (
    <>
      <div className="relative max-h-[70vh] w-full max-w-full min-w-0 overflow-auto">
        {children}
      </div>
      {isSearching && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-white/80 backdrop-blur-[2px]"
          aria-live="polite"
          aria-busy="true"
        >
          <div className="flex flex-col items-center justify-center gap-3 rounded-xl border border-gray-200 bg-white px-6 py-5 shadow-lg">
            <span className="inline-block h-8 w-8 shrink-0 overflow-visible text-gray-500">
              <SpinnerIcon size={32} />
            </span>
            <span className="shrink-0 text-sm font-medium text-gray-600">Searching orders…</span>
          </div>
        </div>
      )}
    </>
  )
}
