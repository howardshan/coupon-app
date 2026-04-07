'use client'

// 法律审计日志时间线组件（用户/商家详情页 Legal tab 使用）
// 支持分页加载、按事件类型筛选、导出 CSV/JSON

import { useState, useCallback } from 'react'
import { toast } from 'sonner'
import { getUserLegalTimeline, exportUserLegalTimeline } from '@/app/actions/legal'

export type LegalAuditLogEntry = {
  id: string
  user_id: string
  actor_id: string | null
  actor_role: string
  event_type: string
  document_id: string | null
  document_slug: string | null
  document_title: string | null
  document_version: number | null
  details: Record<string, any>
  ip_address: string | null
  user_agent: string | null
  device_info: string | null
  app_version: string | null
  platform: string | null
  locale: string | null
  created_at: string
  integrity_hash: string
}

type Props = {
  userId: string
  initialData: LegalAuditLogEntry[]
  totalCount: number
}

/** 每页加载条数 */
const PAGE_SIZE = 20

/** 可筛选的事件类型列表 */
const EVENT_TYPE_OPTIONS = [
  { value: '', label: 'All' },
  { value: 'consent_given', label: 'Consent Given' },
  { value: 'consent_superseded', label: 'Consent Superseded' },
  { value: 'consent_prompted', label: 'Consent Prompted' },
  { value: 'consent_declined', label: 'Consent Declined' },
  { value: 'document_published', label: 'Document Published' },
  { value: 'document_setting_changed', label: 'Document Setting Changed' },
] as const

/** 事件类型对应的时间线圆点颜色 */
function dotColor(eventType: string): string {
  if (eventType === 'consent_given') return 'bg-green-500'
  if (eventType === 'consent_superseded') return 'bg-amber-500'
  if (eventType === 'consent_declined') return 'bg-red-500'
  if (eventType.startsWith('document_')) return 'bg-blue-500'
  return 'bg-slate-400'
}

/** 事件类型标签颜色 */
function badgeClass(eventType: string): string {
  if (eventType === 'consent_given') return 'bg-green-50 text-green-700'
  if (eventType === 'consent_superseded') return 'bg-amber-50 text-amber-700'
  if (eventType === 'consent_declined') return 'bg-red-50 text-red-700'
  if (eventType.startsWith('document_')) return 'bg-blue-50 text-blue-700'
  return 'bg-gray-100 text-gray-700'
}

/** 根据事件类型生成可读描述 */
function describeEvent(entry: LegalAuditLogEntry): string {
  const docLabel = entry.document_title
    ? `${entry.document_title}${entry.document_version != null ? ` v${entry.document_version}` : ''}`
    : 'Unknown document'

  switch (entry.event_type) {
    case 'consent_given':
      return `Accepted ${docLabel}`
    case 'consent_superseded':
      return `Consent invalidated due to new version published — ${docLabel}`
    case 'consent_prompted':
      return `Prompted to review ${docLabel}`
    case 'consent_declined':
      return `Declined ${docLabel}`
    case 'document_published':
      return `${docLabel} was published`
    case 'document_setting_changed':
      return `Settings changed for ${docLabel}`
    default:
      return `${entry.event_type} — ${docLabel}`
  }
}

/** 格式化时间戳（精确到秒+时区） */
function formatTs(iso: string): string {
  try {
    return new Date(iso).toLocaleString('en-US', {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
      timeZoneName: 'short',
    })
  } catch {
    return iso
  }
}

/** 格式化 event_type 为展示标签文字 */
function formatEventType(eventType: string): string {
  return eventType.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase())
}

/** 在客户端触发文件下载 */
function downloadBlob(content: string, filename: string, mime: string) {
  const blob = new Blob([content], { type: mime })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  document.body.appendChild(a)
  a.click()
  document.body.removeChild(a)
  URL.revokeObjectURL(url)
}

