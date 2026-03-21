'use client'

import { useState, useTransition } from 'react'
import { toast } from 'sonner'
import { updateMerchantCommission } from '@/app/actions/admin'

interface Props {
  merchantId: string
  commissionFreeUntil: string | null
  commissionRate: number | null
  commissionStripeRate: number | null
  commissionStripeFlatFee: number | null
  commissionEffectiveFrom: string | null
  commissionEffectiveTo: string | null
  // 全局默认值（用于占位提示）
  defaultCommissionRate: number
  defaultStripeRate: number
  defaultStripeFlatFee: number
}

function toDateInput(iso: string | null) {
  if (!iso) return ''
  return iso.slice(0, 10)
}

function RateField({
  label,
  placeholder,
  value,
  onChange,
  suffix = '%',
  prefix,
  step = '0.1',
}: {
  label: string
  placeholder?: string
  value: string
  onChange: (v: string) => void
  suffix?: string
  prefix?: string
  step?: string
}) {
  return (
    <div>
      <label className="block text-xs font-medium text-gray-700 mb-1">{label}</label>
      <div className="flex items-center gap-1">
        {prefix && <span className="text-sm text-gray-400">{prefix}</span>}
        <input
          type="number"
          min={0}
          step={step}
          placeholder={placeholder}
          value={value}
          onChange={e => onChange(e.target.value)}
          className="w-24 px-2 py-1.5 text-sm border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500 placeholder:text-gray-300"
        />
        {suffix && <span className="text-sm text-gray-400">{suffix}</span>}
      </div>
    </div>
  )
}

