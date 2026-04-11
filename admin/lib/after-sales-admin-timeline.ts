/**
 * 售后单（after_sales_requests）— Admin 活动时间线条目
 * 注释中文；展示文案英文。
 */

import {
  sortActivityTimelineAscending,
  type AdminActivityTimelineEntry,
} from '@/lib/admin-activity-timeline-types'

export type AfterSalesTimelineInput = {
  id: string
  createdAt: string
  status: string
  reasonCode?: string | null
}

/** 售后详情 API 返回的 request.timeline（JSONB）单项 — 与 after-sales-drawer 类型对齐 */
export type AfterSalesApiTimelineEvent = {
  status: string
  actor: string
  note?: string
  attachments?: string[]
  at: string
}

function humanizeUnderscores(s: string): string {
  return s.replace(/_/g, ' ').trim()
}

function sentenceCaseStatus(s: string): string {
  const h = humanizeUnderscores(s)
  if (!h) return 'Update'
  return h.charAt(0).toUpperCase() + h.slice(1)
}

/** 非结案状态：与业务侧「活跃售后」一致 */
export const AFTER_SALES_TERMINAL_STATUSES = new Set([
  'refunded',
  'closed',
  'platform_rejected',
])

export function isActiveAfterSalesStatus(status: string): boolean {
  return !AFTER_SALES_TERMINAL_STATUSES.has(status)
}

/**
 * 每条售后单在创建时刻生成一条时间线节点（细粒度事件见 after_sales_events，此处保持轻量）
 */
export function buildAfterSalesRequestTimelineEntries(
  rows: AfterSalesTimelineInput[]
): AdminActivityTimelineEntry[] {
  if (!rows.length) return []
  const out: AdminActivityTimelineEntry[] = []
  for (const r of rows) {
    const code = (r.reasonCode ?? 'other').replace(/_/g, ' ')
    const st = r.status.replace(/_/g, ' ')
    out.push({
      at: r.createdAt,
      title: 'After-sales case opened',
      subtitle: `Reason: ${code} · Status: ${st} · Case ${r.id.slice(0, 8).toUpperCase()}…`,
    })
  }
  return sortActivityTimelineAscending(out)
}

/**
 * 将详情接口中的 timeline JSON 转为通用活动卡片条目（升序）
 * 标题：状态文案；副标题：Actor 与 note；附件原样交给卡片渲染
 */
export function buildAfterSalesTimelineEntries(
  timeline: AfterSalesApiTimelineEvent[] | null | undefined
): AdminActivityTimelineEntry[] {
  if (timeline == null || timeline.length === 0) return []
  const out: AdminActivityTimelineEntry[] = []
  for (const ev of timeline) {
    const at = String(ev.at ?? '').trim()
    if (!at) continue
    const title = sentenceCaseStatus(String(ev.status ?? ''))
    const actorPart = humanizeUnderscores(String(ev.actor ?? 'unknown'))
    const actorLine = `Actor: ${actorPart}`
    const note = ev.note?.trim()
    const subtitle = note != null && note.length > 0 ? `${actorLine}\n${note}` : actorLine
    const attachments = (ev.attachments ?? []).filter(
      (u) => typeof u === 'string' && u.trim().length > 0
    )
    out.push({
      at,
      title,
      subtitle,
      ...(attachments.length > 0 ? { attachments } : {}),
    })
  }
  return sortActivityTimelineAscending(out)
}

/**
 * 订单下多条售后：优先用 DB timeline JSON（含商家拒绝等真实时间），无则退回单条「opened」摘要
 */
export function mergeAfterSalesRowsToTimelineEvents(
  rows: Record<string, unknown>[]
): AdminActivityTimelineEntry[] {
  const merged: AdminActivityTimelineEntry[] = []
  for (const r of rows) {
    const tl = r.timeline as AfterSalesApiTimelineEvent[] | null | undefined
    const fromJson = buildAfterSalesTimelineEntries(Array.isArray(tl) ? tl : null)
    if (fromJson.length > 0) {
      merged.push(...fromJson)
    } else {
      merged.push(
        ...buildAfterSalesRequestTimelineEntries([
          {
            id: String(r.id ?? ''),
            createdAt: String(r.created_at ?? ''),
            status: String(r.status ?? ''),
            reasonCode: (r.reason_code as string | null) ?? null,
          },
        ])
      )
    }
  }
  return sortActivityTimelineAscending(merged)
}
