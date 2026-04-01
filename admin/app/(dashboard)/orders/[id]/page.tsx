import { createClient } from '@/lib/supabase/server'
import { redirect, notFound } from 'next/navigation'
import Link from 'next/link'
import OrderRefundButtons from '@/components/order-refund-buttons'
import OrderDetailPricingCard from '@/components/order-detail-pricing-card'
import OrderDetailCustomerSidebar, {
  type OrderCustomerSummary,
} from '@/components/order-detail-customer-sidebar'
import { getOrderDetailStatusTags, STATUS_STYLES, STATUS_LABELS } from '@/lib/order-display-status'
import {
  buildDealPriceLines,
  computePaymentSplit,
  computeRefundSummary,
  computeV2RefundSummaryFromCoupons,
  serviceFeeLineLabel,
} from '@/lib/order-detail-display'

// V3 order_item 的 customer_status 状态样式
const ITEM_STATUS_STYLES: Record<string, string> = {
  unused: 'bg-blue-100 text-blue-700',
  used: 'bg-green-100 text-green-700',
  expired: 'bg-red-100 text-red-700',
  refund_pending: 'bg-amber-100 text-amber-700',
  refund_processing: 'bg-sky-100 text-sky-800',
  refund_review: 'bg-orange-100 text-orange-700',
  refund_reject: 'bg-amber-100 text-amber-700',
  refund_success: 'bg-purple-100 text-purple-700',
  gifted: 'bg-pink-100 text-pink-700',
}

const ITEM_STATUS_LABELS: Record<string, string> = {
  unused: 'Unused',
  used: 'Redeemed',
  expired: 'Expired',
  refund_pending: 'Refund Pending',
  refund_processing: 'Refund Processing',
  refund_review: 'Refund Review',
  refund_reject: 'Refund Rejected',
  refund_success: 'Refunded',
  gifted: 'Gifted',
}

// coupon_gifts 的 gift_status 样式
const GIFT_STATUS_STYLES: Record<string, string> = {
  pending: 'bg-yellow-100 text-yellow-700',
  claimed: 'bg-green-100 text-green-700',
  recalled: 'bg-gray-100 text-gray-600',
  expired: 'bg-red-100 text-red-700',
}

const GIFT_STATUS_LABELS: Record<string, string> = {
  pending: 'Pending',
  claimed: 'Claimed',
  recalled: 'Recalled',
  expired: 'Expired',
}

