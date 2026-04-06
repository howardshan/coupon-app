/**
 * 退款争议（refund_requests）— Admin 活动时间线
 * 由表内时间戳与状态推导；注释中文；展示文案英文。
 */

import {
  sortActivityTimelineAscending,
  type AdminActivityTimelineEntry,
} from '@/lib/admin-activity-timeline-types'

export type RefundDisputeTimelineInput = {
  id?: string
  createdAt: string
  updatedAt?: string | null
  status?: string | null
  refundAmount?: number
  userReason?: string | null
  merchantDecision?: string | null
  merchantReason?: string | null
  merchantDecidedAt?: string | null
  adminDecision?: string | null
  adminReason?: string | null
  adminDecidedAt?: string | null
  completedAt?: string | null
}

function truncate(s: string | null | undefined, max: number): string {
  if (s == null) return ''
  const t = String(s).trim()
  if (!t) return ''
  if (t.length <= max) return t
  return `${t.slice(0, max - 1)}…`
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

/**
 * 单条 refund_request 的时间线节点（升序由调用方再 sort 或由 merge 统一 sort）
 */
export function buildRefundDisputeTimeline(
  row: RefundDisputeTimelineInput,
  options?: { multiDisputeHint?: string }
): AdminActivityTimelineEntry[] {
  const out: AdminActivityTimelineEntry[] = []
  const hint = options?.multiDisputeHint?.trim()
  const withHint = (sub?: string) => {
    if (!hint) return sub
    return sub ? `${hint} · ${sub}` : hint
  }

  const amt =
    row.refundAmount != null && !Number.isNaN(Number(row.refundAmount))
      ? `$${Number(row.refundAmount).toFixed(2)}`
      : ''
  const ur = truncate(row.userReason, 200)
  const filedSub = [amt, ur].filter(Boolean).join(' · ')
  push(out, row.createdAt, 'Refund dispute submitted', withHint(filedSub || undefined))

  if (row.merchantDecidedAt) {
    const dec = row.merchantDecision
    if (dec === 'approved') {
      push(
        out,
        row.merchantDecidedAt,
        'Merchant approved refund',
        withHint('Proceeding per payout / admin rules')
      )
    } else if (dec === 'rejected') {
      push(
        out,
        row.merchantDecidedAt,
        'Merchant rejected refund request',
        withHint(truncate(row.merchantReason, 220) || 'Reason on file')
      )
    } else {
      push(
        out,
        row.merchantDecidedAt,
        'Merchant decision recorded',
        withHint(dec ? `Decision: ${dec}` : undefined)
      )
    }
  }

  if (row.adminDecidedAt) {
    const dec = row.adminDecision
    if (dec === 'approved') {
      push(
        out,
        row.adminDecidedAt,
        'Admin approved refund',
        withHint(truncate(row.adminReason, 220) || undefined)
      )
    } else if (dec === 'rejected') {
      push(
        out,
        row.adminDecidedAt,
        'Admin rejected refund',
        withHint(truncate(row.adminReason, 220) || undefined)
      )
    } else {
      push(
        out,
        row.adminDecidedAt,
        'Admin decision recorded',
        withHint(dec ? `Decision: ${dec}` : undefined)
      )
    }
  }

  if (row.completedAt) {
    push(out, row.completedAt, 'Refund completed', withHint(undefined))
  }

  if (row.status === 'cancelled' && row.updatedAt) {
    push(out, row.updatedAt, 'Refund dispute cancelled', withHint('Withdrawn by customer'))
  }

  return sortActivityTimelineAscending(out)
}

/**
 * 同一订单下多条争议：按 createdAt 排序后合并为一条时间线（全局按时间升序）
 */
export function buildMergedOrderRefundDisputeTimelines(
  rows: RefundDisputeTimelineInput[]
): AdminActivityTimelineEntry[] {
  if (!rows.length) return []
  const sorted = [...rows].sort(
    (a, b) => new Date(a.createdAt).getTime() - new Date(b.createdAt).getTime()
  )
  const multi = sorted.length > 1
  const merged: AdminActivityTimelineEntry[] = []
  sorted.forEach((r, i) => {
    const hint = multi
      ? `Dispute ${i + 1}${r.id ? ` · ${String(r.id).slice(0, 8)}…` : ''}`
      : undefined
    merged.push(...buildRefundDisputeTimeline(r, { multiDisputeHint: hint }))
  })
  return sortActivityTimelineAscending(merged)
}
