'use client'

import { useCallback, useState } from 'react'
import { useRouter, useSearchParams } from 'next/navigation'
import type {
  MerchantItem,
  DealItem,
  RefundDisputeItem,
  AfterSalesItem,
  UnifiedApprovalRow,
} from '@/app/(dashboard)/approvals/page'
import MerchantDrawer from '@/components/approvals/merchant-drawer'
import DealDrawer from '@/components/approvals/deal-drawer'
import RefundDisputeDrawer from '@/components/approvals/refund-dispute-drawer'
import AfterSalesDrawer from '@/components/approvals/after-sales-drawer'
import { batchApproveDeal, batchRejectDeal } from '@/app/actions/admin'

// ─── 类型 ────────────────────────────────────────────────────────────────
type Counts = {
  merchants: number
  deals: number
  refundDisputes: number
  afterSales: number
}

type Props = {
  tab: string
  page: number
  perPage: number
  counts: Counts
  merchants: MerchantItem[]
  merchantsTotal: number
  deals: DealItem[]
  dealsTotal: number
  refundDisputes: RefundDisputeItem[]
  refundDisputesTotal: number
  afterSales: AfterSalesItem[]
  afterSalesTotal: number
  /** All Tab：服务端已按全局时间排序的一页数据 */
  unifiedAllRows: UnifiedApprovalRow[]
}

// ─── 常量 ────────────────────────────────────────────────────────────────
const TABS = [
  { key: 'all', label: 'All' },
  { key: 'merchants', label: 'Merchant Applications' },
  { key: 'deals', label: 'Deal Reviews' },
  { key: 'refund-disputes', label: 'Refund Disputes' },
  { key: 'after-sales', label: 'After-Sales' },
] as const

// 超过 24h 认为超时
const OVERDUE_MS = 24 * 60 * 60 * 1000

function isOverdue(createdAt: string) {
  return Date.now() - new Date(createdAt).getTime() > OVERDUE_MS
}

function relativeTime(iso: string) {
  const diff = Date.now() - new Date(iso).getTime()
  const mins = Math.floor(diff / 60000)
  const hours = Math.floor(diff / 3600000)
  const days = Math.floor(diff / 86400000)
  if (days > 0) return `${days}d ago`
  if (hours > 0) return `${hours}h ago`
  return `${mins}m ago`
}

type UnifiedRow = UnifiedApprovalRow

const TYPE_COLORS: Record<string, string> = {
  merchant: 'bg-purple-100 text-purple-700',
  deal: 'bg-blue-100 text-blue-700',
  refund: 'bg-orange-100 text-orange-700',
  'after-sales': 'bg-teal-100 text-teal-700',
}
const TYPE_LABELS: Record<string, string> = {
  merchant: 'Merchant',
  deal: 'Deal',
  refund: 'Refund Dispute',
  'after-sales': 'After-Sales',
}

