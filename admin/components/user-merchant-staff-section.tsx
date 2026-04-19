'use client'

import Link from 'next/link'
import MerchantStaffAdminRow, { type MerchantStaffAdminRowModel } from '@/components/merchant-staff-admin-row'

type PendingInvitation = {
  id: string
  merchantId: string
  merchantName: string | null
  role: string
  expiresAt: string
  createdAt: string
}

export default function UserMerchantStaffSection({
  staffRows,
  pendingInvitations,
  userEmail,
}: {
  staffRows: MerchantStaffAdminRowModel[]
  pendingInvitations: PendingInvitation[]
  userEmail: string
}) {
  const hasStaff = staffRows.length > 0
  const hasPending = pendingInvitations.length > 0

  if (!hasStaff && !hasPending) {
    return (
      <div className="bg-white rounded-xl border border-gray-200 p-6">
        <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-2">Merchant staff</h2>
        <p className="text-sm text-gray-500">
          This account is not linked to any store staff records (merchant_staff). Pending invitations must match email{' '}
          <span className="font-mono text-gray-700">{userEmail || '(unknown)'}</span>.
        </p>
      </div>
    )
  }

  return (
    <div className="space-y-6">
      {hasStaff && (
        <div className="bg-white rounded-xl border border-gray-200 p-6">
          <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-4">
            Merchant staff ({staffRows.length})
          </h2>
          <p className="text-xs text-gray-500 mb-4">
            Store-level roles (cashier, manager, etc.). Use actions to change role, disable, or remove access.
          </p>
          <div className="overflow-x-auto">
            <table className="w-full text-sm min-w-[640px]">
              <thead className="border-b border-gray-100">
                <tr>
                  <th className="text-left py-2 font-medium text-gray-500">Store</th>
                  <th className="text-left py-2 font-medium text-gray-500">Name</th>
                  <th className="text-left py-2 font-medium text-gray-500">Email</th>
                  <th className="text-left py-2 font-medium text-gray-500">Role</th>
                  <th className="text-left py-2 font-medium text-gray-500">Status</th>
                  <th className="text-left py-2 font-medium text-gray-500">Since</th>
                  <th className="text-left py-2 font-medium text-gray-500">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-50">
                {staffRows.map((row) => (
                  <MerchantStaffAdminRow key={row.id} row={row} showStoreColumn />
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {hasPending && (
        <div className="bg-white rounded-xl border border-amber-100 p-6">
          <h2 className="text-sm font-semibold text-amber-800 uppercase tracking-wide mb-3">
            Pending staff invitations ({pendingInvitations.length})
          </h2>
          <p className="text-xs text-gray-600 mb-4">
            These invitations match this user&apos;s email. They will become staff after accepting in the merchant app.
          </p>
          <ul className="space-y-2">
            {pendingInvitations.map((inv) => (
              <li
                key={inv.id}
                className="flex flex-wrap items-center justify-between gap-2 rounded border border-dashed border-amber-200 px-3 py-2 text-sm"
              >
                <span>
                  <Link href={`/merchants/${inv.merchantId}`} className="font-medium text-blue-600 hover:underline">
                    {inv.merchantName || inv.merchantId.slice(0, 8)}
                  </Link>
                  <span className="text-gray-500"> · role {inv.role}</span>
                </span>
                <span className="text-xs text-gray-400">
                  expires {new Date(inv.expiresAt).toLocaleDateString('en-US')}
                </span>
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  )
}
