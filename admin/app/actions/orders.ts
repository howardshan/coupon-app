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
  totalCount: number
  redeemedMerchantNames: Record<string, string>
  fetchError: string | null
  refundCount: number
  merchantsForFilter: { id: string; name: string }[]
  customersForFilter: { id: string; email: string }[]
}

export type OrdersListFilters = {
  q?: string
  status?: string[]
  merchantId?: string
  customerId?: string
  dateFrom?: string
  dateTo?: string
  amountMin?: number
  amountMax?: number
  sort?: 'date_desc' | 'date_asc' | 'amount_desc' | 'amount_asc'
  page?: number
  limit?: number
}

const DEFAULT_LIMIT = 20
const MAX_LIMIT = 100

/** 订单列表：支持关键词、状态/商家/日期/金额筛选、排序、分页；URL 持久化 */
export async function getOrdersList(filters: OrdersListFilters = {}): Promise<OrdersListPayload> {
  const supabase = await requireAdmin()
  const adminSupabase = getServiceRoleClient()

  const q = filters.q?.trim() ?? ''
  const status = filters.status?.length ? filters.status : null
  const merchantId = filters.merchantId?.trim() || null
  // 支持 email 或 UUID 输入：如果不是 UUID 格式，按 email 查找 user_id
  let customerId = filters.customerId?.trim() || null
  if (customerId && !customerId.match(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i)) {
    const { data: matchedUser } = await adminSupabase
      .from('users')
      .select('id')
      .ilike('email', customerId)
      .limit(1)
      .maybeSingle()
    customerId = matchedUser?.id ?? 'no-match'
  }
  const dateFrom = filters.dateFrom || null
  const dateTo = filters.dateTo || null
  const amountMin = filters.amountMin
  const amountMax = filters.amountMax
  const sort = filters.sort ?? 'date_desc'
  const page = Math.max(1, filters.page ?? 1)
  const limit = Math.min(MAX_LIMIT, Math.max(1, filters.limit ?? DEFAULT_LIMIT))
  const offset = (page - 1) * limit

  let orders: any[] | null = null
  let totalCount = 0
  let fetchError: string | null = null

  if (q !== '' || status || merchantId || customerId || dateFrom || dateTo || amountMin != null || amountMax != null) {
    const rpcParams: Record<string, unknown> = {
      search_q: q || null,
      p_merchant_ids: merchantId ? [merchantId] : null,
      p_status: status || null,
      p_date_from: dateFrom || null,
      p_date_to: dateTo || null,
      p_amount_min: amountMin ?? null,
      p_amount_max: amountMax ?? null,
      p_sort: sort,
      p_limit: limit,
      p_offset: offset,
      p_customer_id: customerId || null,
    }
    const [listRes, countRes] = await Promise.all([
      supabase.rpc('get_admin_orders_search', rpcParams),
      supabase.rpc('get_admin_orders_count', {
        search_q: q || null,
        p_merchant_ids: merchantId ? [merchantId] : null,
        p_status: status || null,
        p_date_from: dateFrom || null,
        p_date_to: dateTo || null,
        p_amount_min: amountMin ?? null,
        p_amount_max: amountMax ?? null,
        p_customer_id: customerId || null,
      }),
    ])
    if (listRes.error) fetchError = listRes.error.message
    else orders = listRes.data ?? null
    if (countRes.data != null) totalCount = Number(countRes.data)
  } else {
    let query = adminSupabase
      .from('orders')
      .select(
        `
        id,
        order_number,
        total_amount,
        quantity,
        status,
        refund_reason,
        refund_rejected_at,
        created_at,
        users ( email ),
        deals ( id, title, merchants ( name ) ),
        coupons!fk_orders_coupon_id ( redeemed_at_merchant_id, expires_at ),
        order_items ( deal_id, customer_status, deals ( id, title, merchants ( id, name ) ) )
`,
        { count: 'exact' }
      )

    if (merchantId) {
      query = query.eq('deals.merchant_id', merchantId)
    }
    if (customerId) {
      query = query.eq('user_id', customerId)
    }
    if (status && status.length > 0) {
      query = query.in('status', status)
    }
    if (dateFrom) {
      query = query.gte('created_at', dateFrom)
    }
    if (dateTo) {
      const endOfDay = new Date(dateTo)
      endOfDay.setHours(23, 59, 59, 999)
      query = query.lte('created_at', endOfDay.toISOString())
    }
    if (amountMin != null) {
      query = query.gte('total_amount', amountMin)
    }
    if (amountMax != null) {
      query = query.lte('total_amount', amountMax)
    }

    const ascending = sort === 'date_asc' || sort === 'amount_asc'
    if (sort === 'amount_asc' || sort === 'amount_desc') {
      query = query.order('total_amount', { ascending }).order('created_at', { ascending: false })
    } else {
      query = query.order('created_at', { ascending })
    }

    const { data, error, count } = await query.range(offset, offset + limit - 1)
    if (error) fetchError = error.message
    else orders = data
    if (count != null) totalCount = count
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

  const { data: ordersWithDeals } = await adminSupabase
    .from('orders')
    .select('deal_id')
    .limit(500)
  const dealIds = [...new Set((ordersWithDeals ?? []).map((r: { deal_id: string }) => r.deal_id).filter(Boolean))]
  let merchantsForFilterList: { id: string; name: string }[] = []
  if (dealIds.length > 0) {
    const { data: dealRows } = await adminSupabase
      .from('deals')
      .select('merchant_id')
      .in('id', dealIds)
    const merchantIds = new Set<string>((dealRows ?? []).map((r: { merchant_id: string }) => r.merchant_id).filter(Boolean))
    if (merchantIds.size > 0) {
      const { data: names } = await adminSupabase
        .from('merchants')
        .select('id, name')
        .in('id', Array.from(merchantIds))
        .order('name')
      merchantsForFilterList = names ?? []
    }
  }
  // 获取有订单的客户列表用于过滤
  const { data: orderUsers } = await adminSupabase
    .from('orders')
    .select('user_id')
    .limit(500)
  const userIds = [...new Set((orderUsers ?? []).map((r: { user_id: string }) => r.user_id).filter(Boolean))]
  let customersForFilterList: { id: string; email: string }[] = []
  if (userIds.length > 0) {
    const { data: userRows } = await adminSupabase
      .from('users')
      .select('id, email')
      .in('id', userIds)
      .order('email')
    customersForFilterList = (userRows ?? []).map((u: { id: string; email: string }) => ({ id: u.id, email: u.email }))
  }

  return {
    orders,
    totalCount,
    redeemedMerchantNames,
    fetchError,
    refundCount,
    merchantsForFilter: merchantsForFilterList,
    customersForFilter: customersForFilterList,
  }
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