/** 可展开的详情区域 */
function ExpandableDetails({ entry }: { entry: LegalAuditLogEntry }) {
  const [open, setOpen] = useState(false)

  const detailRows = [
    { label: 'IP Address', value: entry.ip_address },
    { label: 'User Agent', value: entry.user_agent },
    { label: 'Device Info', value: entry.device_info },
    { label: 'App Version', value: entry.app_version },
    { label: 'Platform', value: entry.platform },
    { label: 'Locale', value: entry.locale },
  ]

  // details JSON 中的 trigger context
  const triggerContext = entry.details && Object.keys(entry.details).length > 0
    ? JSON.stringify(entry.details, null, 2)
    : null

  return (
    <div className="mt-2">
      <button
        type="button"
        onClick={() => setOpen(!open)}
        className="text-xs font-medium text-slate-500 hover:text-slate-700"
      >
        {open ? 'Hide details' : 'Show details'}
      </button>

      {open && (
        <div className="mt-2 space-y-1.5 rounded-lg border border-slate-200 bg-slate-50 p-3 text-xs text-slate-600">
          {detailRows.map(({ label, value }) =>
            value ? (
              <div key={label} className="flex gap-2">
                <span className="shrink-0 font-medium text-slate-500">{label}:</span>
                <span className="break-all">{value}</span>
              </div>
            ) : null,
          )}

          {triggerContext && (
            <div>
              <span className="font-medium text-slate-500">Trigger Context:</span>
              <pre className="mt-1 overflow-x-auto whitespace-pre-wrap rounded bg-white p-2 font-mono text-[11px] text-slate-600">
                {triggerContext}
              </pre>
            </div>
          )}

          <div className="flex gap-2">
            <span className="shrink-0 font-medium text-slate-500">Integrity Hash:</span>
            <span className="break-all font-mono">{entry.integrity_hash}</span>
          </div>

          <div className="flex gap-2">
            <span className="shrink-0 font-medium text-slate-500">Actor:</span>
            <span>{entry.actor_role || '—'}</span>
          </div>
        </div>
      )}
    </div>
  )
}

