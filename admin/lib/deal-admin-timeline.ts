/**
 * Deal 详情页 — 活动时间线（由 deals 与 deal_rejections 已有字段推导）
 * 注释中文；展示文案英文。
 */

import {
  sortActivityTimelineAscending,
  type AdminActivityTimelineEntry,
} from '@/lib/admin-activity-timeline-types'

export type DealTimelineDealLike = {
  created_at?: string | null
  updated_at?: string | null
  published_at?: string | null
  expires_at?: string | null
  deal_status?: string | null
  is_active?: boolean | null
}

export type DealRejectionRecordLike = {
  created_at: string
  reason: string
  users?: { email?: string | null } | { email?: string | null }[] | null
}

function reviewerEmail(r: DealRejectionRecordLike): string {
  const u = r.users
  if (u == null) return 'Admin'
  const row = Array.isArray(u) ? u[0] : u
  return row?.email?.trim() || 'Admin'
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
 * 组装 Deal 时间线：创建、上架、驳回记录、对外过期日、可能的最后更新时间。
 * 下架/编辑等若无单独时间戳，仅体现在 updated_at（见卡片 footnote）。
 */
export function buildDealTimeline(
  deal: DealTimelineDealLike,
  rejections: DealRejectionRecordLike[]
): AdminActivityTimelineEntry[] {
  const out: AdminActivityTimelineEntry[] = []

  push(out, deal.created_at, 'Deal record created', 'First saved on platform')

  push(out, deal.published_at, 'Published to marketplace')

  const sortedRejections = [...rejections].sort(
    (a, b) => new Date(a.created_at).getTime() - new Date(b.created_at).getTime()
  )
  for (const r of sortedRejections) {
    const who = reviewerEmail(r)
    const reason = r.reason?.trim() || '—'
    push(out, r.created_at, 'Deal rejected', `${reason} · ${who}`)
  }

  push(
    out,
    deal.expires_at,
    'Listing expiry (customer-facing)',
    'Purchase or redemption window deadline — not an admin action time'
  )

  const sorted = sortActivityTimelineAscending(out)
  const maxAt = sorted.reduce((acc, e) => Math.max(acc, new Date(e.at).getTime()), 0)
  const updatedRaw = deal.updated_at
  const updatedMs = updatedRaw ? new Date(updatedRaw).getTime() : 0
  // 若 updated_at 明显晚于已有节点，补充一条（避免与驳回/创建同毫秒重复）
  if (updatedMs > maxAt + 1000) {
    sorted.push({
      at: String(updatedRaw).trim(),
      title: 'Record last updated',
      subtitle: 'May reflect edits, deactivation, or other DB updates without separate audit rows',
    })
  }

  return sortActivityTimelineAscending(sorted)
}
