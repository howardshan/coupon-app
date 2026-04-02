'use client'

import { useEffect, useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { toast } from 'sonner'
import type { MerchantItem } from '@/app/(dashboard)/approvals/page'
import { approveMerchant, rejectMerchant } from '@/app/actions/admin'

type Document = {
  id: string
  document_type: string
  file_url: string
  file_name: string
  uploaded_at: string
}

type MerchantDetail = {
  id: string
  user_id: string
  name: string
  company_name: string | null
  description: string | null
  contact_name: string | null
  contact_email: string | null
  phone: string | null
  category: string | null
  ein: string | null
  address: string | null
  submitted_at: string | null
  created_at: string
}

const DOC_TYPE_LABELS: Record<string, string> = {
  business_license: 'Business License',
  health_permit: 'Health Permit',
  food_service_license: 'Food Service License',
  cosmetology_license: 'Cosmetology License',
  massage_therapy_license: 'Massage Therapy License',
  facility_license: 'Facility License',
  general_business_permit: 'General Business Permit',
  storefront_photo: 'Storefront Photo',
  owner_id: 'Owner ID',
}

export default function MerchantDrawer({
  merchant,
  onClose,
}: {
  merchant: MerchantItem
  onClose: () => void
}) {
  const router = useRouter()
  const [isPending, startTransition] = useTransition()
  const [detail, setDetail] = useState<MerchantDetail | null>(null)
  const [documents, setDocuments] = useState<Document[]>([])
  const [loading, setLoading] = useState(true)
  const [fetchError, setFetchError] = useState<string | null>(null)
  const [showRejectModal, setShowRejectModal] = useState(false)
  const [rejectReason, setRejectReason] = useState('')

  // 点击抽屉时懒加载商家完整信息
  useEffect(() => {
    setLoading(true)
    setFetchError(null)
    fetch(`/api/approvals/merchant/${merchant.id}`)
      .then(async res => {
        if (!res.ok) throw new Error((await res.json())?.error ?? 'Failed to load')
        return res.json()
      })
      .then(data => {
        setDetail(data.merchant)
        setDocuments(data.documents ?? [])
      })
      .catch(err => setFetchError(err.message))
      .finally(() => setLoading(false))
  }, [merchant.id])

  function confirmReject() {
    startTransition(async () => {
      try {
        await rejectMerchant(merchant.id, rejectReason.trim() || null)
        toast.success('Merchant rejected')
        setShowRejectModal(false)
        onClose()
        router.refresh()
      } catch (e) {
        toast.error(e instanceof Error ? e.message : 'Action failed')
      }
    })
  }

  return (
    <>
      {/* 遮罩 */}
      <div className="fixed inset-0 z-40 flex justify-end">
        <div className="flex-1 bg-black/30" onClick={onClose} />
        <div className="h-full w-full max-w-2xl overflow-y-auto bg-white shadow-2xl flex flex-col">

          {/* 抽屉头部 */}
          <div className="flex items-center justify-between border-b border-gray-200 px-6 py-4 sticky top-0 bg-white z-10">
            <div>
              <span className="text-xs font-semibold uppercase tracking-wide text-purple-600 bg-purple-100 px-2 py-0.5 rounded-full">
                Merchant Application
              </span>
              <h2 className="text-lg font-bold text-gray-900 mt-1">{merchant.name}</h2>
            </div>
            <button type="button" onClick={onClose} className="p-2 rounded-full hover:bg-gray-100 text-gray-500">
              ✕
            </button>
          </div>

          <div className="flex-1 px-6 py-6 space-y-6">
            {loading && <p className="text-sm text-gray-500">Loading details…</p>}
            {fetchError && <p className="text-sm text-rose-600">Failed to load: {fetchError}</p>}

            {detail && (
              <>
                {/* 基本信息 */}
                <section className="rounded-xl border border-gray-200 p-4 space-y-3">
                  <h3 className="font-semibold text-gray-800">Business Info</h3>
                  <dl className="grid grid-cols-2 gap-x-4 gap-y-3 text-sm">
                    <div>
                      <dt className="text-gray-500">Business Name</dt>
                      <dd className="font-medium text-gray-900">{detail.name}</dd>
                    </div>
                    {detail.company_name && (
                      <div>
                        <dt className="text-gray-500">Company Name</dt>
                        <dd className="font-medium text-gray-900">{detail.company_name}</dd>
                      </div>
                    )}
                    <div>
                      <dt className="text-gray-500">Category</dt>
                      <dd className="font-medium text-gray-900">{detail.category ?? '—'}</dd>
                    </div>
                    <div>
                      <dt className="text-gray-500">EIN</dt>
                      <dd className="font-medium text-gray-900">{detail.ein ?? '—'}</dd>
                    </div>
                    <div className="col-span-2">
                      <dt className="text-gray-500">Address</dt>
                      <dd className="font-medium text-gray-900">{detail.address ?? '—'}</dd>
                    </div>
                  </dl>
                </section>

                {/* 联系人 */}
                <section className="rounded-xl border border-gray-200 p-4 space-y-3">
                  <h3 className="font-semibold text-gray-800">Contact</h3>
                  <dl className="grid grid-cols-2 gap-x-4 gap-y-3 text-sm">
                    <div>
                      <dt className="text-gray-500">Contact Name</dt>
                      <dd className="font-medium text-gray-900">{detail.contact_name ?? '—'}</dd>
                    </div>
                    <div>
                      <dt className="text-gray-500">Email</dt>
                      <dd className="font-medium text-gray-900">{detail.contact_email ?? '—'}</dd>
                    </div>
                    <div>
                      <dt className="text-gray-500">Phone</dt>
                      <dd className="font-medium text-gray-900">{detail.phone ?? '—'}</dd>
                    </div>
                    <div>
                      <dt className="text-gray-500">Applied</dt>
                      <dd className="font-medium text-gray-900">
                        {new Date(detail.submitted_at ?? detail.created_at).toLocaleString()}
                      </dd>
                    </div>
                  </dl>
                </section>

                {/* 描述 */}
                {detail.description && (
                  <section className="rounded-xl border border-gray-200 p-4">
                    <h3 className="font-semibold text-gray-800 mb-2">Description</h3>
                    <p className="text-sm text-gray-700 whitespace-pre-line">{detail.description}</p>
                  </section>
                )}
              </>
            )}

            {/* 证件材料 */}
            {documents.length > 0 && (
              <section className="space-y-3">
                <h3 className="font-semibold text-gray-800">Documents ({documents.length})</h3>
                <div className="space-y-3">
                  {documents.map(doc => (
                    <div key={doc.id} className="rounded-xl border border-gray-200 overflow-hidden">
                      <div className="flex items-center justify-between px-4 py-2 bg-gray-50 border-b border-gray-200">
                        <span className="text-sm font-medium text-gray-700">
                          {DOC_TYPE_LABELS[doc.document_type] ?? doc.document_type}
                        </span>
                        <a
                          href={doc.file_url}
                          target="_blank"
                          rel="noreferrer"
                          className="text-xs text-blue-600 hover:underline"
                        >
                          Open full size ↗
                        </a>
                      </div>
                      {/* 尝试内嵌显示图片；如非图片则显示下载链接 */}
                      <div className="p-3">
                        <img
                          src={doc.file_url}
                          alt={DOC_TYPE_LABELS[doc.document_type] ?? doc.document_type}
                          className="max-h-64 w-full object-contain rounded"
                          onError={e => { (e.target as HTMLImageElement).style.display = 'none' }}
                        />
                      </div>
                    </div>
                  ))}
                </div>
              </section>
            )}

            {!loading && documents.length === 0 && (
              <p className="text-sm text-gray-400">No documents uploaded.</p>
            )}
          </div>

          {/* 审批操作区 */}
          <div className="border-t border-gray-200 px-6 py-4 space-y-3 bg-white sticky bottom-0">
            <ApproveButton
              merchantId={merchant.id}
              merchantUserId={detail?.user_id ?? null}
              onSuccess={() => { onClose(); router.refresh() }}
            />
            <button
              type="button"
              onClick={() => setShowRejectModal(true)}
              disabled={isPending}
              className="w-full rounded-lg border border-rose-400 px-4 py-2.5 font-semibold text-rose-700 hover:bg-rose-50 transition-colors text-sm disabled:opacity-50"
            >
              Reject Application
            </button>
            <a
              href={`/merchants/${merchant.id}`}
              target="_blank"
              rel="noreferrer"
              className="block text-center text-sm text-gray-400 hover:text-gray-600"
            >
              View Full Profile →
            </a>
          </div>
        </div>
      </div>

      {/* 拒绝弹窗 */}
      {showRejectModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4">
          <div className="w-full max-w-md rounded-2xl bg-white p-6 shadow-xl">
            <h3 className="text-lg font-semibold text-gray-900">Reject Application</h3>
            <p className="mt-1 text-sm text-gray-500">Optionally provide a reason (visible to the merchant).</p>
            <textarea
              value={rejectReason}
              onChange={e => setRejectReason(e.target.value)}
              rows={3}
              placeholder="e.g. Incomplete documents, invalid EIN…"
              className="mt-3 w-full rounded-lg border border-gray-300 px-3 py-2 text-sm"
            />
            <div className="mt-4 flex justify-end gap-3">
              <button
                type="button"
                onClick={() => { setShowRejectModal(false); setRejectReason('') }}
                className="px-4 py-2 rounded-lg border border-gray-300 text-sm"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={confirmReject}
                disabled={isPending}
                className="px-4 py-2 rounded-lg bg-rose-600 text-sm font-semibold text-white hover:bg-rose-700 disabled:opacity-50"
              >
                {isPending ? 'Rejecting…' : 'Reject'}
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  )
}

// Approve 按钮组件：依赖父组件加载好的 user_id
function ApproveButton({
  merchantId,
  merchantUserId,
  onSuccess,
}: {
  merchantId: string
  merchantUserId: string | null
  onSuccess: () => void
}) {
  const [isPending, startTransition] = useTransition()

  function handleApprove() {
    if (!merchantUserId) {
      toast.error('Merchant user ID not loaded yet, please wait')
      return
    }
    startTransition(async () => {
      try {
        await approveMerchant(merchantId, merchantUserId)
        toast.success('Merchant approved')
        onSuccess()
      } catch (e) {
        toast.error(e instanceof Error ? e.message : 'Action failed')
      }
    })
  }

  return (
    <button
      type="button"
      onClick={handleApprove}
      disabled={isPending || !merchantUserId}
      className="w-full rounded-lg bg-emerald-600 px-4 py-2.5 font-semibold text-white hover:bg-emerald-700 transition-colors text-sm disabled:opacity-50"
    >
      {isPending ? 'Approving…' : 'Approve Merchant'}
    </button>
  )
}
