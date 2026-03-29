'use client'

import { useState } from 'react'
import { banUser, banUserPermanently, unbanUser } from '@/app/actions/admin'
import { toast } from 'sonner'

export default function BanUserButton({
  userId,
  isBanned,
  bannedUntil,
  compact = false,
}: {
  userId: string
  isBanned: boolean
  bannedUntil: string | null
  /** 用户详情侧栏：更小按钮与间距 */
  compact?: boolean
}) {
  const [loading, setLoading] = useState(false)
  const [showBanOptions, setShowBanOptions] = useState(false)

  const handleUnban = async () => {
    setLoading(true)
    try {
      await unbanUser(userId)
      toast.success('User unbanned successfully')
    } catch (e: unknown) {
      toast.error(e instanceof Error ? e.message : 'Failed to unban user')
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
    } catch (e: unknown) {
      toast.error(e instanceof Error ? e.message : 'Failed to ban user')
    } finally {
      setLoading(false)
    }
  }

  if (isBanned) {
    return (
      <div className={compact ? 'space-y-1.5' : 'flex items-center gap-4'}>
        <div className={compact ? '' : 'flex-1'}>
          <p className={compact ? 'text-xs text-red-600 font-medium' : 'text-sm text-red-600 font-medium'}>
            Currently banned
          </p>
          {bannedUntil && (
            <p className="text-[11px] text-gray-500 mt-0.5">
              Until {new Date(bannedUntil).toLocaleString('en-US', { dateStyle: 'short', timeStyle: 'short' })}
            </p>
          )}
        </div>
        <button
          onClick={handleUnban}
          disabled={loading}
          className={
            compact
              ? 'px-2.5 py-1.5 text-xs font-medium rounded-md bg-green-600 text-white hover:bg-green-700 disabled:opacity-50 transition-colors w-full sm:w-auto'
              : 'px-4 py-2 text-sm font-medium rounded-lg bg-green-600 text-white hover:bg-green-700 disabled:opacity-50 transition-colors'
          }
        >
          {loading ? 'Processing...' : 'Unban'}
        </button>
      </div>
    )
  }

  return (
    <div>
      {!showBanOptions ? (
        <button
          onClick={() => setShowBanOptions(true)}
          className={
            compact
              ? 'px-2.5 py-1.5 text-xs font-medium rounded-md bg-red-600 text-white hover:bg-red-700 transition-colors'
              : 'px-4 py-2 text-sm font-medium rounded-lg bg-red-600 text-white hover:bg-red-700 transition-colors'
          }
        >
          Ban user
        </button>
      ) : (
        <div className={compact ? 'space-y-2' : 'space-y-3'}>
          <p className={compact ? 'text-xs text-gray-600' : 'text-sm text-gray-600'}>Ban duration:</p>
          <div className="flex flex-wrap gap-1.5">
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
                className={
                  compact
                    ? 'px-2 py-1 text-xs font-medium rounded-md border border-red-300 text-red-700 hover:bg-red-50 disabled:opacity-50 transition-colors'
                    : 'px-3 py-1.5 text-sm font-medium rounded-lg border border-red-300 text-red-700 hover:bg-red-50 disabled:opacity-50 transition-colors'
                }
              >
                {opt.label}
              </button>
            ))}
            <button
              onClick={() => handleBan('permanent')}
              disabled={loading}
              className={
                compact
                  ? 'px-2 py-1 text-xs font-medium rounded-md bg-red-600 text-white hover:bg-red-700 disabled:opacity-50 transition-colors'
                  : 'px-3 py-1.5 text-sm font-medium rounded-lg bg-red-600 text-white hover:bg-red-700 disabled:opacity-50 transition-colors'
              }
            >
              Permanent
            </button>
            <button
              onClick={() => setShowBanOptions(false)}
              disabled={loading}
              className={
                compact
                  ? 'px-2 py-1 text-xs font-medium rounded-md border border-gray-300 text-gray-600 hover:bg-gray-50 transition-colors'
                  : 'px-3 py-1.5 text-sm font-medium rounded-lg border border-gray-300 text-gray-600 hover:bg-gray-50 transition-colors'
              }
            >
              Cancel
            </button>
          </div>
          {loading && <p className={compact ? 'text-[11px] text-gray-400' : 'text-xs text-gray-400'}>Processing...</p>}
        </div>
      )}
    </div>
  )
}