export default function LegalTimeline({ userId, initialData, totalCount }: Props) {
  const [entries, setEntries] = useState<LegalAuditLogEntry[]>(initialData)
  const [filter, setFilter] = useState('')
  const [loading, setLoading] = useState(false)
  const [exporting, setExporting] = useState(false)
  // 当前已加载的偏移量（用于 load more）
  const [offset, setOffset] = useState(initialData.length)

  /** 切换筛选条件时重新加载 */
  const handleFilterChange = useCallback(
    async (eventType: string) => {
      setFilter(eventType)
      setLoading(true)
      try {
        // 从第 1 页开始重新加载，page 基于 offset/PAGE_SIZE 推算为 1
        const result = await getUserLegalTimeline(userId, 1, PAGE_SIZE, eventType || undefined)
        setEntries(result.items)
        setOffset(result.items.length)
      } catch {
        toast.error('Failed to load timeline data')
      } finally {
        setLoading(false)
      }
    },
    [userId],
  )

  /** 加载更多 */
  const handleLoadMore = useCallback(async () => {
    setLoading(true)
    try {
      // 根据当前 offset 计算下一页页码
      const nextPage = Math.floor(offset / PAGE_SIZE) + 1
      const result = await getUserLegalTimeline(userId, nextPage, PAGE_SIZE, filter || undefined)
      setEntries((prev) => [...prev, ...result.items])
      setOffset((prev) => prev + result.items.length)
    } catch {
      toast.error('Failed to load more entries')
    } finally {
      setLoading(false)
    }
  }, [userId, filter, offset])

  /** 导出为 CSV */
  const handleExportCSV = useCallback(async () => {
    setExporting(true)
    try {
      const result = await exportUserLegalTimeline(userId, 'csv')
      downloadBlob(result.data, result.filename, 'text/csv')
      toast.success('CSV exported')
    } catch {
      toast.error('Failed to export CSV')
    } finally {
      setExporting(false)
    }
  }, [userId])

  /** 导出为 JSON */
  const handleExportJSON = useCallback(async () => {
    setExporting(true)
    try {
      const result = await exportUserLegalTimeline(userId, 'json')
      downloadBlob(result.data, result.filename, 'application/json')
      toast.success('JSON exported')
    } catch {
      toast.error('Failed to export JSON')
    } finally {
      setExporting(false)
    }
  }, [userId])

  const hasMore = entries.length < totalCount

  return (
    <div className="rounded-2xl border border-slate-200/90 bg-white p-5 shadow-sm ring-1 ring-slate-900/[0.04] sm:p-6">
      {/* 顶部栏：筛选 + 导出 */}
      <div className="mb-5 flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-3">
          <h2 className="text-sm font-bold uppercase tracking-wide text-slate-500">
            Legal Timeline
          </h2>
          <select
            value={filter}
            onChange={(e) => handleFilterChange(e.target.value)}
            className="rounded-lg border border-slate-200 bg-white px-3 py-1.5 text-xs text-slate-700 shadow-sm focus:border-blue-400 focus:outline-none focus:ring-1 focus:ring-blue-400"
          >
            {EVENT_TYPE_OPTIONS.map((opt) => (
              <option key={opt.value} value={opt.value}>
                {opt.label}
              </option>
            ))}
          </select>
        </div>

        <div className="flex items-center gap-2">
          <button
            type="button"
            onClick={handleExportCSV}
            disabled={exporting}
            className="rounded-lg border border-slate-200 bg-white px-3 py-1.5 text-xs font-medium text-slate-600 shadow-sm hover:bg-slate-50 disabled:opacity-50"
          >
            Export CSV
          </button>
          <button
            type="button"
            onClick={handleExportJSON}
            disabled={exporting}
            className="rounded-lg border border-slate-200 bg-white px-3 py-1.5 text-xs font-medium text-slate-600 shadow-sm hover:bg-slate-50 disabled:opacity-50"
          >
            Export JSON
          </button>
        </div>
      </div>

      {/* 时间线主体 */}
      {loading && entries.length === 0 ? (
        <p className="py-8 text-center text-sm text-slate-400">Loading...</p>
      ) : entries.length === 0 ? (
        <p className="py-8 text-center text-sm text-slate-400">No legal activity recorded.</p>
      ) : (
        <ul className="space-y-0">
          {entries.map((entry, i) => (
            <li key={entry.id} className={`flex gap-4 ${i < entries.length - 1 ? 'pb-2' : ''}`}>
              {/* 左侧时间线竖线 + 圆点 */}
              <div className="flex w-5 shrink-0 flex-col items-center pt-1">
                <span
                  className={`z-[1] h-3 w-3 shrink-0 rounded-full border-2 border-white shadow-sm ring-1 ring-slate-200 ${dotColor(entry.event_type)}`}
                  aria-hidden
                />
                {i < entries.length - 1 ? (
                  <span
                    className="mt-1 min-h-[2.75rem] w-0.5 flex-1 rounded-full bg-slate-200"
                    aria-hidden
                  />
                ) : null}
              </div>

              {/* 右侧卡片内容 */}
              <div className="min-w-0 flex-1 pb-6">
                {/* 第一行：事件类型标签 + 时间戳 + 文档信息 */}
                <div className="flex flex-wrap items-center gap-2">
                  <span
                    className={`inline-block rounded-full px-2 py-0.5 text-[11px] font-medium ${badgeClass(entry.event_type)}`}
                  >
                    {formatEventType(entry.event_type)}
                  </span>
                  {entry.document_title && (
                    <span className="text-xs font-medium text-slate-700">
                      {entry.document_title}
                      {entry.document_version != null ? ` v${entry.document_version}` : ''}
                    </span>
                  )}
                </div>

                {/* 时间戳 */}
                <time
                  className="mt-1 block text-xs tabular-nums text-slate-500"
                  dateTime={entry.created_at}
                >
                  {formatTs(entry.created_at)}
                </time>

                {/* 第二行：事件描述 */}
                <p className="mt-1 text-sm text-slate-700">{describeEvent(entry)}</p>

                {/* 可展开详情区域 */}
                <ExpandableDetails entry={entry} />
              </div>
            </li>
          ))}
        </ul>
      )}

      {/* Load More 按钮 */}
      {hasMore && entries.length > 0 && (
        <div className="mt-4 text-center">
          <button
            type="button"
            onClick={handleLoadMore}
            disabled={loading}
            className="rounded-lg border border-slate-200 bg-white px-5 py-2 text-sm font-medium text-slate-600 shadow-sm hover:bg-slate-50 disabled:opacity-50"
          >
            {loading ? 'Loading...' : 'Load More'}
          </button>
        </div>
      )}
    </div>
  )
}
