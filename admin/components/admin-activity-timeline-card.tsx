import type { AdminActivityTimelineEntry } from '@/lib/admin-activity-timeline-types'

function formatWhen(iso: string): string {
  try {
    return new Date(iso).toLocaleString('en-US', {
      month: 'short',
      day: 'numeric',
      year: 'numeric',
      hour: 'numeric',
      minute: '2-digit',
    })
  } catch {
    return iso
  }
}

type Props = {
  /** 卡片主标题（英文） */
  title: string
  /** 标题下方说明（英文）；无则省略整段 */
  footnote?: string
  events: AdminActivityTimelineEntry[]
}

/**
 * 通用活动时间线卡片（样式与订单详情 Activity timeline 对齐）
 */
export default function AdminActivityTimelineCard({ title, footnote, events }: Props) {
  if (events.length === 0) return null

  return (
    <div className="rounded-2xl border border-slate-200/90 bg-white p-5 shadow-sm ring-1 ring-slate-900/[0.04] sm:p-6">
      <h2
        className={`text-sm font-bold uppercase tracking-wide text-slate-500 ${
          footnote ? 'mb-1' : 'mb-5'
        }`}
      >
        {title}
      </h2>
      {footnote ? <p className="mb-5 text-xs text-slate-500">{footnote}</p> : null}

      <ul className="space-y-0">
        {events.map((e, i) => (
          <li key={`${e.at}-${e.title}-${i}`} className={`flex gap-4 ${i < events.length - 1 ? 'pb-2' : ''}`}>
            <div className="flex w-5 shrink-0 flex-col items-center pt-1">
              <span
                className="z-[1] h-3 w-3 shrink-0 rounded-full border-2 border-white bg-blue-600 shadow-sm ring-1 ring-slate-200"
                aria-hidden
              />
              {i < events.length - 1 ? (
                <span className="mt-1 min-h-[2.75rem] w-0.5 flex-1 rounded-full bg-slate-200" aria-hidden />
              ) : null}
            </div>
            <div className="min-w-0 flex-1 pb-6">
              <p className="text-sm font-semibold text-slate-900">{e.title}</p>
              {e.subtitle ? <p className="mt-1 text-sm text-slate-600">{e.subtitle}</p> : null}
              <time className="mt-1 block text-xs tabular-nums text-slate-500" dateTime={e.at}>
                {formatWhen(e.at)}
              </time>
            </div>
          </li>
        ))}
      </ul>
    </div>
  )
}
