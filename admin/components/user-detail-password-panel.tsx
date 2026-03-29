'use client'

import { useState, useTransition, type FormEvent } from 'react'
import { toast } from 'sonner'
import { adminSetUserPassword, sendUserPasswordRecoveryEmail } from '@/app/actions/admin'

export default function UserDetailPasswordPanel({
  userId,
  hasEmail,
}: {
  userId: string
  hasEmail: boolean
}) {
  const [password, setPassword] = useState('')
  const [confirm, setConfirm] = useState('')
  const [isPending, startTransition] = useTransition()

  const sendRecovery = () => {
    if (!hasEmail) {
      toast.error('This user has no email; cannot send recovery mail.')
      return
    }
    startTransition(async () => {
      try {
        await sendUserPasswordRecoveryEmail(userId)
        toast.success('Done. Email sends only if email type C12 (Password Reset) is enabled in settings.')
      } catch (e: unknown) {
        toast.error(e instanceof Error ? e.message : 'Failed to send email')
      }
    })
  }

  const setPasswordSubmit = (e: FormEvent) => {
    e.preventDefault()
    if (password !== confirm) {
      toast.error('Passwords do not match')
      return
    }
    startTransition(async () => {
      try {
        await adminSetUserPassword(userId, password)
        setPassword('')
        setConfirm('')
        toast.success('Password updated')
      } catch (err: unknown) {
        toast.error(err instanceof Error ? err.message : 'Failed to set password')
      }
    })
  }

  return (
    <div className="space-y-2">
      <p className="text-[11px] leading-snug text-gray-500">
        Recovery link by email, or set a new password below (share securely with the user).
      </p>

      <div>
        <button
          type="button"
          onClick={sendRecovery}
          disabled={isPending || !hasEmail}
          className="inline-flex text-xs font-medium px-2.5 py-1.5 rounded-md border border-gray-300 bg-white text-gray-800 hover:bg-gray-50 disabled:opacity-50 disabled:cursor-not-allowed"
        >
          Send reset email
        </button>
        {!hasEmail && (
          <p className="text-[11px] text-amber-600 mt-1">No email on file.</p>
        )}
      </div>

      <form onSubmit={setPasswordSubmit} className="space-y-1.5 border-t border-gray-100 pt-2.5 mt-2">
        <p className="text-[11px] font-medium text-gray-700">New password</p>
        <input
          type="password"
          autoComplete="new-password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          placeholder="Min 8 characters"
          className="w-full text-xs px-2 py-1.5 rounded-md border border-gray-300"
        />
        <input
          type="password"
          autoComplete="new-password"
          value={confirm}
          onChange={(e) => setConfirm(e.target.value)}
          placeholder="Confirm"
          className="w-full text-xs px-2 py-1.5 rounded-md border border-gray-300"
        />
        <button
          type="submit"
          disabled={isPending || password.length < 8}
          className="w-full text-xs font-medium px-2 py-1.5 rounded-md bg-gray-900 text-white hover:bg-gray-800 disabled:opacity-50"
        >
          Apply new password
        </button>
      </form>
    </div>
  )
}
