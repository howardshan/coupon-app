'use client'

import { useState, useTransition } from 'react'
import { pauseCampaign, resumeCampaign } from '@/app/actions/ads'

// Campaign 暂停/恢复按钮组件（客户端交互）
export default function CampaignActions({
  campaignId,
  status,
}: {
  campaignId: string
  status: string
}) {
  const [isPending, startTransition] = useTransition()
  const [showNoteInput, setShowNoteInput] = useState(false)
  const [note, setNote] = useState('')
  const [error, setError] = useState('')

  // 可暂停的状态
  const canPause = status === 'active' || status === 'paused'
  // 可恢复的状态
  const canResume = status === 'admin_paused'

  function handlePause() {
    if (!showNoteInput) {
      setShowNoteInput(true)
      return
    }
    setError('')
    startTransition(async () => {
      try {
        await pauseCampaign(campaignId, note)
        setShowNoteInput(false)
        setNote('')
      } catch (e: any) {
        setError(e.message)
      }
    })
  }

  function handleResume() {
    setError('')
    startTransition(async () => {
      try {
        await resumeCampaign(campaignId)
      } catch (e: any) {
        setError(e.message)
      }
    })
  }

  return (
    <div className="flex items-center gap-1">
      {canPause && (
        <div className="flex items-center gap-1">
          {showNoteInput && (
            <input
              type="text"
              value={note}
              onChange={e => setNote(e.target.value)}
              placeholder="Admin note..."
              className="border border-gray-300 rounded px-2 py-1 text-xs w-28"
            />
          )}
          <button
            onClick={handlePause}
            disabled={isPending}
            className="px-2 py-1 rounded text-xs font-medium bg-red-50 text-red-600 hover:bg-red-100 transition-colors disabled:opacity-50"
          >
            {isPending ? '...' : 'Pause'}
          </button>
          {showNoteInput && (
            <button
              onClick={() => { setShowNoteInput(false); setNote('') }}
              className="px-2 py-1 rounded text-xs text-gray-500 hover:text-gray-700"
            >
              Cancel
            </button>
          )}
        </div>
      )}
      {canResume && (
        <button
          onClick={handleResume}
          disabled={isPending}
          className="px-2 py-1 rounded text-xs font-medium bg-green-50 text-green-600 hover:bg-green-100 transition-colors disabled:opacity-50"
        >
          {isPending ? '...' : 'Resume'}
        </button>
      )}
      {error && <span className="text-xs text-red-500">{error}</span>}
    </div>
  )
}
