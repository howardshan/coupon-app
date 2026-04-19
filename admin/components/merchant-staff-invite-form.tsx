'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { inviteOrAddMerchantStaff } from '@/app/actions/merchant-staff-admin'
import { MERCHANT_STAFF_ROLES } from '@/lib/merchant-staff-constants'

const ROLE_LABELS: Record<string, string> = {
  cashier: 'Cashier',
  service: 'Service',
  manager: 'Manager',
  finance: 'Finance',
  regional_manager: 'Regional manager',
  trainee: 'Trainee',
}

export default function MerchantStaffInviteForm({ merchantId }: { merchantId: string }) {
  const router = useRouter()
  const [email, setEmail] = useState('')
  const [role, setRole] = useState<string>('cashier')
  const [loading, setLoading] = useState(false)
  const [message, setMessage] = useState<string | null>(null)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setMessage(null)
    setLoading(true)
    try {
      const result = await inviteOrAddMerchantStaff({ merchantId, email, role })
      setMessage(
        result.mode === 'invited'
          ? 'Invitation created. The user can accept after they sign up with this email.'
          : 'Staff member added to this store.'
      )
      setEmail('')
      router.refresh()
    } catch (err) {
      setMessage(err instanceof Error ? err.message : 'Failed')
    } finally {
      setLoading(false)
    }
  }

  return (
    <form onSubmit={handleSubmit} className="rounded-lg border border-gray-200 bg-gray-50 p-4">
      <h3 className="text-sm font-semibold text-gray-900">Invite or add staff (admin)</h3>
      <p className="mt-1 text-xs text-gray-500">
        If the email is already registered, a staff row is created immediately. Otherwise, only manager / cashier /
        service invitations can be sent (pending signup).
      </p>
      <div className="mt-3 flex flex-col gap-3 sm:flex-row sm:flex-wrap sm:items-end">
        <label className="block min-w-[200px] flex-1">
          <span className="text-xs font-medium text-gray-600">Email</span>
          <input
            type="email"
            required
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            className="mt-1 w-full rounded-md border border-gray-300 px-3 py-2 text-sm"
            placeholder="name@example.com"
          />
        </label>
        <label className="block w-full sm:w-44">
          <span className="text-xs font-medium text-gray-600">Role</span>
          <select
            value={role}
            onChange={(e) => setRole(e.target.value)}
            className="mt-1 w-full rounded-md border border-gray-300 px-3 py-2 text-sm"
          >
            {MERCHANT_STAFF_ROLES.map((r) => (
              <option key={r} value={r}>
                {ROLE_LABELS[r] ?? r}
              </option>
            ))}
          </select>
        </label>
        <button
          type="submit"
          disabled={loading}
          className="rounded-md bg-blue-600 px-4 py-2 text-sm font-medium text-white hover:bg-blue-700 disabled:opacity-50"
        >
          {loading ? '…' : 'Send'}
        </button>
      </div>
      {message && <p className="mt-2 text-xs text-gray-700">{message}</p>}
    </form>
  )
}
