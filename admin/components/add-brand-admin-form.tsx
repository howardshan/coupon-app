'use client'

import { useState, useTransition } from 'react'
import { toast } from 'sonner'
import { addBrandAdmin } from '@/app/actions/brands'

export default function AddBrandAdminForm({ brandId }: { brandId: string }) {
  const [email, setEmail] = useState('')
  const [role, setRole] = useState<'owner' | 'admin'>('admin')
  const [isPending, startTransition] = useTransition()

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!email.trim()) return

    startTransition(async () => {
      try {
        await addBrandAdmin(brandId, email, role)
        setEmail('')
        toast.success('Brand admin added')
      } catch (err: any) {
        toast.error(err.message || 'Failed to add admin')
      }
    })
  }

  return (
    <form onSubmit={handleSubmit} className="flex items-end gap-2">
      <div>
        <label className="block text-xs text-gray-500 mb-1">Email</label>
        <input
          type="email"
          value={email}
          onChange={e => setEmail(e.target.value)}
          placeholder="user@example.com"
          required
          className="px-3 py-1.5 text-sm border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none"
        />
      </div>
      <div>
        <label className="block text-xs text-gray-500 mb-1">Role</label>
        <select
          value={role}
          onChange={e => setRole(e.target.value as 'owner' | 'admin')}
          className="px-3 py-1.5 text-sm border border-gray-300 rounded-lg bg-white focus:ring-2 focus:ring-blue-500 outline-none"
        >
          <option value="admin">Admin</option>
          <option value="owner">Owner</option>
        </select>
      </div>
      <button
        type="submit"
        disabled={isPending || !email.trim()}
        className="px-3 py-1.5 text-sm font-medium rounded-lg bg-blue-600 text-white hover:bg-blue-700 disabled:opacity-50 transition-colors"
      >
        {isPending ? 'Adding...' : 'Add'}
      </button>
    </form>
  )
}
