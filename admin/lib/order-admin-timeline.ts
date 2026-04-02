/**
 * 后台订单详情 — 活动时间线（由已有时间字段推导，非独立审计表）
 * 注释中文；展示文案英文。
 */

import { displayCouponCode } from '@/lib/coupon-admin-display'
import type { AdminActivityTimelineEntry } from '@/lib/admin-activity-timeline-types'

/** 与通用时间线条目结构一致，保留别名便于订单模块内阅读 */
export type OrderTimelineEntry = AdminActivityTimelineEntry

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
  coupons?:
    | { coupon_code?: string | null }
    | { coupon_code?: string | null }[]
    | null
}

export type V2CouponLike = {
  id: string
  created_at?: string | null
  used_at?: string | null
  voided_at?: string | null
  status?: string | null
  coupon_code?: string | null
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

/** 时间线券事件标题前缀：有 deal 名用 deal 名，否则沿用 Voucher */
function timelineDealLabel(title: string | null | undefined): string {
  const t = title == null ? '' : String(title).trim()
  return t || 'Voucher'
}

function giftCreatedAt(item: OrderItemLike): string | null {
  const g = item.coupon_gifts
  if (!g) return null
  const row = Array.isArray(g) ? g[0] : g
  return row?.created_at ?? null
}

/** 从 order_item 嵌套 coupons 取券码（用于时间线与列表一致） */
function couponCodeFromItem(item: OrderItemLike): string | null {
  const c = item.coupons
  if (!c) return null
  const one = Array.isArray(c) ? c[0] : c
  const raw = one?.coupon_code
  if (raw == null || String(raw).trim() === '') return null
  return String(raw).trim()
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
    const dealLabel = timelineDealLabel(deal)
    const cc = couponCodeFromItem(item)
    const suffix = cc ? ` · ${displayCouponCode(cc)}` : ''
    const prefix = `${dealLabel} #${n}${suffix}`

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

export type BuildOrderTimelineV2Options = {
  /** 旧单订单级 deal 标题，用于券事件前缀 */
  dealTitle?: string | null
}

/**
 * V2：订单级 + 每张 coupon 的核销/作废（used_at / voided_at）；退款以订单级为准
 */
export function buildOrderTimelineV2(
  order: OrderLike,
  v2Coupons: V2CouponLike[],
  options?: BuildOrderTimelineV2Options
): OrderTimelineEntry[] {
  const out: OrderTimelineEntry[] = []

  const placedAt = order.paid_at ?? order.created_at
  push(out, placedAt, 'Order placed', 'Payment recorded')

  push(out, order.refund_requested_at, 'Refund requested', order.refund_reason ?? undefined)
  push(out, order.refund_rejected_at, 'Refund rejected', order.refund_reason ?? undefined)
  push(out, order.refunded_at, 'Order refunded', order.refund_reason ?? undefined)

  const dealLabel = timelineDealLabel(options?.dealTitle)

  const sorted = [...v2Coupons].sort(
    (a, b) => new Date(a.created_at ?? 0).getTime() - new Date(b.created_at ?? 0).getTime()
  )

  sorted.forEach((c, idx) => {
    const n = idx + 1
    const raw = c.coupon_code
    const cc = raw != null && String(raw).trim() !== '' ? String(raw).trim() : null
    const suffix = cc ? ` · ${displayCouponCode(cc)}` : ''
    const prefix = `${dealLabel} #${n}${suffix}`

    if (c.used_at && c.status === 'used') {
      push(out, c.used_at, `${prefix} redeemed`)
    } else if (c.used_at) {
      push(out, c.used_at, `${prefix} used`, `Status: ${c.status ?? '—'}`)
    }

    push(out, c.voided_at, `${prefix} voided`)
  })

  return sortTimelineAscending(out)
}
