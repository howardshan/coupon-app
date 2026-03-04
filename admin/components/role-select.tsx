'use client'

import { useState, useTransition } from 'react'
import { updateUserRole } from '@/app/actions/admin'

interface RoleSelectProps {
  userId: string
  currentRole: string
}

const roles = ['user', 'merchant', 'admin'] as const

export default function RoleSelect({ userId, currentRole }: RoleSelectProps) {
  const [role, setRole] = useState(currentRole)
  const [isPending, startTransition] = useTransition()
  const [error, setError] = useState('')

  function handleChange(newRole: string) {
    const previous = role
    setRole(newRole)
    setError('')

    startTransition(async () => {
      try {
        await updateUserRole(userId, newRole as 'user' | 'merchant' | 'admin')
      } catch {
        setRole(previous)
        setError('Failed to update role')
      }
    })
  }

  const colors: Record<string, string> = {
    admin: 'text-red-700 bg-red-50 border-red-200',
    merchant: 'text-blue-700 bg-blue-50 border-blue-200',
    user: 'text-gray-600 bg-gray-50 border-gray-200',
  }

  return (
    <div>
      <select
        value={role}
        onChange={e => handleChange(e.target.value)}
        disabled={isPending}
        className={`text-xs font-medium px-2 py-1 rounded-full border cursor-pointer transition-opacity disabled:opacity-50 ${colors[role] ?? colors.user}`}
      >
        {roles.map(r => (
          <option key={r} value={r}>{r}</option>
        ))}
      </select>
      {error && <p className="text-xs text-red-500 mt-1">{error}</p>}
    </div>
  )
}
