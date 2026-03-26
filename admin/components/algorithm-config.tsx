'use client'

import { useState, useTransition } from 'react'
import { parseAlgorithm, activateConfig, restoreConfig } from '@/app/actions/recommendation'
import { useRouter } from 'next/navigation'

// 权重配置类型
interface WeightConfig {
  relevance: number
  distance: number
  popularity: number
  quality: number
  freshness: number
  time_slot: number
}

// 配置记录类型
interface ConfigRecord {
  id: string
  version: number
  description: string
  weights: WeightConfig
  is_active: boolean
  created_at: string
}

// 解析结果类型（Edge Function 返回）
interface ParseResult {
  config_id: string
  weights: WeightConfig
  description: string
}

// 权重标签映射
const WEIGHT_LABELS: Record<keyof WeightConfig, string> = {
  relevance: 'Relevance',
  distance: 'Distance',
  popularity: 'Popularity',
  quality: 'Quality',
  freshness: 'Freshness',
  time_slot: 'Time Slot',
}

// 权重颜色映射
const WEIGHT_COLORS: Record<keyof WeightConfig, string> = {
  relevance: 'bg-blue-500',
  distance: 'bg-green-500',
  popularity: 'bg-purple-500',
  quality: 'bg-yellow-500',
  freshness: 'bg-pink-500',
  time_slot: 'bg-orange-500',
}

interface AlgorithmConfigProps {
  initialConfigs: ConfigRecord[]
}

