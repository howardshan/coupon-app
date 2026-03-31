/**
 * 根据订单 DB 状态 + deal/coupon 过期时间计算「展示用」状态（仅前端展示，不落库）
 * 规则：unused + 未过期 → unused；unused + 已过期 <24h → expired；unused + 已过期 ≥24h → pending_refund
 */
const TWENTY_FOUR_HOURS_MS = 24 * 60 * 60 * 1000;

/** 状态徽章样式（与详情页、列表一致） */
export const STATUS_STYLES: Record<string, string> = {
  unused: 'bg-blue-100 text-blue-700',
  used: 'bg-gray-100 text-gray-600',
  refunded: 'bg-purple-100 text-purple-700',
  refund_requested: 'bg-orange-100 text-orange-700',
  refund_processing: 'bg-amber-100 text-amber-800',
  refund_failed: 'bg-red-100 text-red-700',
  refund_rejected: 'bg-amber-100 text-amber-700',
  expired: 'bg-red-100 text-red-700',
  pending_refund: 'bg-amber-100 text-amber-700',
};

/** 状态展示文案 */
export const STATUS_LABELS: Record<string, string> = {
  unused: 'Unused',
  used: 'Used',
  refunded: 'Refunded',
  refund_requested: 'Refund Requested',
  refund_processing: 'Refund Processing',
  refund_failed: 'Refund Failed',
  refund_rejected: 'Refund Rejected',
  expired: 'Expired',
  pending_refund: 'Pending Refund',
};

export type OrderForDisplayStatus = {
  status: string
  deals?: { expires_at?: string | null } | null
  coupon_expires_at?: string | null
  deal_expires_at?: string | null
  /** 管理员拒绝退款时写入，详情页展示 Refund Rejected */
  refund_rejected_at?: string | null
}

export function getOrderDisplayStatus(order: OrderForDisplayStatus): string {
  if (order.status !== 'unused') return order.status;

  const expiresAt =
    order.deal_expires_at ??
    order.coupon_expires_at ??
    (order.deals && 'expires_at' in order.deals ? order.deals.expires_at : null);

  if (!expiresAt) return 'unused';

  const expiry = new Date(expiresAt).getTime();
  const now = Date.now();
  if (expiry > now) return 'unused';

  const elapsed = now - expiry;
  if (elapsed >= TWENTY_FOUR_HOURS_MS) return 'pending_refund';
  return 'expired';
}

/**
 * 订单详情页：返回多个状态标签数组，用于并排展示（如 [Unused, Expired]）
 * 使用维度（usage）+ 过期/退款维度（仅当 status=unused 时）
 */
export function getOrderDetailStatusTags(order: OrderForDisplayStatus): string[] {
  const tags: string[] = []

  // 1. 使用维度：始终有一个主状态
  if (order.status === 'unused') {
    tags.push('unused')
    if (order.refund_rejected_at) tags.push('refund_rejected')
  } else if (order.status === 'used') {
    tags.push('used')
    return tags
  } else if (order.status === 'refunded') {
    tags.push('refunded')
    return tags
  } else if (order.status === 'refund_requested') {
    tags.push('refund_requested')
    return tags
  } else if (order.status === 'refund_processing') {
    tags.push('refund_processing')
    return tags
  } else if (order.status === 'refund_failed') {
    tags.push('refund_failed')
    return tags
  }

  // 2. 仅当 unused 时：根据过期时间追加 expired / pending_refund
  if (order.status !== 'unused') return tags

  const expiresAt =
    order.deal_expires_at ??
    order.coupon_expires_at ??
    (order.deals && 'expires_at' in order.deals ? order.deals.expires_at : null)
  if (!expiresAt) return tags

  const expiry = new Date(expiresAt).getTime()
  const now = Date.now()
  if (expiry > now) return tags

  const elapsed = now - expiry
  if (elapsed >= TWENTY_FOUR_HOURS_MS) {
    tags.push('pending_refund')
  } else {
    tags.push('expired')
  }
  return tags
}
