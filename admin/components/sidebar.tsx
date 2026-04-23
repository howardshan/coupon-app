'use client'

import Link from 'next/link'
import { usePathname, useRouter } from 'next/navigation'
import { useEffect, useState } from 'react'
import { APP_DISPLAY_NAME } from '@/lib/app-branding'
import { createClient } from '@/lib/supabase/client'

interface SidebarProps {
  role: string
  email: string
  pendingCount?: number
  /** 导航链接被点击时回调（用于移动端关闭抽屉） */
  onNavigate?: () => void
  /** 移动端加大可点击区域 */
  mobileTouchTargets?: boolean
}

type NavLink = { kind: 'link'; href: string; label: string; icon: string }
type NavGroup = { kind: 'group'; label: string; icon: string; children: { href: string; label: string }[] }
type NavEntry = NavLink | NavGroup

const adminNav: NavEntry[] = [
  { kind: 'link', href: '/dashboard', label: 'Overview', icon: '📊' },
  { kind: 'link', href: '/users', label: 'Users', icon: '👥' },
  { kind: 'link', href: '/merchants', label: 'Merchants', icon: '🏪' },
  { kind: 'link', href: '/brands', label: 'Brands', icon: '🏢' },
  { kind: 'link', href: '/deals', label: 'Deals', icon: '🏷️' },
  { kind: 'link', href: '/orders', label: 'Orders', icon: '📦' },
  { kind: 'link', href: '/approvals', label: 'Approvals', icon: '✅' },
  {
    kind: 'group', label: 'Finance', icon: '💰',
    children: [
      { href: '/finance', label: 'Withdrawals' },
      { href: '/finance/tax-revenue', label: 'Tax Revenue' },
      { href: '/finance/store-credits', label: 'Store Credits' },
    ],
  },
  {
    kind: 'group', label: 'Ads', icon: '📣',
    children: [
      { href: '/ads', label: 'Campaigns' },
      { href: '/ads/accounts', label: 'Accounts' },
      { href: '/ads/revenue', label: 'Revenue' },
    ],
  },
  { kind: 'link', href: '/closures', label: 'Closures', icon: '🔒' },
  { kind: 'link', href: '/support', label: 'Support', icon: '💬' },
  { kind: 'link', href: '/tax-rates', label: 'Tax Rates', icon: '🧾' },
  { kind: 'link', href: '/regions', label: 'Regions', icon: '🗺️' },
  {
    kind: 'group', label: 'Content', icon: '🎨',
    children: [
      { href: '/settings/splash', label: 'Splash Screen' },
      { href: '/settings/onboarding', label: 'Onboarding' },
      { href: '/settings/banner', label: 'Homepage Banner' },
    ],
  },
  {
    kind: 'group', label: 'Settings', icon: '⚙️',
    children: [
      { href: '/settings/categories', label: 'Categories' },
      { href: '/settings/email-types', label: 'Email Types' },
      { href: '/settings/email-logs', label: 'Email Logs' },
      { href: '/settings/algorithm', label: 'Algorithm' },
      { href: '/settings/search-ranking', label: 'Search Ranking' },
      { href: '/settings/legal', label: 'Legal Docs' },
    ],
  },
]

const merchantNav: NavLink[] = [
  { kind: 'link', href: '/dashboard', label: 'Dashboard', icon: '📊' },
  { kind: 'link', href: '/deals', label: 'My Deals', icon: '🏷️' },
]

function isGroupActive(children: { href: string }[], pathname: string) {
  return children.some(c => pathname === c.href || pathname.startsWith(`${c.href}/`))
}

const navItemClass = (active: boolean, touch: boolean) =>
  `flex items-center gap-3 rounded-lg text-sm transition-colors ${
    touch ? 'min-h-[44px] px-3 py-2 md:min-h-0 md:py-2' : 'px-3 py-2'
  } ${
    active ? 'bg-blue-600 text-white' : 'text-gray-300 hover:bg-gray-800 hover:text-white'
  }`

const childLinkClass = (active: boolean, touch: boolean) =>
  `flex items-center rounded-lg text-sm transition-colors ${
    touch ? 'min-h-[44px] px-3 py-2 md:min-h-0 md:py-2' : 'px-3 py-2'
  } ${
    active ? 'bg-blue-600 text-white' : 'text-gray-400 hover:bg-gray-800 hover:text-white'
  }`

