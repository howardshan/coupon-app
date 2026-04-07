'use client'

import { useState, useTransition } from 'react'
import { toast } from 'sonner'
import { updateLegalPlaceholders } from '@/app/actions/legal'

type Placeholder = {
  key: string
  placeholder: string
  value: string
  description: string | null
  updated_at: string
}

export default function PlaceholdersEditor({ initialData }: { initialData: Placeholder[] }) {
  const [items, setItems] = useState(initialData)
  const [isPending, startTransition] = useTransition()

  // 追踪哪些字段被修改了
  const [dirty, setDirty] = useState<Set<string>>(new Set())

  function handleChange(key: string, newValue: string) {
    setItems(prev => prev.map(item =>
      item.key === key ? { ...item, value: newValue } : item
    ))
    setDirty(prev => new Set(prev).add(key))
  }

  function handleSaveAll() {
    if (dirty.size === 0) {
      toast.info('No changes to save')
      return
    }

    const updates = items
      .filter(item => dirty.has(item.key))
      .map(item => ({ key: item.key, value: item.value }))

    startTransition(async () => {
      try {
        await updateLegalPlaceholders(updates)
        setDirty(new Set())
        toast.success(`${updates.length} placeholder(s) updated`)
      } catch (e: unknown) {
        toast.error((e as Error).message || 'Failed to save')
      }
    })
  }

  // 检查某个值是否为空（需要填写）
  const emptyCount = items.filter(i => !i.value).length

  return (
    <div>
      {/* 状态摘要 */}
      {emptyCount > 0 && (
        <div className="mb-6 p-3 rounded-lg bg-amber-50 border border-amber-200 text-sm text-amber-800">
          ⚠️ {emptyCount} placeholder(s) still need to be filled in before publishing legal documents.
        </div>
      )}

      {/* 占位符列表 */}
      <div className="space-y-4">
        {items.map(item => (
          <div
            key={item.key}
            className="bg-white border border-gray-200 rounded-xl p-5"
          >
            <div className="flex items-start justify-between gap-4">
              <div className="flex-1">
                {/* 标题行 */}
                <div className="flex items-center gap-2 mb-1">
                  <span className="font-semibold text-gray-900 text-sm">{item.key}</span>
                  <code className="text-xs bg-gray-100 text-gray-600 px-1.5 py-0.5 rounded">
                    {item.placeholder}
                  </code>
                  {!item.value && (
                    <span className="text-xs px-1.5 py-0.5 rounded bg-red-100 text-red-700 font-medium">
                      Empty
                    </span>
                  )}
                  {dirty.has(item.key) && (
                    <span className="text-xs px-1.5 py-0.5 rounded bg-blue-100 text-blue-700 font-medium">
                      Modified
                    </span>
                  )}
                </div>

                {/* 说明 */}
                {item.description && (
                  <p className="text-xs text-gray-500 mb-3">{item.description}</p>
                )}

                {/* 输入框 */}
                <input
                  type="text"
                  value={item.value}
                  onChange={(e) => handleChange(item.key, e.target.value)}
                  placeholder={`Enter value for ${item.placeholder}...`}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                />
              </div>
            </div>

            {/* 上次更新时间 */}
            {item.updated_at && (
              <p className="text-xs text-gray-400 mt-2">
                Last updated: {new Date(item.updated_at).toLocaleString('en-US')}
              </p>
            )}
          </div>
        ))}
      </div>

      {/* 保存按钮 */}
      <div className="sticky bottom-0 bg-white border-t border-gray-200 p-4 mt-6 -mx-4 flex items-center justify-between">
        <span className="text-sm text-gray-500">
          {dirty.size > 0
            ? `${dirty.size} unsaved change(s)`
            : 'All saved'}
        </span>
        <button
          onClick={handleSaveAll}
          disabled={isPending || dirty.size === 0}
          className="px-5 py-2 bg-blue-600 text-white text-sm font-medium rounded-lg hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
        >
          {isPending ? 'Saving...' : 'Save All Changes'}
        </button>
      </div>
    </div>
  )
}
