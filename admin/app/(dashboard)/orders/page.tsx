import { createClient } from '@/lib/supabase/server'
import { getServiceRoleClient } from '@/lib/supabase/service'
import { redirect } from 'next/navigation'
import OrdersPageClient from '@/components/orders-page-client'
import { OrdersSearchProvider } from '@/contexts/orders-search-context'

export const dynamic = 'force-dynamic'

export default async function OrdersPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string }>
}) {
  const { q } = await searchParams
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  const { data: profile } = await supabase
    .from('users')
    .select('role')
    .eq('id', user!.id)
    .single()

  if (profile?.role !== 'admin') redirect('/dashboard')

  const adminSupabase = getServiceRoleClient()
  let orders: any[] | null = null
  let fetchError: string | null = null

  if (q != null && q.trim() !== '') {
    const { data, error } = await supabase.rpc('get_admin_orders_search', { search_q: q.trim() })
    if (error) {
      fetchError = error.message
      console.error('[Orders] get_admin_orders_search error:', error)
    } else {
      orders = data ?? null
    }
  } else {
    const { data, error } = await adminSupabase
      .from('orders')
      .select(`
        id,
        order_number,
        total_amount,
        quantity,
        status,
        refund_reason,
        refund_rejected_at,
        created_at,
        users ( email ),
        deals ( title, merchants ( name ) ),
        coupons!fk_orders_coupon_id ( redeemed_at_merchant_id, expires_at )
      `)
      .order('created_at', { ascending: false })
      .limit(100)
    if (error) {
      fetchError = error.message
      console.error('[Orders] orders select error:', error)
    } else {
      orders = data
    }
  }

  const redeemedMerchantIds = new Set<string>()
  if (orders) {
    for (const o of orders) {
      const raw = o.coupons
      const list = Array.isArray(raw) ? raw : raw != null ? [raw] : []
      for (const c of list) {
        if (c?.redeemed_at_merchant_id) redeemedMerchantIds.add(c.redeemed_at_merchant_id)
      }
    }
  }

  let redeemedMerchantNames: Record<string, string> = {}
  if (redeemedMerchantIds.size > 0) {
    const { data: merchants } = await adminSupabase
      .from('merchants')
      .select('id, name')
      .in('id', Array.from(redeemedMerchantIds))
    if (merchants) {
      for (const m of merchants) {
        redeemedMerchantNames[m.id] = m.name
      }
    }
  }

  const refundCount = orders?.filter((o: { status: string }) => o.status === 'refund_requested').length ?? 0

  return (
    <OrdersSearchProvider>
      <OrdersPageClient
        orders={orders}
        redeemedMerchantNames={redeemedMerchantNames}
        fetchError={fetchError}
        refundCount={refundCount}
        initialSearchQ={q ?? ''}
      />
    </OrdersSearchProvider>
  )
}
