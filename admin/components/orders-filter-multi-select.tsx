'use client'

import { useEffect, useMemo, useRef, useState } from 'react'

type Option = { value: string; label: string }

type OrdersFilterMultiSelectProps = {
  /** 与上方 label 文案一致，供无障碍使用 */
  fieldLabel: string
  options: Option[]
  selectedValues: string[]
  onChange: (next: string[]) => void
  /** 与订单页其它筛选控件一致的按钮样式 */
  triggerClassName: string
}

/** 订单页 Status / Merchant 多选：下拉 checkbox + 下方展示已选摘要 */
export default function OrdersFilterMultiSelect({
  fieldLabel,
  options,
  selectedValues,
  onChange,
  triggerClassName,
}: OrdersFilterMultiSelectProps) {
  const [open, setOpen] = useState(false)
  const rootRef = useRef<HTMLDivElement>(null)

  const labelByValue = useMemo(() => {
    const m = new Map<string, string>()
    for (const o of options) m.set(o.value, o.label)
    return m
  }, [options])

  const summaryText =
    selectedValues.length === 0
      ? 'All'
      : selectedValues.map((v) => labelByValue.get(v) ?? v).join(', ')

  const triggerText =
    selectedValues.length === 0 ? 'All' : `${selectedValues.length} selected`

  useEffect(() => {
    if (!open) return
    const onDocMouseDown = (e: MouseEvent) => {
      if (rootRef.current && !rootRef.current.contains(e.target as Node)) {
        setOpen(false)
      }
    }
    document.addEventListener('mousedown', onDocMouseDown)
    return () => document.removeEventListener('mousedown', onDocMouseDown)
  }, [open])

  const toggle = (value: string) => {
    const set = new Set(selectedValues)
    if (set.has(value)) set.delete(value)
    else set.add(value)
    onChange([...set])
  }

  return (
    <div ref={rootRef} className="relative min-w-0">
      <span className="mb-1 block font-medium text-gray-600">{fieldLabel}</span>
      <button
        type="button"
        aria-expanded={open}
        aria-haspopup="listbox"
        aria-label={`${fieldLabel} filter`}
        onClick={() => setOpen((v) => !v)}
        className={`${triggerClassName} flex w-full min-h-[42px] items-center justify-between gap-2 text-left`}
      >
        <span className="min-w-0 truncate">{triggerText}</span>
        <span className="shrink-0 text-gray-400" aria-hidden>
          {open ? '▲' : '▼'}
        </span>
      </button>
      {open && (
        <div className="absolute left-0 right-0 z-30 mt-1 flex max-h-72 flex-col overflow-hidden rounded-lg border border-gray-200 bg-white shadow-lg">
          <div
            className="max-h-60 min-h-0 flex-1 overflow-y-auto p-2"
            role="listbox"
            aria-label={fieldLabel}
          >
            {options.map((opt) => (
              <label
                key={opt.value}
                className="flex cursor-pointer items-center gap-2 rounded px-2 py-1.5 text-gray-800 hover:bg-gray-50"
              >
                <input
                  type="checkbox"
                  className="h-4 w-4 shrink-0 rounded border-gray-300"
                  checked={selectedValues.includes(opt.value)}
                  onChange={() => toggle(opt.value)}
                />
                <span className="min-w-0 text-sm">{opt.label}</span>
              </label>
            ))}
          </div>
          <div className="shrink-0 border-t border-gray-200 p-2">
            <button
              type="button"
              disabled={selectedValues.length === 0}
              aria-label={`Clear all ${fieldLabel} filters`}
              className="w-full rounded-md px-3 py-2 text-sm font-medium text-gray-700 transition-colors hover:bg-gray-100 disabled:cursor-not-allowed disabled:opacity-40"
              onClick={() => {
                onChange([])
                setOpen(false)
              }}
            >
              Clear
            </button>
          </div>
        </div>
      )}
      <p className="mt-1 text-xs leading-snug text-gray-600 break-words" aria-live="polite">
        {summaryText}
      </p>
    </div>
  )
}