export default function Sidebar({
  role,
  email,
  pendingCount = 0,
  onNavigate,
  mobileTouchTargets = false,
}: SidebarProps) {
  const pathname = usePathname()
  const router = useRouter()
  const nav = role === 'admin' ? adminNav : null

  // 追踪哪些 group 是展开的（按 label 索引）
  const [openGroups, setOpenGroups] = useState<Record<string, boolean>>(() => {
    // 初始化：当前路径所属的 group 自动展开
    const init: Record<string, boolean> = {}
    if (nav) {
      for (const entry of nav) {
        if (entry.kind === 'group' && isGroupActive(entry.children, pathname)) {
          init[entry.label] = true
        }
      }
    }
    return init
  })

  useEffect(() => {
    // 路径变化时自动展开对应 group
    if (!nav) return
    for (const entry of nav) {
      if (entry.kind === 'group' && isGroupActive(entry.children, pathname)) {
        setOpenGroups(prev => ({ ...prev, [entry.label]: true }))
      }
    }
  }, [pathname])

  async function handleSignOut() {
    const supabase = createClient()
    await supabase.auth.signOut()
    router.push('/login')
    router.refresh()
  }

  return (
    <aside className="flex h-full min-h-0 w-56 flex-col bg-gray-900 text-white">
      <div className="shrink-0 border-b border-gray-700 px-5 py-6">
        <p className="text-lg font-bold">{APP_DISPLAY_NAME}</p>
        <p className="text-xs text-gray-400 mt-0.5 capitalize">{role} Portal</p>
      </div>

      <nav className="min-h-0 flex-1 space-y-1 overflow-y-auto px-3 py-4">
        {role === 'admin' && nav
          ? nav.map(entry => {
              if (entry.kind === 'link') {
                const active = pathname === entry.href || pathname.startsWith(`${entry.href}/`)
                return (
                  <Link
                    key={entry.href}
                    href={entry.href}
                    onClick={() => onNavigate?.()}
                    className={navItemClass(active, mobileTouchTargets)}
                  >
                    <span>{entry.icon}</span>
                    <span className="flex-1">{entry.label}</span>
                    {/* Approvals 专属待审批角标 */}
                    {entry.href === '/approvals' && pendingCount > 0 && (
                      <span className="min-w-[20px] h-5 px-1.5 rounded-full bg-red-500 text-white text-xs font-bold flex items-center justify-center leading-none">
                        {pendingCount > 99 ? '99+' : pendingCount}
                      </span>
                    )}
                  </Link>
                )
              }

              // 可折叠分组
              const groupActive = isGroupActive(entry.children, pathname)
              const isOpen = groupActive || !!openGroups[entry.label]
              return (
                <div key={entry.label} className="space-y-0.5">
                  <button
                    type="button"
                    onClick={() => setOpenGroups(prev => ({ ...prev, [entry.label]: !prev[entry.label] }))}
                    className={`flex w-full items-center gap-3 rounded-lg text-sm transition-colors ${
                      mobileTouchTargets ? 'min-h-[44px] px-3 py-2 md:min-h-0 md:py-2' : 'px-3 py-2'
                    } text-left ${
                      groupActive
                        ? 'bg-gray-800 text-white'
                        : 'text-gray-300 hover:bg-gray-800 hover:text-white'
                    }`}
                    aria-expanded={isOpen}
                  >
                    <span>{entry.icon}</span>
                    <span className="flex-1">{entry.label}</span>
                    <span className="text-xs text-gray-500">{isOpen ? '▾' : '▸'}</span>
                  </button>
                  {isOpen && (
                    <div className="ml-4 pl-3 border-l border-gray-700 space-y-0.5">
                      {entry.children.map(child => {
                        const childActive =
                          pathname === child.href || pathname.startsWith(`${child.href}/`)
                        return (
                          <Link
                            key={child.href}
                            href={child.href}
                            onClick={() => onNavigate?.()}
                            className={childLinkClass(childActive, mobileTouchTargets)}
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
                  onClick={() => onNavigate?.()}
                  className={navItemClass(active, mobileTouchTargets)}
                >
                  <span>{item.icon}</span>
                  {item.label}
                </Link>
              )
            })}
      </nav>

      <div className="shrink-0 border-t border-gray-700 px-4 py-4">
        <p className="text-xs text-gray-400 truncate mb-3">{email}</p>
        <button
          type="button"
          onClick={() => {
            onNavigate?.()
            void handleSignOut()
          }}
          className={`w-full text-left text-sm text-gray-300 transition-colors hover:text-white ${
            mobileTouchTargets ? 'min-h-[44px] py-2 md:min-h-0' : ''
          }`}
        >
          Sign out →
        </button>
      </div>
    </aside>
  )
}