// ─── Component ───────────────────────────────────────────────────────────
export default function ApprovalsPageClient({
  tab,
  page,
  perPage,
  counts,
  merchants,
  merchantsTotal,
  deals,
  dealsTotal,
  refundDisputes,
  refundDisputesTotal,
  afterSales,
  afterSalesTotal,
  unifiedAllRows,
}: Props) {
  const router = useRouter()
  const searchParams = useSearchParams()

  // 抽屉状态
  const [drawerRow, setDrawerRow] = useState<UnifiedRow | null>(null)

  // Deal 批量选择状态
  const [selectedDealIds, setSelectedDealIds] = useState<Set<string>>(new Set())
  const [batchModal, setBatchModal] = useState<null | 'approve' | 'reject'>(null)
  const [batchReason, setBatchReason] = useState('')
  const [batchLoading, setBatchLoading] = useState(false)
  const [batchResult, setBatchResult] = useState<string | null>(null)

  // 导航辅助
  const navigate = useCallback((updates: Record<string, string | undefined>) => {
    const next = new URLSearchParams(searchParams)
    Object.entries(updates).forEach(([k, v]) => {
      if (v === undefined) next.delete(k)
      else next.set(k, v)
    })
    router.push(`/approvals?${next.toString()}`)
  }, [router, searchParams])

  const onTabChange = (key: string) => {
    setSelectedDealIds(new Set())
    navigate({ tab: key === 'all' ? undefined : key, page: undefined })
  }

  const onPageChange = (p: number) => navigate({ page: p === 1 ? undefined : String(p) })

  // All tab：使用服务端 RPC 全局时间序分页结果（不再客户端四类各取一页再合并）
  const allRows: UnifiedRow[] = tab === 'all' ? unifiedAllRows : []

  // 当前 tab 的总条数（用于分页）
  const totalMap: Record<string, number> = {
    all: counts.merchants + counts.deals + counts.refundDisputes + counts.afterSales,
    merchants: merchantsTotal,
    deals: dealsTotal,
    'refund-disputes': refundDisputesTotal,
    'after-sales': afterSalesTotal,
  }
  const currentTotal = totalMap[tab] ?? 0
  const totalPages = Math.max(1, Math.ceil(currentTotal / perPage))

  // Deal 全选
  const allDealIds = deals.map(d => d.id)
  const allSelected = allDealIds.length > 0 && allDealIds.every(id => selectedDealIds.has(id))
  const toggleSelectAll = () => {
    if (allSelected) {
      setSelectedDealIds(new Set())
    } else {
      setSelectedDealIds(new Set(allDealIds))
    }
  }
  const toggleDeal = (id: string) => {
    setSelectedDealIds(prev => {
      const next = new Set(prev)
      next.has(id) ? next.delete(id) : next.add(id)
      return next
    })
  }

  // 批量审批
  async function submitBatch(action: 'approve' | 'reject') {
    setBatchLoading(true)
    setBatchResult(null)
    try {
      const ids = Array.from(selectedDealIds)
      let result: { success: string[]; failed: string[] }
      if (action === 'approve') {
        result = await batchApproveDeal(ids)
      } else {
        result = await batchRejectDeal(ids, batchReason)
      }
      setBatchResult(`${result.success.length} succeeded, ${result.failed.length} failed`)
      setSelectedDealIds(new Set())
      setBatchModal(null)
      setBatchReason('')
      router.refresh()
    } catch (err) {
      setBatchResult((err as Error).message)
    } finally {
      setBatchLoading(false)
    }
  }

  return (
    <div className="space-y-6">
      {/* ── 页头 ── */}
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Approvals</h1>
        <p className="text-sm text-gray-500 mt-1">
          {counts.merchants + counts.deals + counts.refundDisputes + counts.afterSales} pending
        </p>
      </div>

      {/* ── Tabs（横向可滚动 + 禁止收缩，避免角标被 flex 挤没） ── */}
      <div className="flex flex-nowrap gap-1 overflow-x-auto border-b border-gray-200">
        {TABS.map(t => {
          const countMap: Record<string, number> = {
            all: counts.merchants + counts.deals + counts.refundDisputes + counts.afterSales,
            merchants: counts.merchants,
            deals: counts.deals,
            'refund-disputes': counts.refundDisputes,
            'after-sales': counts.afterSales,
          }
          const cnt = countMap[t.key] ?? 0
          const active = tab === t.key
          return (
            <button
              key={t.key}
              type="button"
              onClick={() => onTabChange(t.key)}
              className={`shrink-0 whitespace-nowrap px-4 py-2.5 text-sm font-medium border-b-2 transition-colors flex items-center gap-2 -mb-px ${
                active
                  ? 'border-blue-600 text-blue-600'
                  : 'border-transparent text-gray-500 hover:text-gray-700'
              }`}
            >
              {t.label}
              {cnt > 0 && (
                <span
                  className={`shrink-0 min-w-[20px] h-5 px-1.5 rounded-full text-xs font-bold flex items-center justify-center ${
                    active ? 'bg-blue-600 text-white' : 'bg-red-500 text-white'
                  }`}
                >
                  {cnt > 99 ? '99+' : cnt}
                </span>
              )}
            </button>
          )
        })}
      </div>

      {/* ── Deal 批量操作栏 ── */}
      {tab === 'deals' && (
        <div className="flex items-center gap-3">
          <label className="flex items-center gap-2 text-sm text-gray-600 cursor-pointer">
            <input
              type="checkbox"
              checked={allSelected}
              onChange={toggleSelectAll}
              className="rounded border-gray-300"
            />
            Select All
          </label>
          {selectedDealIds.size > 0 && (
            <>
              <span className="text-sm text-gray-500">{selectedDealIds.size} selected</span>
              <button
                type="button"
                onClick={() => setBatchModal('approve')}
                className="px-3 py-1.5 rounded-lg bg-emerald-600 text-white text-sm font-medium hover:bg-emerald-700"
              >
                Batch Approve
              </button>
              <button
                type="button"
                onClick={() => setBatchModal('reject')}
                className="px-3 py-1.5 rounded-lg border border-rose-400 text-rose-700 text-sm font-medium hover:bg-rose-50"
              >
                Batch Reject
              </button>
            </>
          )}
          {batchResult && (
            <span className="text-sm text-gray-600">{batchResult}</span>
          )}
        </div>
      )}

      {/* ── 列表 ── */}
      <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
        <table className="w-full text-sm">
          <thead className="bg-gray-50 border-b border-gray-200 text-gray-600">
            <tr>
              {tab === 'deals' && <th className="px-4 py-3 w-8" />}
              {tab === 'all' && <th className="px-4 py-3 text-left font-medium">Type</th>}
              <th className="px-4 py-3 text-left font-medium">Summary</th>
              <th className="px-4 py-3 text-left font-medium">Submitter</th>
              <th className="px-4 py-3 text-left font-medium">Submitted</th>
              <th className="px-4 py-3 w-24" />
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100">
            {tab === 'all' && allRows.map(row => (
              <UnifiedTableRow
                key={`${row.kind}-${row.data.id}`}
                row={row}
                showType
                showCheckbox={false}
                checked={false}
                onToggle={() => {}}
                onReview={() => setDrawerRow(row)}
              />
            ))}
            {tab === 'merchants' && merchants.map(m => {
              const row: UnifiedRow = { kind: 'merchant', data: m }
              return (
                <UnifiedTableRow
                  key={m.id} row={row} showType={false} showCheckbox={false}
                  checked={false} onToggle={() => {}} onReview={() => setDrawerRow(row)}
                />
              )
            })}
            {tab === 'deals' && deals.map(d => {
              const row: UnifiedRow = { kind: 'deal', data: d }
              return (
                <UnifiedTableRow
                  key={d.id} row={row} showType={false} showCheckbox
                  checked={selectedDealIds.has(d.id)}
                  onToggle={() => toggleDeal(d.id)}
                  onReview={() => setDrawerRow(row)}
                />
              )
            })}
            {tab === 'refund-disputes' && refundDisputes.map(r => {
              const row: UnifiedRow = { kind: 'refund', data: r }
              return (
                <UnifiedTableRow
                  key={r.id} row={row} showType={false} showCheckbox={false}
                  checked={false} onToggle={() => {}} onReview={() => setDrawerRow(row)}
                />
              )
            })}
            {tab === 'after-sales' && afterSales.map(a => {
              const row: UnifiedRow = { kind: 'after-sales', data: a }
              return (
                <UnifiedTableRow
                  key={a.id} row={row} showType={false} showCheckbox={false}
                  checked={false} onToggle={() => {}} onReview={() => setDrawerRow(row)}
                />
              )
            })}
          </tbody>
        </table>

        {/* 空状态 */}
        {currentTotal === 0 && (
          <div className="py-12 text-center text-gray-400">
            No pending approvals in this category.
          </div>
        )}
      </div>

      {/* ── 分页（含 All tab 真实全局分页） ── */}
      {totalPages > 1 && (
        <div className="flex items-center justify-center gap-4">
          <button
            type="button"
            onClick={() => onPageChange(Math.max(1, page - 1))}
            disabled={page <= 1}
            className="px-3 py-1.5 rounded-lg border border-gray-300 text-sm disabled:opacity-40"
          >
            Previous
          </button>
          <span className="text-sm text-gray-600">Page {page} of {totalPages}</span>
          <button
            type="button"
            onClick={() => onPageChange(Math.min(totalPages, page + 1))}
            disabled={page >= totalPages}
            className="px-3 py-1.5 rounded-lg border border-gray-300 text-sm disabled:opacity-40"
          >
            Next
          </button>
        </div>
      )}

      {/* ── 详情抽屉 ── */}
      {drawerRow?.kind === 'merchant' && (
        <MerchantDrawer
          merchant={drawerRow.data}
          onClose={() => setDrawerRow(null)}
        />
      )}
      {drawerRow?.kind === 'deal' && (
        <DealDrawer
          deal={drawerRow.data}
          onClose={() => setDrawerRow(null)}
        />
      )}
      {drawerRow?.kind === 'refund' && (
        <RefundDisputeDrawer
          dispute={drawerRow.data}
          onClose={() => setDrawerRow(null)}
        />
      )}
      {drawerRow?.kind === 'after-sales' && (
        <AfterSalesDrawer
          item={drawerRow.data}
          onClose={() => setDrawerRow(null)}
        />
      )}

      {/* ── 批量审批弹窗 ── */}
      {batchModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/30 p-4">
          <div className="w-full max-w-md rounded-2xl bg-white p-6 shadow-xl">
            <h2 className="text-lg font-semibold text-gray-900">
              {batchModal === 'approve'
                ? `Approve ${selectedDealIds.size} deal${selectedDealIds.size > 1 ? 's' : ''}?`
                : `Reject ${selectedDealIds.size} deal${selectedDealIds.size > 1 ? 's' : ''}`}
            </h2>
            {batchModal === 'approve' && (
              <p className="mt-2 text-sm text-gray-600">
                All selected deals will be published immediately.
              </p>
            )}
            {batchModal === 'reject' && (
              <>
                <p className="mt-2 text-sm text-gray-600">
                  All selected deals will use the same rejection reason.
                </p>
                <textarea
                  value={batchReason}
                  onChange={e => setBatchReason(e.target.value)}
                  rows={3}
                  placeholder="Rejection reason (min 10 characters)"
                  className="mt-3 w-full rounded-lg border border-gray-300 px-3 py-2 text-sm"
                />
              </>
            )}
            <div className="mt-5 flex justify-end gap-3">
              <button
                type="button"
                onClick={() => { setBatchModal(null); setBatchReason('') }}
                className="px-4 py-2 rounded-lg border border-gray-300 text-sm"
              >
                Cancel
              </button>
              <button
                type="button"
                disabled={
                  batchLoading ||
                  (batchModal === 'reject' && batchReason.trim().length < 10)
                }
                onClick={() => submitBatch(batchModal)}
                className={`px-4 py-2 rounded-lg text-sm font-semibold text-white disabled:opacity-50 ${
                  batchModal === 'approve' ? 'bg-emerald-600 hover:bg-emerald-700' : 'bg-rose-600 hover:bg-rose-700'
                }`}
              >
                {batchLoading ? 'Processing…' : 'Confirm'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}

// ─── 统一行组件 ──────────────────────────────────────────────────────────
function UnifiedTableRow({
  row,
  showType,
  showCheckbox,
  checked,
  onToggle,
  onReview,
}: {
  row: UnifiedRow
  showType: boolean
  showCheckbox: boolean
  checked: boolean
  onToggle: () => void
  onReview: () => void
}) {
  const overdue = isOverdue(row.data.createdAt)

  let summary = ''
  let submitter = ''
  if (row.kind === 'merchant') {
    summary = row.data.name
    submitter = row.data.contactName ?? row.data.contactEmail ?? '—'
  } else if (row.kind === 'deal') {
    summary = row.data.title
    submitter = row.data.merchantName
  } else if (row.kind === 'refund') {
    summary = `$${row.data.refundAmount.toFixed(2)} — ${row.data.merchantName}`
    submitter = row.data.userNameMasked
  } else {
    summary = row.data.reasonCode.replaceAll('_', ' ')
    submitter = row.data.userFullName
  }

  return (
    <tr className={`hover:bg-gray-50 ${overdue ? 'bg-red-50/40' : ''}`}>
      {showCheckbox && (
        <td className="px-4 py-3">
          <input
            type="checkbox"
            checked={checked}
            onChange={onToggle}
            className="rounded border-gray-300"
            onClick={e => e.stopPropagation()}
          />
        </td>
      )}
      {showType && (
        <td className="px-4 py-3">
          <span className={`inline-flex px-2 py-0.5 rounded-full text-xs font-semibold ${TYPE_COLORS[row.kind]}`}>
            {TYPE_LABELS[row.kind]}
          </span>
        </td>
      )}
      <td className="px-4 py-3 font-medium text-gray-900 max-w-xs truncate">
        {summary}
      </td>
      <td className="px-4 py-3 text-gray-600">{submitter}</td>
      <td className="px-4 py-3 text-gray-500 whitespace-nowrap">
        <span title={new Date(row.data.createdAt).toLocaleString()}>
          {relativeTime(row.data.createdAt)}
        </span>
        {overdue && <span className="ml-1" title="Overdue (>24h)">⚠️</span>}
      </td>
      <td className="px-4 py-3 text-right">
        <button
          type="button"
          onClick={onReview}
          className="inline-flex items-center px-3 py-1.5 text-sm font-medium rounded-lg border border-blue-200 bg-blue-50 text-blue-700 hover:bg-blue-100 transition-colors"
        >
          Review
        </button>
      </td>
    </tr>
  )
}
