'use client'

// 用户当前法律文档同意状态卡片组件

export type ConsentStatusItem = {
  document_title: string
  document_slug: string
  document_type: string       // 'user' | 'merchant' | 'both'
  current_version: number
  consented_version: number | null  // null = 从未同意
  consented_at: string | null
  requires_re_consent: boolean
  is_active: boolean
}

type Props = { items: ConsentStatusItem[] }

/** 格式化日期时间 */
function formatDt(iso: string | null) {
  if (!iso) return '—'
  try {
    return new Date(iso).toLocaleString('en-US', {
      dateStyle: 'medium',
      timeStyle: 'short',
    })
  } catch {
    return iso
  }
}

/** 根据同意状态返回状态标签和样式 */
function resolveStatus(item: ConsentStatusItem): { label: string; className: string } {
  if (!item.is_active) {
    return { label: 'Inactive', className: 'bg-gray-100 text-gray-600' }
  }
  if (item.consented_version === null) {
    return { label: '❌ Never consented', className: 'bg-red-50 text-red-700' }
  }
  if (item.consented_version === item.current_version) {
    return { label: '✅ Current', className: 'bg-green-50 text-green-700' }
  }
  if (item.consented_version < item.current_version && item.requires_re_consent) {
    return { label: '⚠️ Outdated', className: 'bg-amber-50 text-amber-700' }
  }
  // consented_version < current_version 但不需要 re-consent
  return { label: '✅ Current', className: 'bg-green-50 text-green-700' }
}

export default function ConsentStatusCard({ items }: Props) {
  return (
    <div className="rounded-2xl border border-slate-200/90 bg-white p-5 shadow-sm ring-1 ring-slate-900/[0.04] sm:p-6">
      <h2 className="mb-5 text-sm font-bold uppercase tracking-wide text-slate-500">
        Consent Status
      </h2>

      {items.length === 0 ? (
        <p className="text-sm text-slate-400">No legal documents found.</p>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full text-left text-sm">
            <thead>
              <tr className="border-b border-slate-200 text-xs font-semibold uppercase tracking-wider text-slate-400">
                <th className="pb-3 pr-4">Document</th>
                <th className="pb-3 pr-4">Type</th>
                <th className="pb-3 pr-4">Consented Version</th>
                <th className="pb-3 pr-4">Current Version</th>
                <th className="pb-3 pr-4">Status</th>
                <th className="pb-3">Date</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {items.map((item) => {
                const status = resolveStatus(item)
                return (
                  <tr key={item.document_slug} className="text-slate-700">
                    <td className="py-3 pr-4 font-medium text-slate-900">
                      {item.document_title}
                    </td>
                    <td className="py-3 pr-4 capitalize">{item.document_type}</td>
                    <td className="py-3 pr-4 tabular-nums">
                      {item.consented_version !== null ? `v${item.consented_version}` : '—'}
                    </td>
                    <td className="py-3 pr-4 tabular-nums">v{item.current_version}</td>
                    <td className="py-3 pr-4">
                      <span
                        className={`inline-block rounded-full px-2.5 py-0.5 text-xs font-medium ${status.className}`}
                      >
                        {status.label}
                      </span>
                    </td>
                    <td className="py-3 whitespace-nowrap tabular-nums text-slate-500">
                      {formatDt(item.consented_at)}
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}
