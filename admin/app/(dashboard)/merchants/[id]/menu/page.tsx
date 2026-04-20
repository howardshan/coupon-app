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
    <div>
      <div className="mb-6">
        <Link
          href={`/merchants/${merchantId}`}
          className="mb-3 inline-flex items-center gap-2 px-3 py-2 text-sm font-medium rounded-lg border border-gray-300 bg-white text-gray-700 shadow-sm hover:bg-gray-50"
        >
          ← Back to merchant
        </Link>
        <h1 className="text-2xl font-bold text-gray-900">Menu items</h1>
        <p className="text-sm text-gray-500 mt-1">
          {String(merchant.name)} — product catalog (not deals). Upload images, set prices, or import CSV.
        </p>
      </div>
      <MerchantMenuItemsClient merchantId={merchantId} initialItems={initialItems} />
    </div>
  )
}
