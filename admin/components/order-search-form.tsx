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

type OrderSearchFormProps = {
  initialValue?: string
  /** 若提供，则走局部搜索：只回调不跳转，不整页刷新 */
  onSearch?: (q: string) => void
  /** 局部搜索时的 loading 状态（由父组件传入） */
  isSearching?: boolean
  /** 占满父容器宽度（用于订单页标题下方通栏搜索） */
  fullWidth?: boolean
}

export default function OrderSearchForm({
  initialValue = '',
  onSearch,
  isSearching: isSearchingProp,
  fullWidth = false,
}: OrderSearchFormProps) {
  const router = useRouter()
  const pathname = usePathname()
  const [urlPending, startTransition] = useTransition()
  const ordersSearch = useOrdersSearch()
  const [value, setValue] = useState(initialValue)
  const lastPushedQRef = useRef(initialValue)

  const isPending = onSearch ? isSearchingProp ?? false : urlPending

  useEffect(() => {
    if (initialValue !== lastPushedQRef.current) {
      lastPushedQRef.current = initialValue
      setValue(initialValue)
    }
  }, [initialValue])

  // 仅 URL 搜索时同步 context，避免局部搜索时出现全屏遮罩
  useEffect(() => {
    if (!onSearch) ordersSearch?.setSearching(isPending)
  }, [isPending, ordersSearch, onSearch])

  useEffect(() => {
    const timer = setTimeout(() => {
      const trimmed = value.trim()
      lastPushedQRef.current = trimmed
      if (onSearch) {
        onSearch(trimmed)
      } else {
        const url = trimmed ? `${pathname}?q=${encodeURIComponent(trimmed)}` : pathname
        startTransition(() => {
          router.replace(url)
        })
      }
    }, DEBOUNCE_MS)
    return () => clearTimeout(timer)
  }, [value, pathname, router, startTransition, onSearch])

  return (
    <div
      className={
        fullWidth
          ? 'flex w-full min-w-0 flex-wrap items-center gap-2'
          : 'flex items-center gap-2'
      }
    >
      <input
        type="search"
        value={value}
        onChange={(e) => setValue(e.target.value)}
        placeholder="Order #, email, or deal..."
        className={
          fullWidth
            ? 'min-w-0 flex-1 px-3 py-2 border border-gray-300 rounded-lg text-sm text-gray-900 placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent'
            : 'min-w-[180px] px-3 py-2 border border-gray-300 rounded-lg text-sm text-gray-900 placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent'
        }
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
