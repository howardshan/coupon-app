import type { CSSProperties } from 'react'
import { createClient } from '@/lib/supabase/server'
import { getServiceRoleClient } from '@/lib/supabase/service'
import { redirect, notFound } from 'next/navigation'
import Link from 'next/link'
import MerchantMenuItemsClient from '@/components/merchant-menu-items-client'
import type { MenuItemRow } from '@/app/actions/menu-items'

export default async function MerchantMenuPage({ params }: { params: Promise<{ id: string }> }) {
  const { id: merchantId } = await params
  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) redirect('/login')
  const { data: profile } = await supabase.from('users').select('role').eq('id', user.id).single()
  if (profile?.role !== 'admin') redirect('/dashboard')

  const { data: merchant } = await supabase
    .from('merchants')
    .select('id, name')
    .eq('id', merchantId)
    .maybeSingle()
  if (!merchant) notFound()

  const db = getServiceRoleClient()
  const { data: rows, error } = await db
    .from('menu_items')
    .select('id, merchant_id, name, name_normalized, image_url, price, category, sort_order, created_at')
    .eq('merchant_id', merchantId)
    .order('sort_order', { ascending: true })
    .order('created_at', { ascending: true })
  if (error) {
    return (
      <div className="text-red-600 p-4">
        Failed to load menu items. Run DB migration if <code>name_normalized</code> is missing: {error.message}
      </div>
    )
  }

  const initialItems: MenuItemRow[] = (rows ?? []) as MenuItemRow[]

  return (
    <div
      className="menu-catalog-root menu-catalog-animate-in max-w-6xl space-y-8 pb-12"
      style={
        {
          ['--catalog-accent' as string]: '#0d9488',
          ['--catalog-accent-muted' as string]: '#ccfbf1',
        } as CSSProperties
      }
    >
      <header className="relative overflow-hidden rounded-2xl border border-stone-200/90 bg-gradient-to-br from-stone-50 via-white to-teal-50/40 px-6 py-8 shadow-[0_1px_0_rgba(15,23,42,0.04),0_12px_40px_-12px_rgba(15,23,42,0.12)]">
        <div
          className="pointer-events-none absolute -right-16 -top-16 h-48 w-48 rounded-full opacity-[0.07]"
          style={{ background: 'radial-gradient(circle, var(--catalog-accent) 0%, transparent 70%)' }}
          aria-hidden
        />
        <Link
          href={`/merchants/${merchantId}`}
          className="relative mb-5 inline-flex items-center gap-2 rounded-lg border border-stone-200/90 bg-white/90 px-3.5 py-2 text-sm font-medium text-stone-700 shadow-sm backdrop-blur-sm transition hover:border-stone-300 hover:bg-white"
        >
          <span aria-hidden className="text-stone-400">
            ←
          </span>
          Back to merchant
        </Link>
        <p className="relative text-[11px] font-semibold uppercase tracking-[0.2em] text-teal-800/80">
          Product catalog
        </p>
        <h1 className="relative mt-1 font-sans text-3xl font-bold tracking-tight text-stone-900 md:text-[2rem]">
          Menu items
        </h1>
        <p className="relative mt-3 max-w-2xl text-sm leading-relaxed text-stone-600">
          <span className="font-medium text-stone-800">{String(merchant.name)}</span>
          {' — '}
          Store-facing dishes (not deals). Batch-upload photos by filename, set prices inline, or sync prices from
          CSV.
        </p>
      </header>

      <MerchantMenuItemsClient merchantId={merchantId} initialItems={initialItems} />
    </div>
  )
}
