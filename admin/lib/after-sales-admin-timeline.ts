import {
  type AdminActivityTimelineEntry,
  sortActivityTimelineAscending,
} from '@/lib/admin-activity-timeline-types'

/** API / JSONB `timeline` 元素形状（与 platform-after-sales 详情一致） */
export type AfterSalesTimelineRawEntry = {
  status: string
  actor: string
  note?: string
  attachments?: string[]
  at: string
}

function formatStatusLabel(status: string): string {
  return status.replaceAll('_', ' ')
}

/**
 * 将售后请求的 `timeline` JSONB 转为通用活动时间线条目（升序）
 */
export function buildAfterSalesTimelineEntries(
  raw: AfterSalesTimelineRawEntry[] | null | undefined
): AdminActivityTimelineEntry[] {
  if (!raw?.length) return []
  const mapped: AdminActivityTimelineEntry[] = raw.map((entry) => {
    const parts = [`Actor: ${entry.actor}`]
    if (entry.note?.trim()) parts.push(entry.note.trim())
    return {
      at: entry.at,
      title: formatStatusLabel(entry.status),
      subtitle: parts.join('\n'),
      attachments:
        entry.attachments && entry.attachments.length > 0
          ? [...entry.attachments]
          : undefined,
    }
  })
  return sortActivityTimelineAscending(mapped)
}
