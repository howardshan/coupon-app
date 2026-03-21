'use client'

import { useState, useTransition } from 'react'
import { toast } from 'sonner'
import { updateCommissionConfig } from '@/app/actions/admin'

interface CommissionConfig {
  id: string
  free_months: number
  commission_rate: number
  stripe_processing_rate: number
  stripe_flat_fee: number
  effective_from: string | null
  effective_to: string | null
  updated_at: string | null
}

function RateInput({
  label,
  desc,
  value,
  onChange,
  suffix = '%',
  prefix,
  step = '0.1',
  width = 'w-24',
}: {
  label: string
  desc?: string
  value: string
  onChange: (v: string) => void
  suffix?: string
  prefix?: string
  step?: string
  width?: string
}) {
  return (
    <div>
      <label className="block text-xs font-medium text-gray-700 mb-0.5">{label}</label>
      {desc && <p className="text-[10px] text-gray-400 mb-1">{desc}</p>}
      <div className="flex items-center gap-1">
        {prefix && <span className="text-sm text-gray-500">{prefix}</span>}
        <input
          type="number"
          min={0}
          max={suffix === '%' ? 100 : undefined}
          step={step}
          value={value}
          onChange={e => onChange(e.target.value)}
          className={`${width} px-2 py-1.5 text-sm border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500`}
        />
        {suffix && <span className="text-sm text-gray-500">{suffix}</span>}
      </div>
    </div>
  )
}

export default function CommissionConfigForm({ config }: { config: CommissionConfig }) {
  // 平台统一抽成费率（百分比显示，存储时 /100）
  const [commissionRate, setCommissionRate] = useState(String(Math.round(Number(config.commission_rate) * 1000) / 10))
  // 生效日期范围
  const [effFrom, setEffFrom] = useState(config.effective_from ?? '')
  const [effTo,   setEffTo]   = useState(config.effective_to ?? '')
  // Stripe 手续费
  const [stripeRate,    setStripeRate]    = useState(String(Math.round(Number(config.stripe_processing_rate) * 1000) / 10))
  const [stripeFlatFee, setStripeFlatFee] = useState(String(Number(config.stripe_flat_fee).toFixed(2)))
  // 新商家免费期（月数）
  const [freeMonths, setFreeMonths] = useState(String(config.free_months))

  const [isPending, startTransition] = useTransition()

  function handleSave() {
    const commR   = parseFloat(commissionRate) / 100
    const stripeR = parseFloat(stripeRate) / 100
    const flatFee = parseFloat(stripeFlatFee)
    const freeM   = parseInt(freeMonths)

    if (isNaN(commR) || commR < 0 || commR > 1)
      return toast.error('Commission rate must be 0–100%')
    if (isNaN(stripeR) || stripeR < 0 || stripeR > 1)
      return toast.error('Stripe rate must be 0–100%')
    if (isNaN(flatFee) || flatFee < 0)
      return toast.error('Flat fee must be ≥ 0')
    if (isNaN(freeM) || freeM < 0 || freeM > 24)
      return toast.error('Free months must be 0–24')

    startTransition(async () => {
      try {
        await updateCommissionConfig({
          free_months: freeM,
          commission_rate: commR,
          stripe_processing_rate: stripeR,
          stripe_flat_fee: flatFee,
          effective_from: effFrom || null,
          effective_to:   effTo   || null,
        })
        toast.success('Commission config saved')
      } catch (e) {
        toast.error((e as Error).message)
      }
    })
  }

  return (
    <div className="bg-white rounded-xl border border-gray-200 p-6 mb-6 space-y-6">
      <div className="flex items-center justify-between">
        <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide">Default Commission Rates <span className="text-gray-400 font-normal normal-case text-xs">(applies when no merchant-specific rate is set)</span></h2>
        {config.updated_at && (
          <span className="text-xs text-gray-400">Last updated: {new Date(config.updated_at).toLocaleString()}</span>
        )}
      </div>

      {/* 生效日期范围 */}
      <div>
        <p className="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-3">Effective Period</p>
        <div className="flex flex-wrap gap-4">
          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">From</label>
            <input
              type="date"
              value={effFrom}
              onChange={e => setEffFrom(e.target.value)}
              className="px-2 py-1.5 text-sm border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
            />
          </div>
          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">To</label>
            <input
              type="date"
              value={effTo}
              onChange={e => setEffTo(e.target.value)}
              className="px-2 py-1.5 text-sm border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
            />
          </div>
          {(effFrom || effTo) && (
            <div className="flex items-end">
              <button
                onClick={() => { setEffFrom(''); setEffTo('') }}
                className="px-3 py-1.5 text-xs text-gray-500 border border-gray-200 rounded-lg hover:bg-gray-50"
              >
                Clear
              </button>
            </div>
          )}
        </div>
      </div>

      {/* 平台抽成费率 */}
      <div>
        <p className="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-3">Platform Commission Rate</p>
        <RateInput
          label="Platform Commission Rate (%)"
          value={commissionRate}
          onChange={setCommissionRate}
        />
      </div>

      {/* Stripe 刷卡手续费 */}
      <div>
        <p className="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-3">Stripe Processing Fee (per successful redeem)</p>
        <div className="flex flex-wrap gap-6">
          <RateInput
            label="Rate"
            value={stripeRate}
            onChange={setStripeRate}
          />
          <RateInput
            label="Flat Fee"
            value={stripeFlatFee}
            onChange={setStripeFlatFee}
            suffix=""
            prefix="$"
            step="0.01"
            width="w-20"
          />
          <div className="flex items-end">
            <p className="text-xs text-gray-400 pb-2">
              e.g. {stripeRate}% + ${stripeFlatFee} per redeem
            </p>
          </div>
        </div>
      </div>

      {/* 新商家免费期 */}
      <div>
        <p className="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-3">New Merchant Free Period</p>
        <RateInput
          label="Free Months"
          desc="No commission charged from approval date"
          value={freeMonths}
          onChange={setFreeMonths}
          suffix="months"
          step="1"
          width="w-16"
        />
      </div>

      <div className="pt-2 border-t border-gray-100">
        <button
          onClick={handleSave}
          disabled={isPending}
          className="px-5 py-2 text-sm font-semibold rounded-lg bg-blue-600 text-white hover:bg-blue-700 disabled:opacity-50 transition-colors"
        >
          {isPending ? 'Saving…' : 'Save Config'}
        </button>
      </div>
    </div>
  )
}
