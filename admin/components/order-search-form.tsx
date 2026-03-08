'use client'

import { useRouter, usePathname } from 'next/navigation'
import { useState, useEffect, useRef, useTransition } from 'react'
import { useOrdersSearch } from '@/contexts/orders-search-context'

const DEBOUNCE_MS = 350

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

export default function OrderSearchForm({ initialValue = '' }: { initialValue?: string }) {
  const router = useRouter()
  const pathname = usePathname()
  const [isPending, startTransition] = useTransition()
  const ordersSearch = useOrdersSearch()
  const [value, setValue] = useState(initialValue)
  const lastPushedQRef = useRef(initialValue)

  useEffect(() => {
    if (initialValue !== lastPushedQRef.current) {
      lastPushedQRef.current = initialValue
      setValue(initialValue)
    }
  }, [initialValue])

  useEffect(() => {
    ordersSearch?.setSearching(isPending)
  }, [isPending, ordersSearch])

  useEffect(() => {
    const timer = setTimeout(() => {
      const trimmed = value.trim()
      lastPushedQRef.current = trimmed
      const url = trimmed ? `${pathname}?q=${encodeURIComponent(trimmed)}` : pathname
      startTransition(() => {
        router.replace(url)
      })
    }, DEBOUNCE_MS)
    return () => clearTimeout(timer)
  }, [value, pathname, router, startTransition])

  return (
    <div className="flex items-center gap-2">
      <input
        type="search"
        value={value}
        onChange={(e) => setValue(e.target.value)}
        placeholder="Order #, email, or deal..."
        className="px-3 py-2 border border-gray-300 rounded-lg text-sm text-gray-900 placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent min-w-[180px]"
        aria-label="Search orders by order number, email, or deal title"
      />
      {isPending && (
        <span className="flex items-center gap-1.5 text-gray-500 text-sm" aria-live="polite">
          <span className="inline-block h-4 w-4 shrink-0 overflow-visible text-gray-500">
            <SpinnerIcon size={16} />
          </span>
          Searching…
        </span>
      )}
      {!isPending && value.trim() !== '' && (
        <button
          type="button"
          onClick={() => setValue('')}
          className="px-3 py-2 text-sm font-medium text-gray-600 hover:text-gray-900 hover:bg-gray-100 rounded-lg transition-colors"
        >
          Clear
        </button>
      )}
    </div>
  )
}
