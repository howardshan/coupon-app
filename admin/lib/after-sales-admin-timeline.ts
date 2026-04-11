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
