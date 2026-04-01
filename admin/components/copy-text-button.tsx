'use client'

import { useCallback, useState } from 'react'

/** 复制文本到剪贴板（订单号等） */
export default function CopyTextButton({
  text,
  label = 'Copy',
  copiedLabel = 'Copied',
  className = '',
}: {
  text: string
  label?: string
  copiedLabel?: string
  className?: string
}) {
  const [copied, setCopied] = useState(false)

  const onCopy = useCallback(async () => {
    if (!text) return
    try {
      await navigator.clipboard.writeText(text)
      setCopied(true)
      window.setTimeout(() => setCopied(false), 2000)
    } catch {
      setCopied(false)
    }
  }, [text])

  return (
    <button
      type="button"
      onClick={onCopy}
      disabled={!text}
      className={`inline-flex items-center gap-1 rounded-lg border border-slate-200 bg-white px-2 py-1 text-xs font-semibold text-slate-600 shadow-sm ring-1 ring-slate-900/[0.03] transition hover:bg-slate-50 disabled:opacity-40 ${className}`}
      aria-label={copied ? copiedLabel : `Copy ${label}`}
    >
      <svg className="h-3.5 w-3.5 shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden>
        <path
          strokeLinecap="round"
          strokeLinejoin="round"
          strokeWidth={2}
          d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z"
        />
      </svg>
      {copied ? copiedLabel : label}
    </button>
  )
}
