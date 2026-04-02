'use client'

import { useState, useTransition } from 'react'
import { pauseCampaign, resumeCampaign } from '@/app/actions/ads'

// Campaign 详情页的 Admin 操作组件
export default function CampaignDetailActions({
  campaignId,
  status,
}: {
  campaignId: string
  status: string
}) {
  const [isPending, startTransition] = useTransition()
  const [note, setNote] = useState('')
  const [error, setError] = useState('')
  const [success, setSuccess] = useState('')

  const canPause = status === 'active' || status === 'paused'
  const canResume = status === 'admin_paused'

  function handlePause() {
    setError('')
    setSuccess('')
    startTransition(async () => {
      try {
        await pauseCampaign(campaignId, note)
        setSuccess('Campaign paused successfully')
        setNote('')
      } catch (e: any) {
        setError(e.message)
      }
    })
  }

  function handleResume() {
    setError('')
    setSuccess('')
    startTransition(async () => {
      try {
        await resumeCampaign(campaignId)
        setSuccess('Campaign resumed successfully')
      } catch (e: any) {
        setError(e.message)
      }
    })
  }

  return (
    <div className="space-y-3">
      {canPause && (
        <div className="space-y-2">
          <label className="block text-xs text-gray-500">Admin Note (reason for pausing)</label>
          <input
            type="text"
            value={note}
            onChange={e => setNote(e.target.value)}
            placeholder="Enter reason for pausing..."
            className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
          />
          <button
            onClick={handlePause}
            disabled={isPending}
            className="px-4 py-2 rounded-lg text-sm font-medium bg-red-600 text-white hover:bg-red-700 transition-colors disabled:opacity-50"
          >
            {isPending ? 'Processing...' : 'Admin Pause'}
          </button>
        </div>
      )}

      {canResume && (
        <button
          onClick={handleResume}
          disabled={isPending}
          className="px-4 py-2 rounded-lg text-sm font-medium bg-green-600 text-white hover:bg-green-700 transition-colors disabled:opacity-50"
        >
          {isPending ? 'Processing...' : 'Resume Campaign'}
        </button>
      )}

      {!canPause && !canResume && (
        <p className="text-sm text-gray-500">
          No admin actions available for status: <span className="font-medium">{status}</span>
        </p>
      )}

      {error && (
        <div className="bg-red-50 border border-red-200 rounded-lg p-3 text-sm text-red-700">{error}</div>
      )}
      {success && (
        <div className="bg-green-50 border border-green-200 rounded-lg p-3 text-sm text-green-700">{success}</div>
      )}
    </div>
  )
}