export default async function OrderDetailPage({
  params,
}: {
  params: Promise<{ id: string }>
}) {
  const { id } = await params
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  const { data: profile } = await supabase.from('users').select('role').eq('id', user!.id).single()

  if (profile?.role !== 'admin') redirect('/dashboard')

  const { data: order } = await supabase
    .from('orders')
    .select(`
      id,
      user_id,
      order_number,
      quantity,
      unit_price,
      total_amount,
      items_amount,
      service_fee_total,
      status,
      payment_intent_id,
      refund_reason,
      created_at,
      updated_at,
      refund_requested_at,
      refunded_at,
      refund_rejected_at,
      store_credit_used,
      paid_at,
      users ( id, email, full_name, username, role, avatar_url, phone, created_at ),
      deals ( id, title, discount_price, applicable_merchant_ids, merchants ( id, name ) ),
      coupons!fk_orders_coupon_id ( redeemed_at_merchant_id, expires_at ),
      order_items (
        id, deal_id, unit_price, service_fee,
        customer_status, merchant_status,
        redeemed_merchant_id, redeemed_at, redeemed_by,
        refunded_at, refund_reason, refund_amount, refund_method,
        deals ( id, title, discount_price, merchants ( id, name ) ),
        coupons!order_items_coupon_id_fkey ( id, qr_code, coupon_code, status, expires_at, used_at, is_gifted, current_holder_user_id ),
        coupon_gifts ( id, recipient_user_id, recipient_email, recipient_phone, gift_message, status, claimed_at, recalled_at, created_at )
      )
    `)
    .eq('id', id)
    .single()

  if (!order) notFound()

  const customerSummary: OrderCustomerSummary | null = (() => {
    const raw = order.users as unknown
    const u = Array.isArray(raw) ? raw[0] : raw
    if (!u || typeof u !== 'object' || !('id' in u) || !(u as { id: unknown }).id) return null
    const o = u as Record<string, unknown>
    return {
      id: String(o.id),
      email: (o.email as string | null) ?? null,
      full_name: (o.full_name as string | null) ?? null,
      username: (o.username as string | null) ?? null,
      role: (o.role as string | null) ?? null,
      avatar_url: (o.avatar_url as string | null) ?? null,
      phone: (o.phone as string | null) ?? null,
      created_at: (o.created_at as string | null) ?? null,
    }
  })()
  const orderItems = (order as any).order_items as any[] | null
  const hasV3Items = orderItems && orderItems.length > 0

  // V3：按 deal 分组
  type DealGroup = {
    dealId: string
    dealTitle: string
    merchantId: string | null
    merchantName: string | null
    unitPrice: number
    items: any[]
  }
  let dealGroups: DealGroup[] = []
  if (hasV3Items) {
    const groupMap = new Map<string, DealGroup>()
    for (const item of orderItems) {
      const d = item.deals as any
      const m = Array.isArray(d?.merchants) ? d.merchants[0] : d?.merchants
      const key = item.deal_id
      if (!groupMap.has(key)) {
        groupMap.set(key, {
          dealId: d?.id ?? item.deal_id,
          dealTitle: d?.title ?? '—',
          merchantId: m?.id ?? null,
          merchantName: m?.name ?? null,
          unitPrice: Number(item.unit_price),
          items: [],
        })
      }
      groupMap.get(key)!.items.push(item)
    }
    dealGroups = Array.from(groupMap.values())
  }

  // V2 兼容：旧订单
  const deal = order.deals as any
  const merchant = Array.isArray(deal?.merchants) ? deal.merchants[0] : deal?.merchants

  // 核销门店信息 + 券过期时间（用于多维度状态）—— 仅 V2
  const raw = order.coupons
  const first = Array.isArray(raw) ? raw[0] : raw
  const redeemedMerchantId = first?.redeemed_at_merchant_id
  const orderForDisplay = {
    status: order.status as string,
    refund_rejected_at: (order as { refund_rejected_at?: string | null }).refund_rejected_at,
    coupon_expires_at: first?.expires_at ?? null,
    deals: order.deals as { expires_at?: string | null } | null,
  }
  const detailStatusTags = hasV3Items ? [] : getOrderDetailStatusTags(orderForDisplay)

  let redeemedMerchantName: string | null = null
  if (!hasV3Items && redeemedMerchantId) {
    const { data: rm } = await supabase.from('merchants').select('name').eq('id', redeemedMerchantId).single()
    redeemedMerchantName = rm?.name ?? null
  }

  // V2: 查询该订单的所有 coupons（通过 coupons.order_id）
  let v2Coupons: any[] = []
  const v2RedeemedMerchantNames: Record<string, string> = {}
  if (!hasV3Items) {
    const { data: couponsData } = await supabase
      .from('coupons')
      .select('id, qr_code, coupon_code, status, expires_at, used_at, verified_by, redeemed_at_merchant_id, gifted_from, is_gifted, current_holder_user_id, void_reason, voided_at')
      .eq('order_id', id)
      .order('created_at', { ascending: true })
    v2Coupons = couponsData ?? []

    // 批量查询核销门店名称
    const v2MerchantIds = new Set<string>()
    for (const c of v2Coupons) {
      if (c.redeemed_at_merchant_id) v2MerchantIds.add(c.redeemed_at_merchant_id)
    }
    if (v2MerchantIds.size > 0) {
      const { data: ms } = await supabase.from('merchants').select('id, name').in('id', Array.from(v2MerchantIds))
      for (const m of ms ?? []) {
        v2RedeemedMerchantNames[m.id] = m.name
      }
    }
  }

  // V3：批量查询核销门店名称
  const redeemedMerchantNames: Record<string, string> = {}
  if (hasV3Items) {
    const ids = new Set<string>()
    for (const item of orderItems) {
      if (item.redeemed_merchant_id) ids.add(item.redeemed_merchant_id)
    }
    if (ids.size > 0) {
      const { data: merchants } = await supabase.from('merchants').select('id, name').in('id', Array.from(ids))
      for (const m of merchants ?? []) {
        redeemedMerchantNames[m.id] = m.name
      }
    }
  }

  // V3: 查询 gifted 券的受赠人信息和受赠人券状态
  // gifted_from 字段指向原始券 id，受赠人的新券通过此字段关联
  const giftRecipientCouponStatus: Record<string, { status: string; usedAt: string | null; refundedAt: string | null; refundAmount: number | null; refundMethod: string | null }> = {}
  const recipientUserEmails: Record<string, string> = {}
  if (hasV3Items) {
    // 收集 gifted 状态的 order_item 对应的 coupon ids
    const giftedCouponIds: string[] = []
    const recipientUserIds = new Set<string>()
    for (const item of orderItems) {
      if (item.customer_status === 'gifted') {
        const coupon = Array.isArray(item.coupons) ? item.coupons[0] : item.coupons
        if (coupon?.id) giftedCouponIds.push(coupon.id)
        const gift = Array.isArray(item.coupon_gifts) ? item.coupon_gifts[0] : item.coupon_gifts
        if (gift?.recipient_user_id) recipientUserIds.add(gift.recipient_user_id)
      }
    }
    // 查询受赠人的新券（通过 gifted_from 关联到原始券）
    if (giftedCouponIds.length > 0) {
      const { data: recipientCoupons } = await supabase
        .from('coupons')
        .select('id, gifted_from, status, used_at, order_item_id')
        .in('gifted_from', giftedCouponIds)
      for (const rc of recipientCoupons ?? []) {
        if (rc.gifted_from) {
          // 尝试获取 order_item 级别的退款信息
          let refundedAt: string | null = null
          let refundAmount: number | null = null
          let refundMethod: string | null = null
          if (rc.order_item_id && rc.status === 'refunded') {
            const { data: ri } = await supabase
              .from('order_items')
              .select('refunded_at, refund_amount, refund_method')
              .eq('id', rc.order_item_id)
              .single()
            if (ri) {
              refundedAt = ri.refunded_at
              refundAmount = ri.refund_amount ? Number(ri.refund_amount) : null
              refundMethod = ri.refund_method
            }
          }
          giftRecipientCouponStatus[rc.gifted_from] = {
            status: rc.status,
            usedAt: rc.used_at,
            refundedAt,
            refundAmount,
            refundMethod,
          }
        }
      }
    }
    // 查询受赠人 email
    if (recipientUserIds.size > 0) {
      const { data: recipientUsers } = await supabase
        .from('users')
        .select('id, email')
        .in('id', Array.from(recipientUserIds))
      for (const u of recipientUsers ?? []) {
        recipientUserEmails[u.id] = u.email
      }
    }
  }

  // 适用门店（仅 V2）
  const applicableIds = deal?.applicable_merchant_ids as string[] | null
  let applicableStores: { id: string; name: string }[] = []
  if (!hasV3Items && applicableIds && applicableIds.length > 0) {
    const { data } = await supabase.from('merchants').select('id, name').in('id', applicableIds)
    applicableStores = data ?? []
  }

  // V3 汇总状态
  const v3StatusSummary = hasV3Items
    ? (() => {
        const counts: Record<string, number> = {}
        for (const item of orderItems) {
          const s = item.customer_status as string
          counts[s] = (counts[s] ?? 0) + 1
        }
        return counts
      })()
    : null

  const orderNumberDisplay = (order.order_number as string | null) ?? id.slice(0, 8)
  const storeCreditUsed = Number((order as { store_credit_used?: number | string | null }).store_credit_used ?? 0)
  const paidAt = (order as { paid_at?: string | null }).paid_at ?? null
  const totalAmt = Number(order.total_amount ?? 0)
  const paymentSplit = computePaymentSplit(totalAmt, storeCreditUsed)

  const pricingRefundSummary =
    hasV3Items && orderItems
      ? computeRefundSummary(
          orderItems.map((i) => ({
            customer_status: String(i.customer_status ?? ''),
            refund_method: i.refund_method ?? null,
            refund_amount: i.refund_amount ?? null,
            unit_price: i.unit_price ?? null,
            service_fee: i.service_fee,
          }))
        )
      : computeV2RefundSummaryFromCoupons(v2Coupons, Number(order.unit_price ?? 0))

  const v2PriceLines = [
    {
      label: `${(deal?.title as string | undefined) ?? 'Deal'} × ${Number(order.quantity ?? 1)}`,
      amount: Number(order.unit_price ?? 0) * Number(order.quantity ?? 1),
    },
  ]
  const v2ServiceFeeLine = {
    title: 'Service fee',
    total: Number((order as { service_fee_total?: number | string | null }).service_fee_total ?? 0),
  }

  return (
    <div>
      <div className="mb-6">
        <Link href="/orders" className="mb-3 inline-flex items-center gap-2 px-3 py-2 text-sm font-medium rounded-lg border border-gray-300 bg-white text-gray-700 shadow-sm hover:bg-gray-50 transition-colors">
          ← Back to Orders
        </Link>
        <h1 className="text-2xl font-bold text-gray-900 mt-2">Order {orderNumberDisplay}</h1>
      </div>

      <div className="flex flex-col gap-5 md:flex-row md:items-start md:gap-6">
        <div className="order-1 min-w-0 flex-1 space-y-6">
        {/* 状态区块 */}
        <div className="bg-white rounded-xl border border-gray-200 p-6">
          <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-3">Status</h2>
          {hasV3Items ? (
            <div className="flex items-center gap-3 flex-wrap">
              {Object.entries(v3StatusSummary!).map(([status, count]) => (
                <span
                  key={status}
                  className={`px-3 py-1 rounded-full text-sm font-medium ${ITEM_STATUS_STYLES[status] ?? 'bg-gray-100 text-gray-600'}`}
                >
                  {ITEM_STATUS_LABELS[status] ?? status} ×{count}
                </span>
              ))}
            </div>
          ) : (
            <>
              <div className="flex items-center gap-3 flex-wrap">
                {detailStatusTags.map((tag) => (
                  <span
                    key={tag}
                    className={`px-3 py-1 rounded-full text-sm font-medium ${STATUS_STYLES[tag] ?? STATUS_STYLES.used}`}
                  >
                    {STATUS_LABELS[tag] ?? tag}
                  </span>
                ))}
                {order.status === 'refund_requested' && (
                  <OrderRefundButtons orderId={order.id} initialStatus={order.status} />
                )}
              </div>
              {(detailStatusTags.includes('pending_refund') || detailStatusTags.includes('expired')) && (
                <p className="text-sm text-gray-500 mt-3">
                  {detailStatusTags.includes('pending_refund')
                    ? 'Auto-refund in progress (runs hourly).'
                    : 'Coupon expired; will be auto-refunded 24h after expiry.'}
                </p>
              )}
            </>
          )}
        </div>

        {/* 订单信息、价格明细、支付拆分、退款汇总（与用户端对齐） */}
        {hasV3Items ? (
          <OrderDetailPricingCard
            orderNumber={orderNumberDisplay}
            createdAt={order.created_at as string}
            paidAt={paidAt}
            priceLines={buildDealPriceLines(dealGroups)}
            serviceFeeLine={serviceFeeLineLabel(orderItems)}
            totalAmount={totalAmt}
            payment={paymentSplit}
            paymentIntentId={(order.payment_intent_id as string | null) ?? null}
            refundSummary={pricingRefundSummary}
          />
        ) : (
          <OrderDetailPricingCard
            orderNumber={orderNumberDisplay}
            createdAt={order.created_at as string}
            paidAt={paidAt}
            priceLines={v2PriceLines}
            serviceFeeLine={v2ServiceFeeLine}
            totalAmount={totalAmt}
            payment={paymentSplit}
            paymentIntentId={(order.payment_intent_id as string | null) ?? null}
            refundSummary={pricingRefundSummary}
          />
        )}

        {/* V3: Order Items 按 deal 分组 */}
        {hasV3Items ? (
          <div className="bg-white rounded-xl border border-gray-200 p-6">
            <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-4">
              Order Items ({orderItems.length} coupon{orderItems.length > 1 ? 's' : ''})
            </h2>

            {/* 按 deal 分组展示 */}
            <div className="space-y-5">
              {dealGroups.map((group) => (
                <div key={group.dealId} className="border border-gray-100 rounded-lg p-4">
                  <div className="flex items-center justify-between mb-3">
                    <div>
                      <Link
                        href={`/deals/${group.dealId}?returnTo=${encodeURIComponent(`/orders/${order.id}`)}`}
                        className="text-blue-600 hover:underline font-medium"
                      >
                        {group.dealTitle}
                      </Link>
                      {group.merchantName && (
                        <span className="text-gray-500 text-sm ml-2">
                          by{' '}
                          <Link href={`/merchants/${group.merchantId}`} className="text-blue-600 hover:underline">
                            {group.merchantName}
                          </Link>
                        </span>
                      )}
                    </div>
                    <span className="text-sm text-gray-500">
                      ${group.unitPrice.toFixed(2)} × {group.items.length}
                    </span>
                  </div>

                  {/* 每张券 */}
                  <div className="space-y-3">
                    {group.items.map((item: any, idx: number) => {
                      const coupon = Array.isArray(item.coupons) ? item.coupons[0] : item.coupons
                      const couponCode = coupon?.coupon_code
                      const formattedCode = couponCode && couponCode.length === 16
                        ? `${couponCode.slice(0, 4)}-${couponCode.slice(4, 8)}-${couponCode.slice(8, 12)}-${couponCode.slice(12)}`
                        : couponCode ?? '—'
                      const redeemedName = item.redeemed_merchant_id
                        ? redeemedMerchantNames[item.redeemed_merchant_id] ?? item.redeemed_merchant_id.slice(0, 8)
                        : null
                      const gift = Array.isArray(item.coupon_gifts) ? item.coupon_gifts[0] : item.coupon_gifts
                      const recipientCoupon = coupon?.id ? giftRecipientCouponStatus[coupon.id] : null
                      // 只有已核销的券才在头部显示券码
                      const showCodeInHeader = item.customer_status === 'used'

                      return (
                        <div key={item.id} className="border border-gray-100 rounded-lg bg-gray-50/50 p-3">
                          {/* 券头部：code + 状态 */}
                          <div className="flex items-center justify-between mb-2">
                            <div className="flex items-center gap-2">
                              <span className="text-xs text-gray-400">#{idx + 1}</span>
                              {showCodeInHeader && <span className="font-mono text-sm text-gray-800">{formattedCode}</span>}
                            </div>
                            <span className={`px-2.5 py-0.5 rounded-full text-xs font-medium ${ITEM_STATUS_STYLES[item.customer_status] ?? 'bg-gray-100 text-gray-600'}`}>
                              {ITEM_STATUS_LABELS[item.customer_status] ?? item.customer_status}
                            </span>
                          </div>

                          {/* 基础信息行 */}
                          <div className="flex items-center gap-4 text-xs text-gray-500 mb-1">
                            <span>Expires: {coupon?.expires_at ? new Date(coupon.expires_at).toLocaleDateString('en-US') : '—'}</span>
                            <span>Price: ${Number(item.unit_price).toFixed(2)}</span>
                          </div>

                          {/* 已核销 (Redeemed) */}
                          {item.customer_status === 'used' && (
                            <div className="mt-2 pt-2 border-t border-gray-200 text-xs space-y-1">
                              <div className="flex items-center gap-1 text-green-700">
                                <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" /></svg>
                                <span className="font-medium">Redeemed</span>
                              </div>
                              <div className="grid grid-cols-2 gap-x-4 gap-y-1 text-gray-600 pl-4">
                                <div>Time: <span className="text-gray-900">{item.redeemed_at ? new Date(item.redeemed_at).toLocaleString() : '—'}</span></div>
                                <div>Code: <span className="font-mono text-gray-900">{formattedCode}</span></div>
                                <div>Store: {redeemedName ? (
                                  <Link href={`/merchants/${item.redeemed_merchant_id}`} className="text-blue-600 hover:underline">{redeemedName}</Link>
                                ) : <span className="text-gray-400">—</span>}</div>
                              </div>
                            </div>
                          )}

                          {/* 已退款 (Refunded / Refund Success) */}
                          {(item.customer_status === 'refund_success' || item.refunded_at) && item.customer_status !== 'gifted' && item.customer_status !== 'used' && (
                            <div className="mt-2 pt-2 border-t border-gray-200 text-xs space-y-1">
                              <div className="flex items-center gap-1 text-purple-700">
                                <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 10h10a8 8 0 018 8v2M3 10l6 6m-6-6l6-6" /></svg>
                                <span className="font-medium">Refunded</span>
                              </div>
                              <div className="grid grid-cols-2 gap-x-4 gap-y-1 text-gray-600 pl-4">
                                <div>Time: <span className="text-gray-900">{item.refunded_at ? new Date(item.refunded_at).toLocaleString() : '—'}</span></div>
                                <div>Amount: <span className="font-semibold text-gray-900">${Number(item.refund_amount ?? item.unit_price).toFixed(2)}</span></div>
                                <div>Method: <span className="text-gray-900">{item.refund_method === 'store_credit' ? '💳 Store Credit' : item.refund_method === 'original_payment' ? '💰 Original Payment' : item.refund_method ?? '—'}</span></div>
                                {item.refund_reason && (
                                  <div className="col-span-2">Reason: <span className="text-gray-900">{item.refund_reason}</span></div>
                                )}
                              </div>
                            </div>
                          )}

                          {/* 等 Stripe / 支付渠道 webhook */}
                          {item.customer_status === 'refund_processing' && (
                            <div className="mt-2 pt-2 border-t border-gray-200 text-xs space-y-1">
                              <div className="flex items-center gap-1 text-sky-800">
                                <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" /></svg>
                                <span className="font-medium">{ITEM_STATUS_LABELS.refund_processing}</span>
                              </div>
                              <div className="text-gray-600 pl-4">Awaiting card refund confirmation (webhook).</div>
                              {item.refund_reason && (
                                <div className="text-gray-600 pl-4">Reason: <span className="text-gray-900">{item.refund_reason}</span></div>
                              )}
                            </div>
                          )}

                          {/* 待人工审核（legacy refund_pending 可能仍有） */}
                          {(item.customer_status === 'refund_pending' || item.customer_status === 'refund_review') && (
                            <div className="mt-2 pt-2 border-t border-gray-200 text-xs space-y-1">
                              <div className="flex items-center gap-1 text-amber-700">
                                <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" /></svg>
                                <span className="font-medium">{ITEM_STATUS_LABELS[item.customer_status]}</span>
                              </div>
                              {item.refund_reason && (
                                <div className="text-gray-600 pl-4">Reason: <span className="text-gray-900">{item.refund_reason}</span></div>
                              )}
                            </div>
                          )}

                          {/* 退款被拒 */}
                          {item.customer_status === 'refund_reject' && (
                            <div className="mt-2 pt-2 border-t border-gray-200 text-xs space-y-1">
                              <div className="flex items-center gap-1 text-amber-700">
                                <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" /></svg>
                                <span className="font-medium">Refund Rejected</span>
                              </div>
                              {item.refund_reason && (
                                <div className="text-gray-600 pl-4">Reason: <span className="text-gray-900">{item.refund_reason}</span></div>
                              )}
                            </div>
                          )}

                          {/* 已赠送 (Gifted) */}
                          {item.customer_status === 'gifted' && gift && (
                            <div className="mt-2 pt-2 border-t border-gray-200 text-xs space-y-1">
                              <div className="flex items-center gap-1 text-pink-700">
                                <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v13m0-13V6a2 2 0 112 2h-2zm0 0V5.5A2.5 2.5 0 109.5 8H12zm-7 4h14M5 12a2 2 0 110-4h14a2 2 0 110 4M5 12v7a2 2 0 002 2h10a2 2 0 002-2v-7" /></svg>
                                <span className="font-medium">Gifted</span>
                              </div>
                              <div className="grid grid-cols-2 gap-x-4 gap-y-1 text-gray-600 pl-4">
                                <div>Gift Time: <span className="text-gray-900">{gift.created_at ? new Date(gift.created_at).toLocaleString() : '—'}</span></div>
                                <div>Recipient: <span className="text-gray-900">
                                  {gift.recipient_user_id && recipientUserEmails[gift.recipient_user_id]
                                    ? recipientUserEmails[gift.recipient_user_id]
                                    : gift.recipient_email ?? gift.recipient_phone ?? '—'}
                                </span></div>
                                <div>Gift Status: <span className={`px-1.5 py-0.5 rounded-full font-medium ${GIFT_STATUS_STYLES[gift.status] ?? 'bg-gray-100 text-gray-600'}`}>
                                  {GIFT_STATUS_LABELS[gift.status] ?? gift.status}
                                </span></div>
                                {gift.status === 'claimed' && gift.claimed_at && (
                                  <div>Claimed: <span className="text-gray-900">{new Date(gift.claimed_at).toLocaleString()}</span></div>
                                )}
                                {gift.status === 'recalled' && gift.recalled_at && (
                                  <div>Recalled: <span className="text-gray-900">{new Date(gift.recalled_at).toLocaleString()}</span></div>
                                )}
                                {gift.gift_message && (
                                  <div className="col-span-2">Message: <span className="text-gray-900 italic">&ldquo;{gift.gift_message}&rdquo;</span></div>
                                )}
                              </div>

                              {/* 受赠人券的状态 */}
                              {recipientCoupon && (
                                <div className="mt-2 ml-4 p-2 bg-white rounded border border-gray-100">
                                  <div className="text-gray-500 mb-1 font-medium">Recipient Coupon Status</div>
                                  <div className="flex items-center gap-2">
                                    <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${
                                      recipientCoupon.status === 'used' ? 'bg-green-100 text-green-700'
                                      : recipientCoupon.status === 'unused' ? 'bg-blue-100 text-blue-700'
                                      : recipientCoupon.status === 'expired' ? 'bg-red-100 text-red-700'
                                      : recipientCoupon.status === 'refunded' ? 'bg-purple-100 text-purple-700'
                                      : 'bg-gray-100 text-gray-600'
                                    }`}>
                                      {recipientCoupon.status === 'used' ? 'Redeemed' : recipientCoupon.status === 'unused' ? 'Unused' : recipientCoupon.status === 'expired' ? 'Expired' : recipientCoupon.status === 'refunded' ? 'Refunded' : recipientCoupon.status}
                                    </span>
                                    {recipientCoupon.usedAt && (
                                      <span className="text-gray-500">at {new Date(recipientCoupon.usedAt).toLocaleString()}</span>
                                    )}
                                  </div>
                                  {recipientCoupon.status === 'refunded' && recipientCoupon.refundedAt && (
                                    <div className="mt-1 text-gray-600">
                                      Refunded: {new Date(recipientCoupon.refundedAt).toLocaleString()}
                                      {recipientCoupon.refundAmount != null && <span> · ${recipientCoupon.refundAmount.toFixed(2)}</span>}
                                      {recipientCoupon.refundMethod && <span> · {recipientCoupon.refundMethod === 'store_credit' ? 'Store Credit' : 'Original Payment'}</span>}
                                    </div>
                                  )}
                                </div>
                              )}
                            </div>
                          )}
                        </div>
                      )
                    })}
                  </div>
                </div>
              ))}
            </div>
          </div>
        ) : (
          /* V2 兼容：旧的 Order & Deal 区块 */
          <>
            <div className="bg-white rounded-xl border border-gray-200 p-6">
              <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-4">Order & Deal</h2>
              <dl className="grid grid-cols-2 sm:grid-cols-4 gap-3 text-sm mb-4 pb-4 border-b border-gray-100">
                <div>
                  <dt className="text-gray-500">Deal</dt>
                  <dd className="font-medium text-gray-900 mt-0.5">
                    {deal ? (<Link href={`/deals/${deal.id}?returnTo=${encodeURIComponent(`/orders/${order.id}`)}`} className="text-blue-600 hover:underline">{deal.title}</Link>) : '—'}
                  </dd>
                </div>
                <div>
                  <dt className="text-gray-500">Merchant</dt>
                  <dd className="font-medium text-gray-900 mt-0.5">
                    {merchant ? (<Link href={`/merchants/${merchant.id}`} className="text-blue-600 hover:underline">{merchant.name}</Link>) : '—'}
                  </dd>
                </div>
                <div>
                  <dt className="text-gray-500">Unit Price</dt>
                  <dd className="font-medium text-gray-900 mt-0.5">${Number(order.unit_price).toFixed(2)}</dd>
                </div>
                <div>
                  <dt className="text-gray-500">Total</dt>
                  <dd className="font-semibold text-gray-900 mt-0.5">${Number(order.total_amount).toFixed(2)}</dd>
                </div>
                <div>
                  <dt className="text-gray-500">Quantity</dt>
                  <dd className="font-medium text-gray-900 mt-0.5">{order.quantity}</dd>
                </div>
                <div>
                  <dt className="text-gray-500">Created</dt>
                  <dd className="font-medium text-gray-900 mt-0.5">{new Date(order.created_at).toLocaleString()}</dd>
                </div>
              </dl>

              {/* V2 券列表 */}
              {v2Coupons.length > 0 && (
                <>
                  <h3 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-3">
                    Coupons ({v2Coupons.length})
                  </h3>
                  <div className="space-y-3">
                    {v2Coupons.map((c: any, idx: number) => {
                      const cCode = c.coupon_code
                      const fmtCode = cCode && cCode.length === 16
                        ? `${cCode.slice(0, 4)}-${cCode.slice(4, 8)}-${cCode.slice(8, 12)}-${cCode.slice(12)}`
                        : cCode ?? null
                      const rmName = c.redeemed_at_merchant_id
                        ? v2RedeemedMerchantNames[c.redeemed_at_merchant_id] ?? c.redeemed_at_merchant_id.slice(0, 8)
                        : null
                      const couponStatus = c.status as string
                      // 只有已核销的券才显示券码
                      const showCode = couponStatus === 'used'

                      return (
                        <div key={c.id} className="border border-gray-100 rounded-lg bg-gray-50/50 p-3">
                          {/* 券头部 */}
                          <div className="flex items-center justify-between mb-2">
                            <div className="flex items-center gap-2">
                              <span className="text-xs text-gray-400">#{idx + 1}</span>
                              {showCode && fmtCode && <span className="font-mono text-sm text-gray-800">{fmtCode}</span>}
                            </div>
                            <span className={`px-2.5 py-0.5 rounded-full text-xs font-medium ${
                              couponStatus === 'used' ? 'bg-green-100 text-green-700'
                              : couponStatus === 'unused' ? 'bg-blue-100 text-blue-700'
                              : couponStatus === 'expired' ? 'bg-red-100 text-red-700'
                              : couponStatus === 'refunded' ? 'bg-purple-100 text-purple-700'
                              : couponStatus === 'voided' ? 'bg-gray-100 text-gray-600'
                              : 'bg-gray-100 text-gray-600'
                            }`}>
                              {couponStatus === 'used' ? 'Redeemed' : couponStatus === 'unused' ? 'Unused' : couponStatus === 'expired' ? 'Expired' : couponStatus === 'refunded' ? 'Refunded' : couponStatus === 'voided' ? 'Voided' : couponStatus}
                            </span>
                          </div>

                          {/* 基础信息 */}
                          <div className="flex items-center gap-4 text-xs text-gray-500 mb-1">
                            <span>Expires: {c.expires_at ? new Date(c.expires_at).toLocaleDateString('en-US') : '—'}</span>
                          </div>

                          {/* 已核销 */}
                          {couponStatus === 'used' && (
                            <div className="mt-2 pt-2 border-t border-gray-200 text-xs space-y-1">
                              <div className="flex items-center gap-1 text-green-700">
                                <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" /></svg>
                                <span className="font-medium">Redeemed</span>
                              </div>
                              <div className="grid grid-cols-2 gap-x-4 gap-y-1 text-gray-600 pl-4">
                                <div>Time: <span className="text-gray-900">{c.used_at ? new Date(c.used_at).toLocaleString() : '—'}</span></div>
                                <div>Code: <span className="font-mono text-gray-900">{fmtCode}</span></div>
                                {rmName && (
                                  <div>Store: <Link href={`/merchants/${c.redeemed_at_merchant_id}`} className="text-blue-600 hover:underline">{rmName}</Link></div>
                                )}
                              </div>
                            </div>
                          )}

                          {/* 已退款 */}
                          {couponStatus === 'refunded' && (
                            <div className="mt-2 pt-2 border-t border-gray-200 text-xs space-y-1">
                              <div className="flex items-center gap-1 text-purple-700">
                                <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 10h10a8 8 0 018 8v2M3 10l6 6m-6-6l6-6" /></svg>
                                <span className="font-medium">Refunded</span>
                              </div>
                              <div className="grid grid-cols-2 gap-x-4 gap-y-1 text-gray-600 pl-4">
                                <div>Amount: <span className="font-semibold text-gray-900">${Number(order.unit_price).toFixed(2)}</span></div>
                              </div>
                            </div>
                          )}

                          {/* 已作废 */}
                          {couponStatus === 'voided' && (
                            <div className="mt-2 pt-2 border-t border-gray-200 text-xs space-y-1">
                              <div className="flex items-center gap-1 text-gray-600">
                                <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M18.364 18.364A9 9 0 005.636 5.636m12.728 12.728A9 9 0 015.636 5.636m12.728 12.728L5.636 5.636" /></svg>
                                <span className="font-medium">Voided</span>
                              </div>
                              <div className="text-gray-600 pl-4">
                                {c.void_reason && <div>Reason: <span className="text-gray-900">{c.void_reason}</span></div>}
                                {c.voided_at && <div>Time: <span className="text-gray-900">{new Date(c.voided_at).toLocaleString()}</span></div>}
                              </div>
                            </div>
                          )}

                          {/* 已赠送（V2 通过 gifted_from 判断） */}
                          {c.is_gifted && (
                            <div className="mt-2 pt-2 border-t border-gray-200 text-xs space-y-1">
                              <div className="flex items-center gap-1 text-pink-700">
                                <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v13m0-13V6a2 2 0 112 2h-2zm0 0V5.5A2.5 2.5 0 109.5 8H12zm-7 4h14M5 12a2 2 0 110-4h14a2 2 0 110 4M5 12v7a2 2 0 002 2h10a2 2 0 002-2v-7" /></svg>
                                <span className="font-medium">Received as Gift</span>
                              </div>
                            </div>
                          )}
                        </div>
                      )
                    })}
                  </div>
                </>
              )}
            </div>

            {/* 适用门店（多店 Deal） */}
            {applicableStores.length > 0 && (
              <div className="bg-white rounded-xl border border-gray-200 p-6">
                <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-3">Applicable Stores</h2>
                <div className="flex flex-wrap gap-2">
                  {applicableStores.map(s => (
                    <Link key={s.id} href={`/merchants/${s.id}`} className="px-2 py-1 rounded bg-gray-100 text-xs text-blue-600 hover:underline">
                      {s.name}
                    </Link>
                  ))}
                </div>
              </div>
            )}
          </>
        )}

        {/* Refund info (if any) — 仅 V2 */}
        {!hasV3Items && (order.refund_reason != null || order.refund_requested_at != null || order.refunded_at != null || (order as { refund_rejected_at?: string | null }).refund_rejected_at != null) && (
          <div className="bg-white rounded-xl border border-gray-200 p-6">
            <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-3">Refund</h2>
            <dl className="space-y-2 text-sm">
              {order.refund_reason != null && (
                <div><dt className="text-gray-500">Reason</dt><dd className="text-gray-900 mt-0.5">{order.refund_reason}</dd></div>
              )}
              {order.refund_requested_at != null && (
                <div><dt className="text-gray-500">Requested at</dt><dd className="text-gray-900 mt-0.5">{new Date(order.refund_requested_at).toLocaleString()}</dd></div>
              )}
              {order.refunded_at != null && (
                <div><dt className="text-gray-500">Refunded at</dt><dd className="text-gray-900 mt-0.5">{new Date(order.refunded_at).toLocaleString()}</dd></div>
              )}
              {(order as { refund_rejected_at?: string | null }).refund_rejected_at != null && (
                <div>
                  <dt className="text-gray-500">Rejected at</dt>
                  <dd className="text-gray-900 mt-0.5">{new Date((order as { refund_rejected_at: string }).refund_rejected_at).toLocaleString()}</dd>
                </div>
              )}
            </dl>
          </div>
        )}
        </div>

        <aside className="order-2 flex w-full shrink-0 flex-col gap-4 md:sticky md:top-4 md:w-72 md:max-w-[22rem] lg:w-80">
          <OrderDetailCustomerSidebar customer={customerSummary} returnToPath={`/orders/${order.id}`} />
        </aside>
      </div>
    </div>
  )
}
