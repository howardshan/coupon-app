/**
 * Merchant 详情页 — 活动时间线（由 merchants 表已有字段推导）
 * 无独立状态变更流水时不编造「通过/驳回」时刻；注释中文；展示文案英文。
 */

import {
  sortActivityTimelineAscending,
  type AdminActivityTimelineEntry,
} from '@/lib/admin-activity-timeline-types'

export type MerchantTimelineMerchantLike = {
  created_at?: string | null
  updated_at?: string | null
  submitted_at?: string | null
  status?: string | null
  rejection_reason?: string | null
}

function push(
  out: AdminActivityTimelineEntry[],
  at: string | null | undefined,
  title: string,
  subtitle?: string
): void {
  if (at == null) return
  const t = String(at).trim()
  if (!t) return
  out.push({ at: t, title, subtitle: subtitle?.trim() || undefined })
}

function sameInstantWithinMs(
  a: string | null | undefined,
  b: string | null | undefined,
  ms: number
): boolean {
  if (a == null || b == null) return false
  return Math.abs(new Date(a).getTime() - new Date(b).getTime()) <= ms
}

/**
 * 组装 Merchant 时间线：建档、提交审核、最后更新（含当前 status / 驳回原因摘要）。
 * 不包含「管理员通过/驳回」的精确时刻（库中无单独审计列时）。
 */
export function buildMerchantTimeline(
  merchant: MerchantTimelineMerchantLike
): AdminActivityTimelineEntry[] {
  const out: AdminActivityTimelineEntry[] = []

  push(out, merchant.created_at, 'Merchant record created', 'Account / storefront row first created')

  const submitted = merchant.submitted_at
  const created = merchant.created_at
  if (submitted && !sameInstantWithinMs(submitted, created, 1000)) {
    push(out, submitted, 'Application submitted for review', 'Merchant completed onboarding submission')
  } else if (submitted && !created) {
    push(out, submitted, 'Application submitted for review')
  }

  const sorted = sortActivityTimelineAscending(out)
  const maxAt = sorted.reduce((acc, e) => Math.max(acc, new Date(e.at).getTime()), 0)
  const updatedRaw = merchant.updated_at
  const updatedMs = updatedRaw ? new Date(updatedRaw).getTime() : 0

  const status = merchant.status?.trim() || 'unknown'
  const reason = merchant.rejection_reason?.trim()
  const statusLine = `Current status: ${status}`
  const reasonLine =
    reason && status === 'rejected'
      ? ` · Rejection reason on file: ${reason.length > 160 ? `${reason.slice(0, 157)}…` : reason}`
      : ''

  if (updatedMs > maxAt + 1000) {
    sorted.push({
      at: String(updatedRaw).trim(),
      title: 'Record last updated',
      subtitle: `${statusLine}${reasonLine} — may reflect profile edits, commission changes, or review outcome without separate audit rows`,
    })
  }

  return sortActivityTimelineAscending(sorted)
}
