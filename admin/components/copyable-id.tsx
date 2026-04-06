'use client'

import { useState } from 'react'

// 显示截断 ID，点击复制完整 ID
export function CopyableId({ id, showFull = false }: { id: string; showFull?: boolean }) {
  const [copied, setCopied] = useState(false)

  function handleCopy() {
    if (navigator.clipboard?.writeText) {
      navigator.clipboard.writeText(id)
    } else {
      // fallback: 用隐藏 textarea 复制
      const ta = document.createElement('textarea')
      ta.value = id
      ta.style.position = 'fixed'
      ta.style.opacity = '0'
      document.body.appendChild(ta)
      ta.select()
      document.execCommand('copy')
      document.body.removeChild(ta)
    }
    setCopied(true)
    setTimeout(() => setCopied(false), 1500)
  }

  return (
    <code
      className="text-xs text-gray-500 cursor-pointer hover:text-gray-700"
      title={`${id}\nClick to copy`}
      onClick={handleCopy}
    >
      {copied ? 'Copied!' : showFull ? id : id.slice(0, 8)}
    </code>
  )
}
