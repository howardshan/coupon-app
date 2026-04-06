/**
 * 后台通用活动时间线条目（由已有表字段推导，非独立审计表）
 * 各域 builder 输出此结构，由 AdminActivityTimelineCard 展示。
 */

export type AdminActivityTimelineEntry = {
  /** ISO 时间字符串，用于排序与展示 */
  at: string
  /** 主标题（英文，面向北美后台） */
  title: string
  /** 副标题：原因、操作者、关联 ID 等 */
  subtitle?: string
  /** 可选：条目关联的证据链接（如售后时间线） */
  attachments?: string[]
}

/** 按时间升序（最早在上，适合纵向时间线） */
export function sortActivityTimelineAscending(
  entries: AdminActivityTimelineEntry[]
): AdminActivityTimelineEntry[] {
  return [...entries].sort((a, b) => new Date(a.at).getTime() - new Date(b.at).getTime())
}
