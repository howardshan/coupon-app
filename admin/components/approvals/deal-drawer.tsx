'use client'

import { useEffect, useMemo, useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { toast } from 'sonner'
import type { DealItem } from '@/app/(dashboard)/approvals/page'
import { setDealActive, rejectDeal } from '@/app/actions/admin'
import AdminActivityTimelineCard from '@/components/admin-activity-timeline-card'
import { buildDealTimeline } from '@/lib/deal-admin-timeline'

type RejectionRecord = {
  id: string
  reason: string
  created_at: string
  deal_snapshot?: Record<string, unknown> | null
  users?: { email: string } | null
}

// 菜品解析工具
function parseDish(d: unknown): { name: string; qty?: string; subtotal?: string } {
  if (typeof d === 'string') {
    const parts = d.split('::')
    return { name: parts[0], qty: parts[1], subtotal: parts[2] }
  }
  if (d && typeof d === 'object') {
    const obj = d as Record<string, unknown>
    return {
      name: (obj.name as string) ?? String(d),
      qty: obj.qty != null ? String(obj.qty) : undefined,
      subtotal: obj.subtotal != null ? String(obj.subtotal) : undefined,
    }
  }
  return { name: String(d) }
}

const DAY_LABELS: Record<string, string> = {
  Mon: 'Monday', Tue: 'Tuesday', Wed: 'Wednesday',
  Thu: 'Thursday', Fri: 'Friday', Sat: 'Saturday', Sun: 'Sunday',
}

function validityLabel(type: string | null, days: number | null): string {
  if (!type || type === 'fixed_date') return 'Fixed date'
  if (type === 'short_after_purchase') return `${days ?? '?'} days after purchase (short-term)`
  if (type === 'long_after_purchase') return `${days ?? '?'} days after purchase (long-term)`
  return type
}

export default function DealDrawer({
  deal,
  onClose,
}: {
  deal: DealItem
  onClose: () => void
}) {
  const router = useRouter()
  const [isPending, startTransition] = useTransition()
  const [currentImageIdx, setCurrentImageIdx] = useState(0)
  const [showRejectForm, setShowRejectForm] = useState(false)
  const [rejectReason, setRejectReason] = useState('')
  const [rejectionHistory, setRejectionHistory] = useState<RejectionRecord[]>([])
  const [historyLoading, setHistoryLoading] = useState(true)

  // 构建图片列表：优先 deal_images，fallback image_urls
  const images: string[] = deal.dealImages.length > 0
    ? deal.dealImages.sort((a, b) => (b.isPrimary ? 1 : 0) - (a.isPrimary ? 1 : 0)).map(i => i.imageUrl)
    : deal.imageUrls

  // 加载驳回历史
  useEffect(() => {
    setHistoryLoading(true)
    fetch(`/api/approvals/deal-rejections/${deal.id}`)
      .then(res => res.ok ? res.json() : { records: [] })
      .then(data => setRejectionHistory(data.records ?? []))
      .catch(() => setRejectionHistory([]))
      .finally(() => setHistoryLoading(false))
  }, [deal.id])

  const dealPreviewTimeline = useMemo(
    () =>
      buildDealTimeline(
        {
          created_at: deal.createdAt,
          updated_at: deal.updatedAt,
          published_at: deal.publishedAt,
          expires_at: deal.expiresAt,
          deal_status: deal.dealStatus,
          is_active: deal.isActive,
        },
        rejectionHistory.map((r) => ({
          created_at: r.created_at,
          reason: r.reason,
          users: r.users,
        }))
      ),
    [deal, rejectionHistory]
  )

  function handleApprove() {
    startTransition(async () => {
      try {
        await setDealActive(deal.id, true)
        toast.success('Deal is now live')
        onClose()
        router.refresh()
      } catch (e) {
        toast.error(e instanceof Error ? e.message : 'Action failed')
      }
    })
  }

  function handleReject() {
    if (!rejectReason.trim()) {
      toast.error('Please enter a rejection reason')
      return
    }
    startTransition(async () => {
      try {
        await rejectDeal(deal.id, rejectReason)
        toast.success('Deal rejected')
        setShowRejectForm(false)
        setRejectReason('')
        onClose()
        router.refresh()
      } catch (e) {
        toast.error(e instanceof Error ? e.message : 'Action failed')
      }
    })
  }

  const dishes = Array.isArray(deal.dishes) ? deal.dishes : []

  return (
    <div className="fixed inset-0 z-40 flex justify-end">
      <div className="flex-1 bg-black/30" onClick={onClose} />
      <div className="h-full w-full max-w-2xl overflow-y-auto bg-white shadow-2xl flex flex-col">

        {/* 抽屉头部 */}
        <div className="flex items-center justify-between border-b border-gray-200 px-6 py-4 sticky top-0 bg-white z-10">
          <div>
            <span className="text-xs font-semibold uppercase tracking-wide text-blue-600 bg-blue-100 px-2 py-0.5 rounded-full">
              Deal Review
            </span>
            <h2 className="text-lg font-bold text-gray-900 mt-1 line-clamp-1">{deal.title}</h2>
            <p className="text-sm text-gray-500">{deal.merchantName}</p>
          </div>
          <button type="button" onClick={onClose} className="p-2 rounded-full hover:bg-gray-100 text-gray-500">
            ✕
          </button>
        </div>

        <div className="flex-1 px-6 py-6 space-y-6">

          {/* 图片画廊 */}
          {images.length > 0 && (
            <section>
              <div className="relative rounded-xl overflow-hidden bg-gray-100 aspect-video">
                <img
                  src={images[currentImageIdx]}
                  alt={`Deal image ${currentImageIdx + 1}`}
                  className="w-full h-full object-cover"
                />
                {images.length > 1 && (
                  <div className="absolute inset-x-0 bottom-3 flex justify-center gap-1.5">
                    {images.map((_, i) => (
                      <button
                        key={i}
                        type="button"
                        onClick={() => setCurrentImageIdx(i)}
                        className={`w-2 h-2 rounded-full transition-colors ${i === currentImageIdx ? 'bg-white' : 'bg-white/50'}`}
                      />
                    ))}
                  </div>
                )}
                {images.length > 1 && (
                  <>
                    <button
                      type="button"
                      onClick={() => setCurrentImageIdx(i => Math.max(0, i - 1))}
                      disabled={currentImageIdx === 0}
                      className="absolute left-2 top-1/2 -translate-y-1/2 p-1.5 rounded-full bg-black/40 text-white disabled:opacity-30"
                    >
                      ‹
                    </button>
                    <button
                      type="button"
                      onClick={() => setCurrentImageIdx(i => Math.min(images.length - 1, i + 1))}
                      disabled={currentImageIdx === images.length - 1}
                      className="absolute right-2 top-1/2 -translate-y-1/2 p-1.5 rounded-full bg-black/40 text-white disabled:opacity-30"
                    >
                      ›
                    </button>
                  </>
                )}
              </div>
            </section>
          )}

          {/* 价格信息 */}
          <section className="rounded-xl border border-gray-200 p-4">
            <div className="flex items-end gap-3 flex-wrap">
              <span className="text-2xl font-bold text-gray-900">${deal.discountPrice.toFixed(2)}</span>
              <span className="text-base text-gray-400 line-through">${deal.originalPrice.toFixed(2)}</span>
              {deal.discountLabel && (
                <span className="px-2 py-0.5 bg-orange-100 text-orange-700 text-sm font-semibold rounded-full">
                  {deal.discountLabel}
                </span>
              )}
            </div>
            <dl className="mt-3 grid grid-cols-2 gap-x-4 gap-y-2 text-sm">
              {deal.stockLimit != null && (
                <div>
                  <dt className="text-gray-500">Stock Limit</dt>
                  <dd className="font-medium">{deal.stockLimit}</dd>
                </div>
              )}
              {deal.expiresAt && (
                <div>
                  <dt className="text-gray-500">Expires</dt>
                  <dd className="font-medium">{new Date(deal.expiresAt).toLocaleDateString()}</dd>
                </div>
              )}
            </dl>
          </section>

          {/* 套餐与菜品 */}
          {dishes.length > 0 && (
            <section className="rounded-xl border border-gray-200 p-4">
              <h3 className="font-semibold text-gray-800 mb-3">Dishes / Items</h3>
              <div className="space-y-1">
                {dishes.map((d, i) => {
                  const { name, qty, subtotal } = parseDish(d)
                  return (
                    <div key={i} className="flex items-center justify-between text-sm py-1 border-b border-gray-100 last:border-0">
                      <span className="text-gray-900">{name}</span>
                      <div className="flex items-center gap-4 text-gray-500">
                        {qty && <span>×{qty}</span>}
                        {subtotal && <span>${subtotal}</span>}
                      </div>
                    </div>
                  )
                })}
              </div>
            </section>
          )}

          {deal.packageContents && (
            <section className="rounded-xl border border-gray-200 p-4">
              <h3 className="font-semibold text-gray-800 mb-2">Package Contents</h3>
              <p className="text-sm text-gray-700 whitespace-pre-line">{deal.packageContents}</p>
            </section>
          )}

          {/* 使用规则 */}
          <section className="rounded-xl border border-gray-200 p-4">
            <h3 className="font-semibold text-gray-800 mb-3">Usage Rules</h3>
            <dl className="grid grid-cols-2 gap-x-4 gap-y-3 text-sm">
              <div>
                <dt className="text-gray-500">Validity</dt>
                <dd className="font-medium">{validityLabel(deal.validityType, deal.validityDays)}</dd>
              </div>
              {deal.maxPerPerson != null && (
                <div>
                  <dt className="text-gray-500">Max per Person</dt>
                  <dd className="font-medium">{deal.maxPerPerson}</dd>
                </div>
              )}
              <div>
                <dt className="text-gray-500">Stackable</dt>
                <dd className="font-medium">{deal.isStackable ? 'Yes' : 'No'}</dd>
              </div>
            </dl>
            {deal.usageDays && deal.usageDays.length > 0 && (
              <div className="mt-3">
                <dt className="text-sm text-gray-500 mb-1">Available Days</dt>
                <dd className="flex flex-wrap gap-1">
                  {deal.usageDays.map(day => (
                    <span key={day} className="px-2 py-0.5 bg-gray-100 text-gray-700 text-xs rounded-full">
                      {DAY_LABELS[day] ?? day}
                    </span>
                  ))}
                </dd>
              </div>
            )}
            {deal.usageNotes && (
              <div className="mt-3 pt-3 border-t border-gray-100">
                <dt className="text-sm text-gray-500 mb-1">Usage Notes</dt>
                <dd className="text-sm text-gray-700 whitespace-pre-line">{deal.usageNotes}</dd>
              </div>
            )}
          </section>

          {/* 商家信息 */}
          <section className="rounded-xl border border-gray-200 p-4">
            <h3 className="font-semibold text-gray-800 mb-2">Merchant</h3>
            <p className="text-sm font-medium text-gray-900">{deal.merchantName}</p>
            {deal.merchantAddress && (
              <p className="text-sm text-gray-500 mt-0.5">{deal.merchantAddress}</p>
            )}
          </section>

          {!historyLoading && (
            <AdminActivityTimelineCard
              title="Activity preview"
              footnote="Same derivation as deal detail page. Open full deal below for complete context."
              events={dealPreviewTimeline}
            />
          )}

          {/* 拒绝原因输入框 */}
          {showRejectForm && (
            <section className="rounded-xl border border-red-200 bg-red-50 p-4 space-y-3">
              <h3 className="font-semibold text-red-800">Rejection Reason</h3>
              <textarea
                value={rejectReason}
                onChange={e => setRejectReason(e.target.value)}
                rows={3}
                placeholder="Enter the reason for rejecting this deal…"
                className="w-full rounded-lg border border-red-300 px-3 py-2 text-sm bg-white"
              />
              <div className="flex justify-end gap-2">
                <button
                  type="button"
                  onClick={() => { setShowRejectForm(false); setRejectReason('') }}
                  className="px-3 py-1.5 rounded-lg border border-gray-300 text-sm"
                >
                  Cancel
                </button>
                <button
                  type="button"
                  onClick={handleReject}
                  disabled={isPending || !rejectReason.trim()}
                  className="px-3 py-1.5 rounded-lg bg-rose-600 text-sm font-semibold text-white hover:bg-rose-700 disabled:opacity-50"
                >
                  {isPending ? 'Rejecting…' : 'Confirm Reject'}
                </button>
              </div>
            </section>
          )}
        </div>

        {/* 审批操作区：仅 deal_status=pending；历史 Deal 只读 */}
        {deal.dealStatus === 'pending' && (
          <div className="border-t border-gray-200 px-6 py-4 space-y-3 bg-white sticky bottom-0">
            <button
              type="button"
              onClick={handleApprove}
              disabled={isPending}
              className="w-full rounded-lg bg-emerald-600 px-4 py-2.5 font-semibold text-white hover:bg-emerald-700 transition-colors text-sm disabled:opacity-50"
            >
              {isPending ? 'Publishing…' : 'Approve & Publish'}
            </button>
            <button
              type="button"
              onClick={() => setShowRejectForm(v => !v)}
              disabled={isPending}
              className="w-full rounded-lg border border-rose-400 px-4 py-2.5 font-semibold text-rose-700 hover:bg-rose-50 transition-colors text-sm disabled:opacity-50"
            >
              Reject
            </button>
            <a
              href={`/deals/${deal.id}`}
              target="_blank"
              rel="noreferrer"
              className="block text-center text-sm text-gray-500 hover:text-gray-800"
            >
              Open deal detail (full activity timeline) →
            </a>
          </div>
        )}
        {deal.dealStatus && deal.dealStatus !== 'pending' && (
          <div className="border-t border-gray-200 px-6 py-4 bg-white sticky bottom-0">
            <a
              href={`/deals/${deal.id}`}
              target="_blank"
              rel="noreferrer"
              className="block text-center text-sm text-blue-600 hover:underline"
            >
              Open deal detail (full activity timeline) →
            </a>
          </div>
        )}
      </div>
    </div>
  )
}
