'use client'

import { useRouter, usePathname } from 'next/navigation'
import { useState, useEffect, useRef, useTransition } from 'react'
import AdminSpinnerIcon from '@/components/admin-spinner-icon'

const DEBOUNCE_MS = 350

type AdminDebouncedSearchFormProps = {
  initialValue?: string
  /**
   * 受控 URL 更新：防抖后调用；由父组件在 startTransition 内 router.replace。
   * 若提供则不走内置 pathname?q 跳转。
   */
  onQueryChange?: (q: string) => void
  /** 与 onQueryChange 配套：父级 transition pending */
  isQueryPending?: boolean
  fullWidth?: boolean
  placeholder?: string
  ariaLabel?: string
  /** 输入框旁短文案 */
  inlineLoadingText?: string
}

/**
 * 后台列表页通用防抖搜索：支持父级统一 URL 更新，或单独 pathname + q 模式。
 */
export default function AdminDebouncedSearchForm({
  initialValue = '',
  onQueryChange,
  isQueryPending,
  fullWidth = false,
  placeholder = 'Search…',
  ariaLabel = 'Search',
  inlineLoadingText = 'Searching…',
}: AdminDebouncedSearchFormProps) {
  const router = useRouter()
  const pathname = usePathname()
  const [urlPending, startTransition] = useTransition()
  const [value, setValue] = useState(initialValue)
  const lastPushedQRef = useRef(initialValue)

  const isPending = onQueryChange ? (isQueryPending ?? false) : urlPending

  useEffect(() => {
    if (initialValue !== lastPushedQRef.current) {
      lastPushedQRef.current = initialValue
      // 同步导航完成后的 URL 查询串到输入框
      // eslint-disable-next-line react-hooks/set-state-in-effect -- 仅在外部 initialValue 变化时同步
      setValue(initialValue)
    }
  }, [initialValue])

  useEffect(() => {
    const timer = setTimeout(() => {
      const trimmed = value.trim()
      lastPushedQRef.current = trimmed
      if (onQueryChange) {
        onQueryChange(trimmed)
      } else {
        const url = trimmed ? `${pathname}?q=${encodeURIComponent(trimmed)}` : pathname
        startTransition(() => {
          router.replace(url)
        })
      }
    }, DEBOUNCE_MS)
    return () => clearTimeout(timer)
  }, [value, pathname, router, startTransition, onQueryChange])

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
        placeholder={placeholder}
        className={
          fullWidth
            ? 'min-w-0 flex-1 rounded-lg border border-gray-300 px-3 py-2 text-sm text-gray-900 placeholder-gray-400 focus:border-transparent focus:outline-none focus:ring-2 focus:ring-blue-500'
            : 'min-w-[180px] rounded-lg border border-gray-300 px-3 py-2 text-sm text-gray-900 placeholder-gray-400 focus:border-transparent focus:outline-none focus:ring-2 focus:ring-blue-500'
        }
        aria-label={ariaLabel}
      />
      {isPending && (
        <span className="flex items-center gap-1.5 text-sm text-gray-500" aria-live="polite">
          <span className="inline-block h-4 w-4 shrink-0 overflow-visible text-gray-500">
            <AdminSpinnerIcon size={16} />
          </span>
          {inlineLoadingText}
        </span>
      )}
      {!isPending && value.trim() !== '' && (
        <button
          type="button"
          onClick={() => setValue('')}
          className="rounded-lg px-3 py-2 text-sm font-medium text-gray-600 transition-colors hover:bg-gray-100 hover:text-gray-900"
        >
          Clear
        </button>
      )}
    </div>
  )
}
