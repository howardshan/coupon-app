/**
 * 后台订单详情 — 活动时间线（由已有时间字段推导，非独立审计表）
 * 注释中文；展示文案英文。
 */

export type OrderTimelineEntry = {
  /** ISO 时间字符串，用于排序与展示 */
  at: string
  /** 主标题（英文） */
  title: string
  /** 副标题（券序号、deal、原因等） */
  subtitle?: string
}

type OrderLike = {
  created_at?: string | null
  paid_at?: string | null
  refund_requested_at?: string | null
  refunded_at?: string | null
  refund_rejected_at?: string | null
  refund_reason?: string | null
  status?: string | null
  updated_at?: string | null
}

export type OrderItemLike = {
  id: string
  created_at?: string | null
  redeemed_at?: string | null
  refunded_at?: string | null
  refund_method?: string | null
  refund_reason?: string | null
  customer_status?: string | null
  deals?: { title?: string | null } | { title?: string | null }[] | null
  coupon_gifts?:
    | { created_at?: string | null }[]
    | { created_at?: string | null }
    | null
}

export type V2CouponLike = {
  id: string
  created_at?: string | null
  used_at?: string | null
  voided_at?: string | null
  status?: string | null
}

function fmtMethod(m: string | null | undefined): string {
  if (m === 'store_credit') return 'Store credit'
  if (m === 'original_payment') return 'Original payment'
  return m?.replace(/_/g, ' ') ?? ''
}

function dealTitleFromItem(item: OrderItemLike): string {
  const d = item.deals
  if (!d) return ''
  const one = Array.isArray(d) ? d[0] : d
  return (one?.title as string)?.trim() ?? ''
}

function giftCreatedAt(item: OrderItemLike): string | null {
  const g = item.coupon_gifts
  if (!g) return null
  const row = Array.isArray(g) ? g[0] : g
  return row?.created_at ?? null
}

function push(
  out: OrderTimelineEntry[],
  at: string | null | undefined,
  title: string,
  subtitle?: string
): void {
  if (!at) return
  const t = String(at).trim()
  if (!t) return
  out.push({ at: t, title, subtitle: subtitle?.trim() || undefined })
}

/** 按时间升序（最早在上，适合纵向时间线阅读） */
export function sortTimelineAscending(entries: OrderTimelineEntry[]): OrderTimelineEntry[] {
  return [...entries].sort((a, b) => new Date(a.at).getTime() - new Date(b.at).getTime())
}

/**
 * V3：订单级事件 + 每张券的核销/退款/转赠发起（若有时间）
 */
export function buildOrderTimelineV3(order: OrderLike, orderItems: OrderItemLike[]): OrderTimelineEntry[] {
  const out: OrderTimelineEntry[] = []

  const placedAt = order.paid_at ?? order.created_at
  push(out, placedAt, 'Order placed', 'Payment recorded')

  push(out, order.refund_requested_at, 'Refund requested', order.refund_reason ?? undefined)
  push(out, order.refund_rejected_at, 'Refund rejected', order.refund_reason ?? undefined)

  const anyItemRefunded = orderItems.some((i) => i.refunded_at)
  if (!anyItemRefunded) {
    push(out, order.refunded_at, 'Order refunded', order.refund_reason ?? undefined)
  }

  const sorted = [...orderItems].sort(
    (a, b) => new Date(a.created_at ?? 0).getTime() - new Date(b.created_at ?? 0).getTime()
  )

  sorted.forEach((item, idx) => {
    const n = idx + 1
    const deal = dealTitleFromItem(item)
    const prefix = `Voucher #${n}`

    push(out, item.redeemed_at, `${prefix} redeemed`, deal || undefined)

    const giftAt = giftCreatedAt(item)
    if (giftAt && item.customer_status === 'gifted') {
      push(out, giftAt, `${prefix} gift sent`, deal || undefined)
    }

    if (item.refunded_at) {
      const parts = [fmtMethod(item.refund_method ?? undefined), item.refund_reason].filter(Boolean)
      push(out, item.refunded_at, `${prefix} refunded`, parts.join(' · ') || undefined)
    }
  })

  return sortTimelineAscending(out)
}

/**
 * V2：订单级 + 每张 coupon 的核销/作废（used_at / voided_at）；退款以订单级为准
 */
export function buildOrderTimelineV2(order: OrderLike, v2Coupons: V2CouponLike[]): OrderTimelineEntry[] {
  const out: OrderTimelineEntry[] = []

  const placedAt = order.paid_at ?? order.created_at
  push(out, placedAt, 'Order placed', 'Payment recorded')

  push(out, order.refund_requested_at, 'Refund requested', order.refund_reason ?? undefined)
  push(out, order.refund_rejected_at, 'Refund rejected', order.refund_reason ?? undefined)
  push(out, order.refunded_at, 'Order refunded', order.refund_reason ?? undefined)

  const sorted = [...v2Coupons].sort(
    (a, b) => new Date(a.created_at ?? 0).getTime() - new Date(b.created_at ?? 0).getTime()
  )

  sorted.forEach((c, idx) => {
    const n = idx + 1
    const prefix = `Voucher #${n}`

    if (c.used_at && c.status === 'used') {
      push(out, c.used_at, `${prefix} redeemed`)
    } else if (c.used_at) {
      push(out, c.used_at, `${prefix} used`, `Status: ${c.status ?? '—'}`)
    }

    push(out, c.voided_at, `${prefix} voided`)
  })

  return sortTimelineAscending(out)
}
