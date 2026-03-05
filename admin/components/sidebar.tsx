'use client'

import Link from 'next/link'
import { usePathname, useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'

interface SidebarProps {
  role: string
  email: string
}

const adminNav = [
  { href: '/dashboard', label: 'Overview', icon: '📊' },
  { href: '/users', label: 'Users', icon: '👥' },
  { href: '/merchants', label: 'Merchants', icon: '🏪' },
  { href: '/deals', label: 'Deals', icon: '🏷️' },
]

const merchantNav = [
  { href: '/dashboard', label: 'Dashboard', icon: '📊' },
  { href: '/deals', label: 'My Deals', icon: '🏷️' },
]

export default function Sidebar({ role, email }: SidebarProps) {
  const pathname = usePathname()
  const router = useRouter()
  const nav = role === 'admin' ? adminNav : merchantNav

  async function handleSignOut() {
    const supabase = createClient()
    await supabase.auth.signOut()
    router.push('/login')
    router.refresh()
  }

  return (
    <aside className="w-56 min-h-screen bg-gray-900 text-white flex flex-col">
      <div className="px-5 py-6 border-b border-gray-700">
        <p className="text-lg font-bold">DealJoy</p>
        <p className="text-xs text-gray-400 mt-0.5 capitalize">{role} Portal</p>
      </div>

      <nav className="flex-1 px-3 py-4 space-y-1">
        {nav.map(item => {
          const active = pathname.startsWith(item.href)
          return (
            <Link
              key={item.href}
              href={item.href}
              className={`flex items-center gap-3 px-3 py-2 rounded-lg text-sm transition-colors ${
                active
                  ? 'bg-blue-600 text-white'
                  : 'text-gray-300 hover:bg-gray-800 hover:text-white'
              }`}
            >
              <span>{item.icon}</span>
              {item.label}
            </Link>
          )
        })}
      </nav>

      <div className="px-4 py-4 border-t border-gray-700">
        <p className="text-xs text-gray-400 truncate mb-3">{email}</p>
        <button
          onClick={handleSignOut}
          className="w-full text-left text-sm text-gray-300 hover:text-white transition-colors"
        >
          Sign out →
        </button>
      </div>
    </aside>
  )
}
