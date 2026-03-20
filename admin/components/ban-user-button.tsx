'use client'

import { useState } from 'react'
import { banUser, banUserPermanently, unbanUser } from '@/app/actions/admin'
import { toast } from 'sonner'

export default function BanUserButton({
  userId,
  isBanned,
  bannedUntil,
}: {
  userId: string
  isBanned: boolean
  bannedUntil: string | null
}) {
  const [loading, setLoading] = useState(false)
  const [showBanOptions, setShowBanOptions] = useState(false)

  const handleUnban = async () => {
    setLoading(true)
    try {
      await unbanUser(userId)
      toast.success('User unbanned successfully')
    } catch (e: any) {
      toast.error(e.message || 'Failed to unban user')
    } finally {
      setLoading(false)
    }
  }

  const handleBan = async (days: number | 'permanent') => {
    setLoading(true)
    try {
      if (days === 'permanent') {
        await banUserPermanently(userId)
        toast.success('User permanently banned')
      } else {
        await banUser(userId, days)
        toast.success(`User banned for ${days} days`)
      }
      setShowBanOptions(false)
    } catch (e: any) {
      toast.error(e.message || 'Failed to ban user')
    } finally {
      setLoading(false)
    }
  }

  if (isBanned) {
    return (
      <div className="flex items-center gap-4">
        <div className="flex-1">
          <p className="text-sm text-red-600 font-medium">This user is currently banned</p>
          {bannedUntil && (
            <p className="text-xs text-gray-500 mt-1">
              Until: {new Date(bannedUntil).toLocaleString()}
            </p>
          )}
        </div>
        <button
          onClick={handleUnban}
          disabled={loading}
          className="px-4 py-2 text-sm font-medium rounded-lg bg-green-600 text-white hover:bg-green-700 disabled:opacity-50 transition-colors"
        >
          {loading ? 'Processing...' : 'Unban User'}
        </button>
      </div>
    )
  }

  return (
    <div>
      {!showBanOptions ? (
        <button
          onClick={() => setShowBanOptions(true)}
          className="px-4 py-2 text-sm font-medium rounded-lg bg-red-600 text-white hover:bg-red-700 transition-colors"
        >
          Ban User
        </button>
      ) : (
        <div className="space-y-3">
          <p className="text-sm text-gray-600">Select ban duration:</p>
          <div className="flex flex-wrap gap-2">
            {[
              { label: '7 days', days: 7 },
              { label: '30 days', days: 30 },
              { label: '90 days', days: 90 },
              { label: '1 year', days: 365 },
            ].map(opt => (
              <button
                key={opt.days}
                onClick={() => handleBan(opt.days)}
                disabled={loading}
                className="px-3 py-1.5 text-sm font-medium rounded-lg border border-red-300 text-red-700 hover:bg-red-50 disabled:opacity-50 transition-colors"
              >
                {opt.label}
              </button>
            ))}
            <button
              onClick={() => handleBan('permanent')}
              disabled={loading}
              className="px-3 py-1.5 text-sm font-medium rounded-lg bg-red-600 text-white hover:bg-red-700 disabled:opacity-50 transition-colors"
            >
              Permanent
            </button>
            <button
              onClick={() => setShowBanOptions(false)}
              className="px-3 py-1.5 text-sm font-medium rounded-lg border border-gray-300 text-gray-600 hover:bg-gray-50 transition-colors"
            >
              Cancel
            </button>
          </div>
          {loading && <p className="text-xs text-gray-400">Processing...</p>}
        </div>
      )}
    </div>
  )
}
