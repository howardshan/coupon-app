'use client'

import { useRouter, usePathname } from 'next/navigation'
import { useState, useEffect, useRef } from 'react'

const DEBOUNCE_MS = 350

export default function OrderSearchForm({ initialValue = '' }: { initialValue?: string }) {
  const router = useRouter()
  const pathname = usePathname()
  const [value, setValue] = useState(initialValue)
  // 仅当 URL 被“外部”修改（如后退/前进）时才用 initialValue 覆盖输入，避免防抖触发的重渲染用旧 q 覆盖当前输入
  const lastPushedQRef = useRef(initialValue)

  useEffect(() => {
    if (initialValue !== lastPushedQRef.current) {
      lastPushedQRef.current = initialValue
      setValue(initialValue)
    }
  }, [initialValue])

  useEffect(() => {
    const timer = setTimeout(() => {
      const trimmed = value.trim()
      lastPushedQRef.current = trimmed
      const url = trimmed ? `${pathname}?q=${encodeURIComponent(trimmed)}` : pathname
      router.replace(url)
    }, DEBOUNCE_MS)
    return () => clearTimeout(timer)
  }, [value, pathname, router])

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
      {value.trim() !== '' && (
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
