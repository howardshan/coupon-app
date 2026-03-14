'use client'

import { useState } from 'react'

interface RejectionRecord {
  id: string
  reason: string
  created_at: string
  deal_snapshot?: Record<string, unknown> | null
  users?: { email: string } | null
}

export default function RejectionHistory({ records }: { records: RejectionRecord[] }) {
  const [expandedId, setExpandedId] = useState<string | null>(null)

  if (!records || records.length === 0) return null

  return (
    <div className="mt-3 space-y-2">
      <p className="text-sm font-semibold text-red-800">
        Rejection History ({records.length})
      </p>
      {records.map((r) => {
        const isExpanded = expandedId === r.id
        const snapshot = r.deal_snapshot as Record<string, unknown> | null

        return (
          <div key={r.id} className="bg-red-50 border border-red-200 rounded-lg overflow-hidden">
            <div className="p-3">
              <div className="flex items-center justify-between mb-1">
                <span className="text-xs text-red-600 font-medium">
                  {r.users?.email ?? 'admin'}
                </span>
                <span className="text-xs text-red-400">
                  {new Date(r.created_at).toLocaleString()}
                </span>
              </div>
              <p className="text-sm text-red-700">{r.reason}</p>
              {snapshot && (
                <button
                  type="button"
                  onClick={() => setExpandedId(isExpanded ? null : r.id)}
                  className="mt-2 text-xs text-red-500 hover:text-red-700 underline"
                >
                  {isExpanded ? 'Hide snapshot ▲' : 'View deal snapshot ▼'}
                </button>
              )}
            </div>

            {isExpanded && snapshot && (
              <div className="border-t border-red-200 bg-white p-3">
                <dl className="grid grid-cols-1 sm:grid-cols-2 gap-x-4 gap-y-2 text-xs">
                  <div><dt className="text-gray-400">Title</dt><dd className="text-gray-800">{snapshot.title as string ?? '—'}</dd></div>
                  <div><dt className="text-gray-400">Category</dt><dd className="text-gray-800">{snapshot.category as string ?? '—'}</dd></div>
                  <div><dt className="text-gray-400">Original price</dt><dd className="text-gray-800">${String(snapshot.original_price ?? '—')}</dd></div>
                  <div><dt className="text-gray-400">Sale price</dt><dd className="text-gray-800">${String(snapshot.discount_price ?? '—')}</dd></div>
                  <div><dt className="text-gray-400">Stock limit</dt><dd className="text-gray-800">{String(snapshot.stock_limit ?? '—')}</dd></div>
                  <div><dt className="text-gray-400">Status at rejection</dt><dd className="text-gray-800">{snapshot.deal_status as string ?? '—'}</dd></div>
                  <div><dt className="text-gray-400">Expires at</dt><dd className="text-gray-800">{snapshot.expires_at ? new Date(snapshot.expires_at as string).toLocaleString() : '—'}</dd></div>
                  <div><dt className="text-gray-400">Address</dt><dd className="text-gray-800">{snapshot.address as string || ((snapshot.merchants as any)?.address ?? '—')}</dd></div>
                </dl>
                {snapshot.description && (
                  <div className="mt-2 pt-2 border-t border-gray-100">
                    <dt className="text-xs text-gray-400">Description</dt>
                    <dd className="text-xs text-gray-800 mt-1">{snapshot.description as string}</dd>
                  </div>
                )}
                {snapshot.dishes && Array.isArray(snapshot.dishes) && (snapshot.dishes as unknown[]).length > 0 && (
                  <div className="mt-2 pt-2 border-t border-gray-100">
                    <dt className="text-xs text-gray-400">Dishes</dt>
                    <dd className="text-xs text-gray-800 mt-1">
                      {(snapshot.dishes as unknown[]).map((d, i) => (
                        <span key={i}>{typeof d === 'string' ? d : (d as any)?.name ?? String(d)}{i < (snapshot.dishes as unknown[]).length - 1 ? ', ' : ''}</span>
                      ))}
                    </dd>
                  </div>
                )}
                {snapshot.deal_images && Array.isArray(snapshot.deal_images) && (snapshot.deal_images as any[]).length > 0 && (
                  <div className="mt-2 pt-2 border-t border-gray-100">
                    <dt className="text-xs text-gray-400 mb-1">Images</dt>
                    <div className="flex flex-wrap gap-2">
                      {(snapshot.deal_images as any[]).map((img, i) => (
                        <img key={i} src={img.image_url} alt="" className="w-16 h-16 rounded object-cover border border-gray-200" />
                      ))}
                    </div>
                  </div>
                )}
              </div>
            )}
          </div>
        )
      })}
    </div>
  )
}
