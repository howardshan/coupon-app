/**
 * 后台订单详情展示用计算（与用户端 order_detail_screen Order Info 区块对齐）
 * 注释中文；导出英文标识符。
 */

export type OrderItemForSummary = {
  customer_status: string
  refund_method: string | null | undefined
  refund_amount: number | string | null | undefined
  unit_price: number | string | null | undefined
  service_fee?: number | string | null | undefined
}

/** 货币展示 */
export function formatOrderMoney(n: number): string {
  return `$${(Number.isFinite(n) ? n : 0).toFixed(2)}`
}

/** 是否全额 Store Credit（与用户端 _isPaidByStoreCredit 一致） */
export function isFullyPaidByStoreCredit(totalAmount: number, storeCreditUsed: number): boolean {
  const c = Number(storeCreditUsed) || 0
  const t = Number(totalAmount) || 0
  return c > 0 && c >= t
}

/** 主支付方式文案（卡行标签） */
export function resolvePaymentMethodLabel(totalAmount: number, storeCreditUsed: number): string {
  if (isFullyPaidByStoreCredit(totalAmount, storeCreditUsed)) return 'Store Credit'
  return 'Credit Card'
}

export type PaymentSplit = {
  storeCreditUsed: number
  cardAmount: number
  fullyStoreCredit: boolean
  displayMethod: string
}

export function computePaymentSplit(totalAmount: number, storeCreditUsedRaw: number | null | undefined): PaymentSplit {
  const total = Number(totalAmount) || 0
  const credit = Math.max(0, Number(storeCreditUsedRaw) || 0)
  const cardAmount = Math.max(0, total - credit)
  return {
    storeCreditUsed: credit,
    cardAmount,
    fullyStoreCredit: credit > 0 && credit >= total,
    displayMethod: resolvePaymentMethodLabel(total, credit),
  }
}

export type DealPriceLine = { label: string; amount: number }

/** V3：按 deal 分组后的行（dealTitle × count → 金额） */
export function buildDealPriceLines(
  dealGroups: { dealTitle: string; unitPrice: number; items: unknown[] }[]
): DealPriceLine[] {
  return dealGroups.map((g) => ({
    label: `${g.dealTitle || 'Deal'} × ${g.items.length}`,
    amount: Number(g.unitPrice) * g.items.length,
  }))
}

export function sumServiceFeeFromItems(items: { service_fee?: unknown }[]): number {
  let sum = 0
  for (const i of items) {
    sum += Number(i.service_fee ?? 0)
  }
  return Math.round(sum * 100) / 100
}

/** Service fee 行标题：若每笔相同则显示 ($x × n) */
export function serviceFeeLineLabel(items: { service_fee?: unknown }[]): { title: string; total: number } {
  const n = items.length
  const total = sumServiceFeeFromItems(items)
  if (n === 0) return { title: 'Service fee', total }
  const first = Number(items[0]?.service_fee ?? 0)
  const allSame = items.every((i) => Number(i?.service_fee ?? 0) === first)
  if (allSame && first > 0) {
    return { title: `Service fee (${formatOrderMoney(first)} × ${n})`, total }
  }
  return { title: 'Service fee', total }
}

export type RefundSummary = {
  totalRefund: number
  storeCreditTotal: number
  storeCreditCount: number
  originalTotal: number
  originalCount: number
  pendingTotal: number
  pendingCount: number
}

function itemRefundAmount(i: OrderItemForSummary): number {
  const ra = i.refund_amount
  if (ra != null && ra !== '') return Number(ra)
  return Number(i.unit_price ?? 0)
}

/**
 * 与用户端 _OrderInfoSection 退款汇总逻辑一致：
 * refunded 集合含 refund_success | refund_pending | refund_processing；
 * 分渠道仅统计 refund_success + method。
 */
export function computeRefundSummary(items: OrderItemForSummary[]): RefundSummary | null {
  const refundedItems = items.filter((i) =>
    ['refund_success', 'refund_pending', 'refund_processing'].includes(i.customer_status)
  )
  if (refundedItems.length === 0) return null

  const totalRefund = refundedItems.reduce((s, i) => s + itemRefundAmount(i), 0)

  const storeCreditRefunds = refundedItems.filter(
    (i) => i.customer_status === 'refund_success' && i.refund_method === 'store_credit'
  )
  const originalRefunds = refundedItems.filter(
    (i) => i.customer_status === 'refund_success' && i.refund_method === 'original_payment'
  )
  const pendingRefunds = refundedItems.filter((i) =>
    ['refund_pending', 'refund_processing'].includes(i.customer_status)
  )

  const sumList = (list: OrderItemForSummary[]) => list.reduce((s, i) => s + itemRefundAmount(i), 0)

  return {
    totalRefund,
    storeCreditTotal: sumList(storeCreditRefunds),
    storeCreditCount: storeCreditRefunds.length,
    originalTotal: sumList(originalRefunds),
    originalCount: originalRefunds.length,
    pendingTotal: sumList(pendingRefunds),
    pendingCount: pendingRefunds.length,
  }
}

/** V2：按已退款券数量 × 单价估算（无 order_item 级 refund_method 时） */
export function computeV2RefundSummaryFromCoupons(
  v2Coupons: { status: string }[],
  unitPrice: number
): RefundSummary | null {
  const refunded = v2Coupons.filter((c) => c.status === 'refunded')
  if (refunded.length === 0) return null
  const u = Number(unitPrice) || 0
  const totalRefund = refunded.length * u
  return {
    totalRefund,
    storeCreditTotal: 0,
    storeCreditCount: 0,
    originalTotal: totalRefund,
    originalCount: refunded.length,
    pendingTotal: 0,
    pendingCount: 0,
  }
}
