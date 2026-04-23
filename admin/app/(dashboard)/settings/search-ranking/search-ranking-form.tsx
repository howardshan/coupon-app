'use client'

import { useState, useTransition } from 'react'
import { toast } from 'sonner'
import { updateRankingConfig, type RankingConfig } from '@/app/actions/search-ranking'

interface Props {
  config: RankingConfig
}

interface Factor {
  key: keyof Omit<RankingConfig, 'updated_at'>
  label: string
  description: string
  color: string
  bgColor: string
  borderColor: string
  textColor: string
  badgeColor: string
  positive: boolean
}

const FACTORS: Factor[] = [
  {
    key: 'distance_weight',
    label: 'Distance',
    description: 'Closer merchants score higher',
    color: 'bg-blue-500',
    bgColor: 'bg-blue-50',
    borderColor: 'border-blue-200',
    textColor: 'text-blue-700',
    badgeColor: 'text-blue-500',
    positive: true,
  },
  {
    key: 'rating_weight',
    label: 'Rating',
    description: 'Higher-rated merchants score higher',
    color: 'bg-yellow-400',
    bgColor: 'bg-yellow-50',
    borderColor: 'border-yellow-200',
    textColor: 'text-yellow-700',
    badgeColor: 'text-yellow-500',
    positive: true,
  },
  {
    key: 'click_weight',
    label: 'Click-through',
    description: 'More viewed merchants score higher',
    color: 'bg-purple-500',
    bgColor: 'bg-purple-50',
    borderColor: 'border-purple-200',
    textColor: 'text-purple-700',
    badgeColor: 'text-purple-500',
    positive: true,
  },
  {
    key: 'order_weight',
    label: 'Orders',
    description: 'More orders = stronger social proof',
    color: 'bg-green-500',
    bgColor: 'bg-green-50',
    borderColor: 'border-green-200',
    textColor: 'text-green-700',
    badgeColor: 'text-green-500',
    positive: true,
  },
  {
    key: 'refund_weight',
    label: 'Refund Rate',
    description: 'Lower refund rate scores higher (negative signal)',
    color: 'bg-red-400',
    bgColor: 'bg-red-50',
    borderColor: 'border-red-200',
    textColor: 'text-red-700',
    badgeColor: 'text-red-500',
    positive: false,
  },
]

