'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import Link from 'next/link'
import { removeMerchantStaff, setMerchantStaffActive, updateMerchantStaffRole } from '@/app/actions/merchant-staff-admin'
import { MERCHANT_STAFF_ROLES } from '@/lib/merchant-staff-constants'

const ROLE_LABELS: Record<string, string> = {
  cashier: 'Cashier',
  service: 'Service',
  manager: 'Manager',
  finance: 'Finance',
  regional_manager: 'Regional manager',
  trainee: 'Trainee',
}

export type MerchantStaffAdminRowModel = {
  id: string
  merchantId: string
  userId: string
  role: string
  isActive: boolean
  nickname?: string | null
  email?: string | null
  fullName?: string | null
  createdAt: string
  merchantName?: string | null
}

export default function MerchantStaffAdminRow({
  row,
  showStoreColumn,
}: {
  row: MerchantStaffAdminRowModel
  /** 用户详情页为 true，展示门店列 */
  showStoreColumn: boolean
}) {
  const router = useRouter()
  const [loading, setLoading] = useState<string | null>(null)

  const displayName = row.nickname || row.fullName || row.email?.split('@')[0] || '—'

  const roleOptions = Array.from(new Set([row.role, ...MERCHANT_STAFF_ROLES]))

  async function run(action: string, fn: () => Promise<void>) {
    setLoading(action)
    try {
      await fn()
      router.refresh()
    } catch (e) {
      alert(e instanceof Error ? e.message : 'Failed')
    } finally {
      setLoading(null)
    }
  }

  return (
    <tr className="hover:bg-gray-50">
      {showStoreColumn && (
        <td className="py-2">
          <Link href={`/merchants/${row.merchantId}`} className="text-blue-600 hover:underline text-sm font-medium">
            {row.merchantName || row.merchantId.slice(0, 8)}
          </Link>
        </td>
      )}
      <td className="py-2 text-gray-900">{displayName}</td>
      <td className="py-2 text-gray-600 text-xs">{row.email || '—'}</td>
      <td className="py-2">
        <select
          value={row.role}
          disabled={loading !== null}
          onChange={(e) => {
            const next = e.target.value
            if (next === row.role) return
            void run('role', () =>
              updateMerchantStaffRole({
                staffId: row.id,
                merchantId: row.merchantId,
                newRole: next,
                affectedUserId: row.userId,
              })
            )
          }}
          className="rounded border border-gray-200 bg-white px-2 py-1 text-xs"
        >
          {roleOptions.map((r) => (
            <option key={r} value={r}>
              {ROLE_LABELS[r] ?? r}
            </option>
          ))}
        </select>
      </td>
      <td className="py-2">
        <span
          className={`px-2 py-0.5 rounded-full text-xs font-medium ${
            row.isActive ? 'bg-green-100 text-green-700' : 'bg-red-100 text-red-700'
          }`}
        >
          {row.isActive ? 'Active' : 'Disabled'}
        </span>
      </td>
      <td className="py-2 text-gray-500 text-xs">{new Date(row.createdAt).toLocaleDateString('en-US')}</td>
      <td className="py-2">
        <div className="flex flex-wrap gap-1">
          <button
            type="button"
            disabled={loading !== null}
            onClick={() =>
              run('toggle', () =>
                setMerchantStaffActive({
                  staffId: row.id,
                  isActive: !row.isActive,
                  merchantId: row.merchantId,
                  affectedUserId: row.userId,
                })
              )
            }
            className={`rounded px-2 py-1 text-xs font-medium ${
              row.isActive
                ? 'border border-red-200 bg-red-50 text-red-700 hover:bg-red-100'
                : 'border border-green-200 bg-green-50 text-green-700 hover:bg-green-100'
            }`}
          >
            {loading === 'toggle' ? '…' : row.isActive ? 'Disable' : 'Enable'}
          </button>
          <button
            type="button"
            disabled={loading !== null}
            onClick={() => {
              if (
                !confirm(
                  `Remove staff access for ${displayName} at ${row.merchantName ?? 'this store'}? They can be re-invited later.`
                )
              ) {
                return
              }
              void run('remove', () =>
                removeMerchantStaff({
                  staffId: row.id,
                  merchantId: row.merchantId,
                  affectedUserId: row.userId,
                })
              )
            }}
            className="rounded border border-gray-200 bg-white px-2 py-1 text-xs text-gray-700 hover:bg-gray-50"
          >
            {loading === 'remove' ? '…' : 'Remove'}
          </button>
        </div>
      </td>
    </tr>
  )
}