export default function MerchantCommissionForm({
  merchantId,
  commissionFreeUntil,
  commissionRate,
  commissionStripeRate,
  commissionStripeFlatFee,
  commissionEffectiveFrom,
  commissionEffectiveTo,
  defaultCommissionRate,
  defaultStripeRate,
  defaultStripeFlatFee,
}: Props) {
  // 免费期
  const [freeUntil, setFreeUntil] = useState(toDateInput(commissionFreeUntil))

  // 费率（空字符串 = 使用全局默认）
  const toRateStr = (v: number | null) => (v === null ? '' : String(Math.round(v * 1000) / 10))
  const [rate,         setRate]         = useState(toRateStr(commissionRate))
  const [stripeRate,   setStripeRate]   = useState(toRateStr(commissionStripeRate))
  const [stripeFlatFee, setStripeFlatFee] = useState(
    commissionStripeFlatFee === null ? '' : String(Number(commissionStripeFlatFee).toFixed(2))
  )

  // 生效日期范围
  const [effFrom, setEffFrom] = useState(toDateInput(commissionEffectiveFrom))
  const [effTo,   setEffTo]   = useState(toDateInput(commissionEffectiveTo))

  const [isPending, startTransition] = useTransition()

  const isActive = commissionFreeUntil ? new Date() < new Date(commissionFreeUntil) : false

  function parseRate(s: string): number | null {
    if (!s.trim()) return null
    const v = parseFloat(s) / 100
    return isNaN(v) ? null : v
  }

  function handleSave() {
    startTransition(async () => {
      try {
        await updateMerchantCommission(merchantId, {
          commission_free_until:      freeUntil ? new Date(freeUntil).toISOString() : null,
          commission_rate:            parseRate(rate),
          commission_stripe_rate:     parseRate(stripeRate),
          commission_stripe_flat_fee: stripeFlatFee.trim() ? parseFloat(stripeFlatFee) : null,
          commission_effective_from:  effFrom || null,
          commission_effective_to:    effTo   || null,
        })
        toast.success('Commission config saved')
      } catch (e) {
        toast.error((e as Error).message)
      }
    })
  }

  function handleClearAll() {
    setFreeUntil(''); setRate('')
    setStripeRate(''); setStripeFlatFee(''); setEffFrom(''); setEffTo('')
    startTransition(async () => {
      try {
        await updateMerchantCommission(merchantId, {
          commission_free_until: null, commission_rate: null,
          commission_stripe_rate: null, commission_stripe_flat_fee: null,
          commission_effective_from: null, commission_effective_to: null,
        })
        toast.success('Reverted to global defaults')
      } catch (e) {
        toast.error((e as Error).message)
      }
    })
  }

  return (
    <div className="bg-white rounded-xl border border-gray-200 p-6 space-y-5">
      <div className="flex items-center justify-between">
        <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide">Commission Config</h2>
        <span className="text-xs text-gray-400">Leave blank to use global defaults</span>
      </div>

      {/* 免费期 */}
      <div>
        <div className="flex items-center gap-1.5 mb-2">
          <p className="text-xs font-semibold text-gray-400 uppercase tracking-wide">Free Period</p>
          <span className="group relative cursor-help">
            <span className="text-xs text-gray-400 border border-gray-300 rounded-full w-4 h-4 inline-flex items-center justify-center leading-none">?</span>
            <span className="pointer-events-none absolute left-6 top-0 z-10 w-64 rounded-lg bg-gray-800 px-3 py-2 text-xs text-white opacity-0 group-hover:opacity-100 transition-opacity shadow-lg">
              该日期当天仍免费（含当天）。平台抽成从次日凌晨起计算。<br/>
              例：Free Until = 03/31，则 03/31 全天免费，04/01 起按费率收取。
            </span>
          </span>
        </div>
        <div className="flex flex-wrap items-end gap-3">
          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">Commission Free Until (inclusive)</label>
            <input
              type="date"
              value={freeUntil}
              onChange={e => setFreeUntil(e.target.value)}
              className="px-2 py-1.5 text-sm border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
            />
          </div>
          <p className="text-xs text-gray-400 pb-2">
            Status:{' '}
            {commissionFreeUntil ? (
              isActive
                ? <span className="text-green-600 font-medium">Active — free until {new Date(commissionFreeUntil).toLocaleDateString()}, commission starts next day</span>
                : <span className="text-gray-400">Expired ({new Date(commissionFreeUntil).toLocaleDateString()})</span>
            ) : <span className="text-gray-400">No free period</span>}
          </p>
        </div>
      </div>

      {/* 生效日期范围 */}
      <div>
        <div className="flex items-center gap-1.5 mb-2">
          <p className="text-xs font-semibold text-gray-400 uppercase tracking-wide">Rate Effective Period</p>
          <span className="group relative cursor-help">
            <span className="text-xs text-gray-400 border border-gray-300 rounded-full w-4 h-4 inline-flex items-center justify-center leading-none">?</span>
            <span className="pointer-events-none absolute left-6 top-0 z-10 w-64 rounded-lg bg-gray-800 px-3 py-2 text-xs text-white opacity-0 group-hover:opacity-100 transition-opacity shadow-lg">
              记录这套费率的适用日期范围，仅作备注。<br/>
              实际计算以当前保存的费率为准，不会按日期自动切换。
            </span>
          </span>
        </div>
        <div className="flex flex-wrap gap-4">
          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">From</label>
            <input type="date" value={effFrom} onChange={e => setEffFrom(e.target.value)}
              className="px-2 py-1.5 text-sm border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500" />
          </div>
          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">To</label>
            <input type="date" value={effTo} onChange={e => setEffTo(e.target.value)}
              className="px-2 py-1.5 text-sm border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500" />
          </div>
        </div>
      </div>

      {/* 平台抽成费率 */}
      <div>
        <div className="flex items-center gap-1.5 mb-2">
          <p className="text-xs font-semibold text-gray-400 uppercase tracking-wide">Platform Commission Rate</p>
          <span className="group relative cursor-help">
            <span className="text-xs text-gray-400 border border-gray-300 rounded-full w-4 h-4 inline-flex items-center justify-center leading-none">?</span>
            <span className="pointer-events-none absolute left-6 top-0 z-10 w-72 rounded-lg bg-gray-800 px-3 py-2 text-xs text-white opacity-0 group-hover:opacity-100 transition-opacity shadow-lg">
              平台从商家实收中扣除的统一比例。免费期结束的次日起生效。<br/>
              留空则使用 Finance 页面的全局默认值。
            </span>
          </span>
        </div>
        <RateField
          label="Commission Rate (%)"
          placeholder={`default ${Math.round(defaultCommissionRate * 100)}%`}
          value={rate}
          onChange={setRate}
        />
      </div>

      {/* Stripe 手续费 */}
      <div>
        <div className="flex items-center gap-1.5 mb-2">
          <p className="text-xs font-semibold text-gray-400 uppercase tracking-wide">Stripe Processing Fee (per redeem)</p>
          <span className="group relative cursor-help">
            <span className="text-xs text-gray-400 border border-gray-300 rounded-full w-4 h-4 inline-flex items-center justify-center leading-none">?</span>
            <span className="pointer-events-none absolute left-6 top-0 z-10 w-72 rounded-lg bg-gray-800 px-3 py-2 text-xs text-white opacity-0 group-hover:opacity-100 transition-opacity shadow-lg">
              每笔成功核销时平台需支付给 Stripe 的刷卡成本。<br/>
              公式：金额 × Rate% + Flat Fee<br/>
              例：$20 订单 → $20 × 3% + $0.30 = $0.90<br/>
              此项目前为备注，不自动从结算中扣除。
            </span>
          </span>
        </div>
        <div className="flex flex-wrap gap-4">
          <RateField label="Rate" placeholder={`default ${Math.round(defaultStripeRate * 100)}%`}
            value={stripeRate} onChange={setStripeRate} />
          <RateField label="Flat Fee" placeholder={`default $${defaultStripeFlatFee.toFixed(2)}`}
            value={stripeFlatFee} onChange={setStripeFlatFee}
            suffix="" prefix="$" step="0.01" />
        </div>
      </div>

      <div className="flex items-center gap-3 pt-2 border-t border-gray-100">
        <button onClick={handleSave} disabled={isPending}
          className="px-5 py-2 text-sm font-semibold rounded-lg bg-blue-600 text-white hover:bg-blue-700 disabled:opacity-50 transition-colors">
          {isPending ? 'Saving…' : 'Save'}
        </button>
        <button onClick={handleClearAll} disabled={isPending}
          className="px-4 py-2 text-sm font-medium rounded-lg border border-gray-300 text-gray-600 hover:bg-gray-50 disabled:opacity-50 transition-colors">
          Reset to Global Defaults
        </button>
      </div>
    </div>
  )
}