export default function SearchRankingForm({ config }: Props) {
  const [weights, setWeights] = useState<Record<string, number>>({
    distance_weight: Number(config.distance_weight),
    rating_weight: Number(config.rating_weight),
    click_weight: Number(config.click_weight),
    order_weight: Number(config.order_weight),
    refund_weight: Number(config.refund_weight),
  })
  const [isPending, startTransition] = useTransition()

  const total = Object.values(weights).reduce((s, v) => s + v, 0)

  function effectivePct(key: string) {
    if (total === 0) return 0
    return Math.round((weights[key] / total) * 100)
  }

  function handleChange(key: string, value: number) {
    setWeights(prev => ({ ...prev, [key]: Math.max(0, Math.min(100, value)) }))
  }

  function handleSave() {
    startTransition(async () => {
      const result = await updateRankingConfig({
        distance_weight: weights.distance_weight,
        rating_weight: weights.rating_weight,
        click_weight: weights.click_weight,
        order_weight: weights.order_weight,
        refund_weight: weights.refund_weight,
      })
      if (result.success) {
        toast.success('Ranking weights saved')
      } else {
        toast.error(result.error ?? 'Failed to save weights')
      }
    })
  }

  const lastUpdated = config.updated_at
    ? new Date(config.updated_at).toLocaleString()
    : '—'

  return (
    <div className="max-w-2xl space-y-8">
      {/* 算法说明 */}
      <div className="rounded-lg border border-gray-200 bg-white p-6 shadow-sm space-y-5">
        <div>
          <h2 className="text-base font-semibold text-gray-900">How scoring works</h2>
          <p className="mt-1 text-sm text-gray-500">
            Each merchant gets a score between 0 and 1 per factor. Scores are multiplied
            by their normalized weights and summed — the highest total score ranks first.
            Weights are relative; you don't need them to sum to any particular number.
          </p>
        </div>

        <div className="rounded-md bg-gray-50 px-4 py-3 font-mono text-xs text-gray-600 leading-relaxed space-y-1">
          <div>distance_score = 1 − (km / 20mi radius)</div>
          <div>rating_score&nbsp;&nbsp; = avg_rating / 5</div>
          <div>click_score&nbsp;&nbsp;&nbsp; = views / (views + 200)&nbsp;&nbsp;<span className="text-gray-400">soft cap</span></div>
          <div>order_score&nbsp;&nbsp;&nbsp; = sold / (sold + 50)&nbsp;&nbsp;&nbsp;&nbsp;<span className="text-gray-400">soft cap</span></div>
          <div>refund_score&nbsp;&nbsp; = 1 − refund_rate&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<span className="text-gray-400">inverted</span></div>
          <div className="pt-1 text-blue-700 font-semibold">
            final = Σ (normalized_weight × factor_score)
          </div>
        </div>

        {/* 归一化后的比例条 */}
        <div>
          <div className="flex items-center justify-between text-xs text-gray-500 mb-1.5">
            <span>Effective weight distribution</span>
            <span className="text-gray-400">normalized to 100%</span>
          </div>
          <div className="flex h-3 w-full overflow-hidden rounded-full">
            {FACTORS.map(f => (
              <div
                key={f.key}
                className={`${f.color} transition-all duration-200`}
                style={{ width: `${effectivePct(f.key)}%` }}
              />
            ))}
          </div>
          <div className="mt-2 flex flex-wrap gap-3">
            {FACTORS.map(f => (
              <div key={f.key} className="flex items-center gap-1.5 text-xs text-gray-600">
                <span className={`h-2.5 w-2.5 rounded-full ${f.color}`} />
                <span>{f.label} {effectivePct(f.key)}%</span>
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* 5 个权重滑块 */}
      <div className="space-y-3">
        {FACTORS.map(f => (
          <div
            key={f.key}
            className={`rounded-lg border ${f.borderColor} ${f.bgColor} p-4`}
          >
            <div className="flex items-center justify-between mb-2">
              <div className="flex items-center gap-2">
                <span className={`h-3 w-3 rounded-full ${f.color}`} />
                <span className={`text-sm font-semibold ${f.textColor}`}>{f.label}</span>
                {!f.positive && (
                  <span className="rounded-full bg-red-100 px-2 py-0.5 text-xs text-red-600">
                    negative signal
                  </span>
                )}
              </div>
              <div className="flex items-center gap-2">
                <span className={`text-xs ${f.badgeColor}`}>
                  {effectivePct(f.key)}% effective
                </span>
                <input
                  type="number"
                  min={0}
                  max={100}
                  value={weights[f.key]}
                  onChange={e => handleChange(f.key, Number(e.target.value))}
                  className={`w-16 rounded border border-gray-300 bg-white px-2 py-1 text-right text-sm ${f.textColor} font-semibold`}
                />
              </div>
            </div>
            <input
              type="range"
              min={0}
              max={100}
              value={weights[f.key]}
              onChange={e => handleChange(f.key, Number(e.target.value))}
              className="w-full"
              style={{ accentColor: f.color.replace('bg-', '') }}
            />
            <p className="mt-1 text-xs text-gray-500">{f.description}</p>
          </div>
        ))}
      </div>

      {/* 保存 */}
      <div className="flex items-center justify-between">
        <p className="text-xs text-gray-400">Last updated: {lastUpdated}</p>
        <button
          type="button"
          onClick={handleSave}
          disabled={isPending || total === 0}
          className="rounded-lg bg-blue-600 px-5 py-2.5 text-sm font-semibold text-white shadow-sm hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
        >
          {isPending ? 'Saving…' : 'Save Changes'}
        </button>
      </div>
    </div>
  )
}
