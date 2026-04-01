import CopyTextButton from '@/components/copy-text-button'
import {
  type PaymentSplit,
  type RefundSummary,
  formatOrderMoney,
} from '@/lib/order-detail-display'

export type PriceLine = { label: string; amount: number }

type Props = {
  orderNumber: string
  createdAt: string
  paidAt: string | null
  priceLines: PriceLine[]
  serviceFeeLine: { title: string; total: number }
  totalAmount: number
  payment: PaymentSplit
  paymentIntentId: string | null
  refundSummary: RefundSummary | null
}

function Row({ label, value, valueClass = 'text-gray-900' }: { label: string; value: string; valueClass?: string }) {
  return (
    <div className="flex justify-between gap-3 text-sm">
      <span className="min-w-0 text-slate-600">{label}</span>
      <span className={`shrink-0 font-medium tabular-nums ${valueClass}`}>{value}</span>
    </div>
  )
}

/** 大卡片内的轻量子面板：浅底 + 细边框，便于扫读分区 */
function PricingSection({
  title,
  children,
  variant = 'default',
}: {
  title: string
  children: React.ReactNode
  variant?: 'default' | 'refunds' | 'stripe'
}) {
  const shell =
    'rounded-xl border border-slate-200/90 bg-slate-50/90 p-4 shadow-sm ring-1 ring-slate-900/[0.04] sm:p-5'
  const accent =
    variant === 'refunds'
      ? ' border-l-[3px] border-l-amber-400/95'
      : variant === 'stripe'
        ? ' bg-slate-100/80 ring-slate-900/[0.06]'
        : ''

  return (
    <section className={`${shell}${accent}`}>
      <h3 className="mb-3 text-[11px] font-bold uppercase tracking-[0.14em] text-slate-600">{title}</h3>
      {children}
    </section>
  )
}

/** 订单信息、价格明细、支付拆分、退款汇总（与用户端 Order Info 对齐）；子区块划分便于阅读 */
export default function OrderDetailPricingCard({
  orderNumber,
  createdAt,
  paidAt,
  priceLines,
  serviceFeeLine,
  totalAmount,
  payment,
  paymentIntentId,
  refundSummary,
}: Props) {
  const orderedStr = new Date(createdAt).toLocaleString('en-US', {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  })
  const paidStr = paidAt ? new Date(paidAt).toLocaleString('en-US') : null

  return (
    <div className="rounded-2xl border border-slate-200/90 bg-white p-5 shadow-sm ring-1 ring-slate-900/[0.04] sm:p-6">
      <h2 className="mb-4 text-sm font-bold uppercase tracking-wide text-slate-500">Order info &amp; pricing</h2>

      <div className="flex flex-col gap-4">
        <PricingSection title="Order details">
          <div className="space-y-3 text-sm">
            <div className="flex flex-wrap items-center gap-2">
              <span className="text-slate-500">Order number</span>
              <span className="font-mono font-semibold text-slate-900">{orderNumber}</span>
              <CopyTextButton text={orderNumber} label="Copy" copiedLabel="Copied" />
            </div>
            <div>
              <span className="text-slate-500">Ordered</span>
              <p className="mt-0.5 font-medium text-slate-900">{orderedStr}</p>
            </div>
            {paidStr && (
              <div>
                <span className="text-slate-500">Paid</span>
                <p className="mt-0.5 font-medium text-slate-900">{paidStr}</p>
              </div>
            )}
            <div>
              <span className="text-slate-500">Payment method</span>
              <p className="mt-0.5 font-medium text-slate-900">{payment.displayMethod}</p>
            </div>
          </div>
        </PricingSection>

        <PricingSection title="Price breakdown">
          <div className="space-y-2.5">
            {priceLines.map((line) => (
              <Row key={line.label} label={line.label} value={formatOrderMoney(line.amount)} />
            ))}
            {serviceFeeLine.total > 0 && (
              <Row label={serviceFeeLine.title} value={formatOrderMoney(serviceFeeLine.total)} />
            )}
            <div className="mt-3 border-t border-slate-200/80 pt-3">
              <Row label="Total" value={formatOrderMoney(totalAmount)} valueClass="text-base font-semibold text-slate-900" />
            </div>
          </div>
        </PricingSection>

        <PricingSection title="Payment breakdown">
          <div className="space-y-2.5">
            {payment.storeCreditUsed > 0 && (
              <Row
                label="Store credit"
                value={formatOrderMoney(payment.storeCreditUsed)}
                valueClass="font-semibold text-emerald-700"
              />
            )}
            {payment.cardAmount > 0 && (
              <Row label="Credit card" value={formatOrderMoney(payment.cardAmount)} />
            )}
            {payment.fullyStoreCredit && payment.storeCreditUsed > 0 && (
              <p className="text-xs italic text-emerald-700">Fully paid by store credit</p>
            )}
          </div>
        </PricingSection>

        {refundSummary && (
          <PricingSection title="Refunds" variant="refunds">
            <div className="space-y-2.5">
              {refundSummary.storeCreditCount > 0 && (
                <Row
                  label={`To store credit (${refundSummary.storeCreditCount} voucher${refundSummary.storeCreditCount > 1 ? 's' : ''})`}
                  value={formatOrderMoney(refundSummary.storeCreditTotal)}
                  valueClass="font-semibold text-emerald-700"
                />
              )}
              {refundSummary.originalCount > 0 && (
                <Row
                  label={`To original payment (${refundSummary.originalCount})`}
                  value={formatOrderMoney(refundSummary.originalTotal)}
                />
              )}
              {refundSummary.pendingCount > 0 && (
                <Row
                  label={`Refund processing (${refundSummary.pendingCount})`}
                  value={formatOrderMoney(refundSummary.pendingTotal)}
                  valueClass="font-semibold text-amber-700"
                />
              )}
              <div className="mt-3 border-t border-slate-200/80 pt-3">
                <Row
                  label="Total refunded"
                  value={formatOrderMoney(refundSummary.totalRefund)}
                  valueClass="text-base font-semibold text-red-600"
                />
              </div>
            </div>
          </PricingSection>
        )}

        <PricingSection title="Stripe" variant="stripe">
          <p className="break-all font-mono text-xs leading-relaxed text-slate-800">{paymentIntentId ?? '—'}</p>
          <p className="mt-2 text-xs leading-snug text-slate-500">Use Payment Intent ID in Stripe Dashboard.</p>
        </PricingSection>
      </div>
    </div>
  )
}
