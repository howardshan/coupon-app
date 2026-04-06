'use client'

import { useState, useTransition } from 'react'
import { toast } from 'sonner'

interface StatusToggleProps {
  configId: string
  initialActive: boolean
  onActivate: (configId: string) => Promise<void>
  onDeactivate: (configId: string) => Promise<void>
}

// 状态开关组件：用于 Splash / Onboarding / Banner 页面
export function StatusToggle({ configId, initialActive, onActivate, onDeactivate }: StatusToggleProps) {
  const [active, setActive] = useState(initialActive)
  const [isPending, startTransition] = useTransition()

  function handleToggle() {
    const nextActive = !active
    setActive(nextActive)
    startTransition(async () => {
      try {
        if (nextActive) {
          await onActivate(configId)
        } else {
          await onDeactivate(configId)
        }
        toast.success(nextActive ? 'Activated' : 'Deactivated')
      } catch (e: any) {
        setActive(!nextActive) // 回滚
        toast.error(e.message || 'Failed to update status')
      }
    })
  }

  return (
    <div className="flex items-center gap-3">
      <button
        type="button"
        role="switch"
        aria-checked={active}
        disabled={isPending}
        onClick={handleToggle}
        className={`
          relative inline-flex h-6 w-11 shrink-0 cursor-pointer rounded-full border-2 border-transparent
          transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2
          disabled:opacity-50 disabled:cursor-not-allowed
          ${active ? 'bg-green-500' : 'bg-gray-300'}
        `}
      >
        <span
          className={`
            pointer-events-none inline-block h-5 w-5 rounded-full bg-white shadow ring-0
            transition duration-200 ease-in-out
            ${active ? 'translate-x-5' : 'translate-x-0'}
          `}
        />
      </button>
      <span className={`text-sm font-medium ${active ? 'text-green-600' : 'text-gray-500'}`}>
        {isPending ? 'Updating...' : active ? 'Active' : 'Inactive'}
      </span>
    </div>
  )
}