export default function AlgorithmConfig({ initialConfigs }: AlgorithmConfigProps) {
  const router = useRouter()
  const [isPending, startTransition] = useTransition()

  // 输入状态
  const [description, setDescription] = useState('')

  // 解析结果预览
  const [preview, setPreview] = useState<ParseResult | null>(null)

  // 操作状态
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [success, setSuccess] = useState<string | null>(null)

  // 生成配置：调用 parseAlgorithm
  async function handleGenerate() {
    if (!description.trim()) return

    setLoading(true)
    setError(null)
    setSuccess(null)
    setPreview(null)

    const result = await parseAlgorithm(description.trim())

    if (result.error) {
      setError(result.error)
    } else {
      setPreview(result.data as ParseResult)
    }

    setLoading(false)
  }

  // 激活配置
  async function handleActivate() {
    if (!preview?.config_id) return

    setLoading(true)
    setError(null)

    const result = await activateConfig(preview.config_id)

    if (result.error) {
      setError(result.error)
    } else {
      setSuccess('Configuration activated successfully!')
      setPreview(null)
      setDescription('')
      // 刷新页面获取最新列表
      startTransition(() => router.refresh())
    }

    setLoading(false)
  }

  // 丢弃预览
  function handleDiscard() {
    setPreview(null)
    setError(null)
    setSuccess(null)
  }

  // 恢复历史配置
  async function handleRestore(configId: string) {
    setLoading(true)
    setError(null)
    setSuccess(null)

    const result = await restoreConfig(configId)

    if (result.error) {
      setError(result.error)
    } else {
      setSuccess('Configuration restored and activated!')
      startTransition(() => router.refresh())
    }

    setLoading(false)
  }

  return (
    <div className="space-y-6">
      {/* 错误提示 */}
      {error && (
        <div className="bg-red-50 border border-red-200 rounded-xl p-4 text-red-800 text-sm">
          {error}
        </div>
      )}

      {/* 成功提示 */}
      {success && (
        <div className="bg-green-50 border border-green-200 rounded-xl p-4 text-green-800 text-sm">
          {success}
        </div>
      )}

      {/* 输入区域 */}
      <div className="bg-white border border-gray-200 rounded-xl p-6">
        <h2 className="text-lg font-semibold text-gray-900 mb-3">New Configuration</h2>
        <p className="text-sm text-gray-500 mb-4">
          Describe your recommendation algorithm in natural language. The system will generate weight configurations automatically.
        </p>

        <textarea
          value={description}
          onChange={(e) => setDescription(e.target.value)}
          placeholder="e.g., Prioritize nearby deals with high ratings, give moderate weight to popularity, and slightly boost new deals..."
          className="w-full h-32 px-4 py-3 border border-gray-300 rounded-lg text-sm text-gray-900 placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent resize-none"
          disabled={loading}
        />

        <div className="mt-3 flex gap-3">
          <button
            onClick={handleGenerate}
            disabled={loading || !description.trim()}
            className="px-5 py-2.5 bg-blue-600 text-white text-sm font-medium rounded-lg hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
          >
            {loading && !preview ? 'Generating...' : 'Generate Config'}
          </button>
        </div>
      </div>

      {/* 权重预览 */}
      {preview && (
        <div className="bg-white border border-gray-200 rounded-xl p-6">
          <h2 className="text-lg font-semibold text-gray-900 mb-4">Preview Weights</h2>

          <div className="space-y-3 mb-6">
            {(Object.keys(WEIGHT_LABELS) as Array<keyof WeightConfig>).map((key) => {
              const value = preview.weights[key] ?? 0
              // 百分比：假设权重范围 0~1
              const pct = Math.round(value * 100)
              return (
                <div key={key}>
                  <div className="flex justify-between text-sm mb-1">
                    <span className="font-medium text-gray-700">{WEIGHT_LABELS[key]}</span>
                    <span className="text-gray-500">{pct}%</span>
                  </div>
                  <div className="w-full h-3 bg-gray-100 rounded-full overflow-hidden">
                    <div
                      className={`h-full rounded-full transition-all ${WEIGHT_COLORS[key]}`}
                      style={{ width: `${pct}%` }}
                    />
                  </div>
                </div>
              )
            })}
          </div>

          <div className="flex gap-3">
            <button
              onClick={handleActivate}
              disabled={loading}
              className="px-5 py-2.5 bg-green-600 text-white text-sm font-medium rounded-lg hover:bg-green-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
            >
              {loading ? 'Activating...' : 'Activate'}
            </button>
            <button
              onClick={handleDiscard}
              disabled={loading}
              className="px-5 py-2.5 bg-gray-200 text-gray-700 text-sm font-medium rounded-lg hover:bg-gray-300 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
            >
              Discard
            </button>
          </div>
        </div>
      )}

      {/* 配置历史 */}
      <div className="bg-white border border-gray-200 rounded-xl p-6">
        <h2 className="text-lg font-semibold text-gray-900 mb-4">Configuration History</h2>

        {initialConfigs.length === 0 ? (
          <p className="text-sm text-gray-500">No configurations yet. Generate your first one above.</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-gray-200">
                  <th className="text-left py-3 px-3 font-medium text-gray-500">Version</th>
                  <th className="text-left py-3 px-3 font-medium text-gray-500">Description</th>
                  <th className="text-left py-3 px-3 font-medium text-gray-500">Weights</th>
                  <th className="text-left py-3 px-3 font-medium text-gray-500">Date</th>
                  <th className="text-left py-3 px-3 font-medium text-gray-500">Status</th>
                  <th className="text-right py-3 px-3 font-medium text-gray-500">Action</th>
                </tr>
              </thead>
              <tbody>
                {initialConfigs.map((config) => (
                  <tr
                    key={config.id}
                    className={`border-b border-gray-100 ${
                      config.is_active ? 'bg-green-50' : ''
                    }`}
                  >
                    <td className="py-3 px-3 font-mono text-gray-700">
                      v{config.version}
                    </td>
                    <td className="py-3 px-3 text-gray-700 max-w-xs truncate">
                      {config.description}
                    </td>
                    <td className="py-3 px-3">
                      {/* 迷你权重展示 */}
                      <div className="flex gap-1">
                        {(Object.keys(WEIGHT_LABELS) as Array<keyof WeightConfig>).map((key) => {
                          const val = config.weights?.[key] ?? 0
                          return (
                            <div
                              key={key}
                              title={`${WEIGHT_LABELS[key]}: ${Math.round(val * 100)}%`}
                              className={`w-2 rounded-full ${WEIGHT_COLORS[key]}`}
                              style={{ height: `${Math.max(4, val * 24)}px`, alignSelf: 'flex-end' }}
                            />
                          )
                        })}
                      </div>
                    </td>
                    <td className="py-3 px-3 text-gray-500 whitespace-nowrap">
                      {new Date(config.created_at).toLocaleDateString('en-US', {
                        month: 'short',
                        day: 'numeric',
                        year: 'numeric',
                      })}
                    </td>
                    <td className="py-3 px-3">
                      {config.is_active ? (
                        <span className="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">
                          Active
                        </span>
                      ) : (
                        <span className="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-600">
                          Inactive
                        </span>
                      )}
                    </td>
                    <td className="py-3 px-3 text-right">
                      {!config.is_active && (
                        <button
                          onClick={() => handleRestore(config.id)}
                          disabled={loading || isPending}
                          className="text-blue-600 hover:text-blue-800 text-sm font-medium disabled:opacity-50 disabled:cursor-not-allowed"
                        >
                          Restore
                        </button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  )
}
