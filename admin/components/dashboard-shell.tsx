'use client'

import { useEffect, useState } from 'react'
import { usePathname } from 'next/navigation'
import { APP_DISPLAY_NAME } from '@/lib/app-branding'
import Sidebar from '@/components/sidebar'

type DashboardShellProps = {
  children: React.ReactNode
  role: string
  email: string
  pendingCount: number
}

export default function DashboardShell({ children, role, email, pendingCount }: DashboardShellProps) {
  const pathname = usePathname()
  const [mobileNavOpen, setMobileNavOpen] = useState(false)

  useEffect(() => {
    setMobileNavOpen(false)
  }, [pathname])

  useEffect(() => {
    if (!mobileNavOpen) return
    const mq = window.matchMedia('(max-width: 767px)')
    if (!mq.matches) return
    const prev = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    return () => {
      document.body.style.overflow = prev
    }
  }, [mobileNavOpen])

  useEffect(() => {
    if (!mobileNavOpen) return
    function onKey(e: KeyboardEvent) {
      if (e.key === 'Escape') setMobileNavOpen(false)
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [mobileNavOpen])

  return (
    // 桌面端锁视口高度，避免长页面时侧栏仅 min-h-screen 与主区不同高而「断开」；滚动只在 main 内
    <div className="flex min-h-screen flex-col bg-gray-50 md:h-screen md:max-h-screen md:min-h-0 md:flex-row md:overflow-hidden">
      <header className="sticky top-0 z-30 flex h-14 shrink-0 items-center gap-3 border-b border-gray-200 bg-white px-4 md:hidden">
        <button
          type="button"
          onClick={() => setMobileNavOpen(true)}
          className="inline-flex h-11 min-w-[44px] items-center justify-center rounded-lg border border-gray-200 bg-white text-gray-800 hover:bg-gray-50"
          aria-label="Open menu"
          aria-expanded={mobileNavOpen}
          aria-controls="admin-sidebar-nav"
        >
          <span className="text-lg leading-none" aria-hidden>
            ☰
          </span>
        </button>
        <span className="truncate text-base font-semibold text-gray-900">{APP_DISPLAY_NAME}</span>
      </header>

      {mobileNavOpen && (
        <button
          type="button"
          className="fixed inset-0 z-40 bg-black/50 md:hidden"
          aria-label="Close menu"
          onClick={() => setMobileNavOpen(false)}
        />
      )}

      <div
        id="admin-sidebar-nav"
        className={
          'fixed inset-y-0 left-0 z-50 w-56 max-w-[85vw] transform bg-gray-900 transition-transform duration-200 ease-out md:static md:z-auto md:h-full md:min-h-0 md:max-w-none md:flex-shrink-0 md:self-stretch md:translate-x-0 md:bg-transparent ' +
          (mobileNavOpen ? 'translate-x-0' : '-translate-x-full md:translate-x-0')
        }
      >
        <Sidebar
          role={role}
          email={email}
          pendingCount={pendingCount}
          onNavigate={() => setMobileNavOpen(false)}
          mobileTouchTargets
        />
      </div>

      <main className="min-h-0 min-w-0 flex-1 overflow-y-auto overflow-x-hidden p-4 sm:p-6 lg:p-8">
        {children}
      </main>
    </div>
  )
}
