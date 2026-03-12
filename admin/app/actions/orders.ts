'use server'

import { revalidatePath } from 'next/cache'
import { createClient } from '@/lib/supabase/server'
import { getServiceRoleClient } from '@/lib/supabase/service'

async function requireAdmin() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) throw new Error('Unauthorized')

  const { data: profile } = await supabase
    .from('users')
    .select('role')
    .eq('id', user.id)
    .single()

  if (profile?.role !== 'admin') throw new Error('Forbidden')
  return supabase
}

export type OrdersListPayload = {
  orders: any[] | null
  redeemedMerchantNames: Record<string, string>
  fetchError: string | null
  refundCount: number
}

/** 供订单总览「局部搜索」使用：按关键词拉取订单列表，不触发整页刷新 */
export async function getOrdersList(searchQ?: string): Promise<OrdersListPayload> {
  const supabase = await requireAdmin()
  const adminSupabase = getServiceRoleClient()

  const q = searchQ?.trim() ?? ''
  let orders: any[] | null = null
  let fetchError: string | null = null

  if (q !== '') {
    const { data, error } = await supabase.rpc('get_admin_orders_search', { search_q: q })
    if (error) {
      fetchError = error.message
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

  return { orders, redeemedMerchantNames, fetchError, refundCount }
}

/** 管理员通过退款：调用 create-refund Edge Function 执行 Stripe 退款并更新订单/券/支付状态 */
export async function approveRefund(orderId: string) {
  await requireAdmin()

  const supabase = getServiceRoleClient()
  const { data, error } = await supabase.functions.invoke('create-refund', {
    body: { orderId },
  })

  if (error) throw new Error(error.message)

  const body = data as { error?: string } | null
  if (body?.error) throw new Error(body.error)

  revalidatePath('/orders')
  revalidatePath(`/orders/${orderId}`)
}

/** 管理员拒绝退款：订单状态改回 unused，并写入 refund_rejected_at 供详情页展示 Refund Rejected */
export async function rejectRefund(orderId: string) {
  await requireAdmin()

  const supabase = getServiceRoleClient()
  const { error } = await supabase
    .from('orders')
    .update({
      status: 'unused',
      refund_rejected_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    })
    .eq('id', orderId)

  if (error) throw new Error(error.message)
  revalidatePath('/orders')
  revalidatePath(`/orders/${orderId}`)
}
