'use client'

import Link from 'next/link'
import { usePathname, useRouter } from 'next/navigation'
import { useEffect, useState } from 'react'
import { createClient } from '@/lib/supabase/client'

interface SidebarProps {
  role: string
  email: string
}

const adminNav = [
  { href: '/dashboard', label: 'Overview', icon: '📊' },
  { href: '/users', label: 'Users', icon: '👥' },
  { href: '/merchants', label: 'Merchants', icon: '🏪' },
  { href: '/brands', label: 'Brands', icon: '🏢' },
  { href: '/deals', label: 'Deals', icon: '🏷️' },
  { href: '/orders', label: 'Orders', icon: '📦' },
  { href: '/finance', label: 'Finance', icon: '💰' },
  { href: '/closures', label: 'Closures', icon: '🔒' },
  { href: '/support', label: 'Support', icon: '💬' },
  { href: '/tax-rates', label: 'Tax Rates', icon: '🧾' },
]

const merchantNav: NavLink[] = [
  { href: '/dashboard', label: 'Dashboard', icon: '📊' },
  { href: '/deals', label: 'My Deals', icon: '🏷️' },
]

function isOnEmailRoute(pathname: string) {
  return (
    pathname.startsWith('/settings/email-types') ||
    pathname.startsWith('/settings/email-logs')
  )
}

export default function Sidebar({ role, email }: SidebarProps) {
  const pathname = usePathname()
  const router = useRouter()
  const nav = role === 'admin' ? adminNav : null

  const onEmailRoute = isOnEmailRoute(pathname)
  const [emailGroupOpen, setEmailGroupOpen] = useState(onEmailRoute)

  useEffect(() => {
    if (onEmailRoute) setEmailGroupOpen(true)
  }, [onEmailRoute])

  async function handleSignOut() {
    const supabase = createClient()
    await supabase.auth.signOut()
    router.push('/login')
    router.refresh()
  }

  const showEmailChildren = onEmailRoute || emailGroupOpen

  return (
    <aside className="w-56 min-h-screen bg-gray-900 text-white flex flex-col">
      <div className="px-5 py-6 border-b border-gray-700">
        <p className="text-lg font-bold">DealJoy</p>
        <p className="text-xs text-gray-400 mt-0.5 capitalize">{role} Portal</p>
      </div>

      <nav className="flex-1 px-3 py-4 space-y-1">
        {role === 'admin' && nav
          ? nav.map(entry => {
              if (entry.kind === 'link') {
                const active = pathname === entry.href || pathname.startsWith(`${entry.href}/`)
                return (
                  <Link
                    key={entry.href}
                    href={entry.href}
                    className={`flex items-center gap-3 px-3 py-2 rounded-lg text-sm transition-colors ${
                      active
                        ? 'bg-blue-600 text-white'
                        : 'text-gray-300 hover:bg-gray-800 hover:text-white'
                    }`}
                  >
                    <span>{entry.icon}</span>
                    {entry.label}
                  </Link>
                )
              }

              // Email 分组
              const groupActive = entry.children.some(
                c => pathname === c.href || pathname.startsWith(`${c.href}/`)
              )
              return (
                <div key={entry.label} className="space-y-0.5">
                  <button
                    type="button"
                    onClick={() => setEmailGroupOpen(o => !o)}
                    className={`flex items-center gap-3 px-3 py-2 rounded-lg text-sm transition-colors w-full text-left ${
                      groupActive
                        ? 'bg-gray-800 text-white'
                        : 'text-gray-300 hover:bg-gray-800 hover:text-white'
                    }`}
                    aria-expanded={showEmailChildren}
                  >
                    <span>{entry.icon}</span>
                    <span className="flex-1">{entry.label}</span>
                    <span className="text-xs text-gray-500">{showEmailChildren ? '▾' : '▸'}</span>
                  </button>
                  {showEmailChildren && (
                    <div className="ml-4 pl-3 border-l border-gray-700 space-y-0.5">
                      {entry.children.map(child => {
                        const childActive =
                          pathname === child.href || pathname.startsWith(`${child.href}/`)
                        return (
                          <Link
                            key={child.href}
                            href={child.href}
                            className={`flex items-center px-3 py-2 rounded-lg text-sm transition-colors ${
                              childActive
                                ? 'bg-blue-600 text-white'
                                : 'text-gray-400 hover:bg-gray-800 hover:text-white'
                            }`}
                          >
                            {child.label}
                          </Link>
                        )
                      })}
                    </div>
                  )}
                </div>
              )
            })
          : merchantNav.map(item => {
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
