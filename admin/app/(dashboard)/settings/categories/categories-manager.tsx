'use client'

import { useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { useRouter } from 'next/navigation'

interface Category {
  id: number
  name: string
  icon: string | null
  order: number
  merchant_count: number
}

export default function CategoriesManager({ initialCategories }: { initialCategories: Category[] }) {
  const [categories, setCategories] = useState(initialCategories)
  const [editingId, setEditingId] = useState<number | null>(null)
  const [editName, setEditName] = useState('')
  const [editIcon, setEditIcon] = useState('')
  const [editOrder, setEditOrder] = useState(0)
  const [showAdd, setShowAdd] = useState(false)
  const [newName, setNewName] = useState('')
  const [newIcon, setNewIcon] = useState('')
  const [newOrder, setNewOrder] = useState(0)
  const [saving, setSaving] = useState(false)
  const router = useRouter()

  const supabase = createClient()

  // 新增分类
  async function handleAdd() {
    if (!newName.trim()) return
    setSaving(true)
    try {
      const { data, error } = await supabase
        .from('categories')
        .insert({
          name: newName.trim(),
          icon: newIcon.trim() || null,
          order: newOrder,
        })
        .select('id, name, icon, order')
        .single()

      if (error) throw error

      setCategories(prev => [...prev, { ...data, merchant_count: 0 }])
      setNewName('')
      setNewIcon('')
      setNewOrder(0)
      setShowAdd(false)
      router.refresh()
    } catch (e: unknown) {
      alert(`Failed to add: ${e instanceof Error ? e.message : String(e)}`)
    } finally {
      setSaving(false)
    }
  }

  // 更新分类
  async function handleUpdate(id: number) {
    if (!editName.trim()) return
    setSaving(true)
    try {
      const { error } = await supabase
        .from('categories')
        .update({
          name: editName.trim(),
          icon: editIcon.trim() || null,
          order: editOrder,
        })
        .eq('id', id)

      if (error) throw error

      setCategories(prev =>
        prev.map(c =>
          c.id === id
            ? { ...c, name: editName.trim(), icon: editIcon.trim() || null, order: editOrder }
            : c
        )
      )
      setEditingId(null)
      router.refresh()
    } catch (e: unknown) {
      alert(`Failed to update: ${e instanceof Error ? e.message : String(e)}`)
    } finally {
      setSaving(false)
    }
  }

  // 删除分类
  async function handleDelete(id: number, name: string, merchantCount: number) {
    if (merchantCount > 0) {
      if (!confirm(`"${name}" is used by ${merchantCount} merchants. Deleting it will remove all associations. Continue?`)) return
    } else {
      if (!confirm(`Delete category "${name}"?`)) return
    }

    setSaving(true)
    try {
      const { error } = await supabase
        .from('categories')
        .delete()
        .eq('id', id)

      if (error) throw error

      setCategories(prev => prev.filter(c => c.id !== id))
      router.refresh()
    } catch (e: unknown) {
      alert(`Failed to delete: ${e instanceof Error ? e.message : String(e)}`)
    } finally {
      setSaving(false)
    }
  }

  function startEdit(cat: Category) {
    setEditingId(cat.id)
    setEditName(cat.name)
    setEditIcon(cat.icon || '')
    setEditOrder(cat.order)
  }

  return (
    <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
      {/* 表头 */}
      <div className="flex items-center justify-between px-5 py-4 border-b border-gray-100">
        <h2 className="text-sm font-semibold text-gray-700">All Categories</h2>
        <button
          onClick={() => setShowAdd(!showAdd)}
          className="px-3 py-1.5 text-sm font-medium text-white bg-blue-600 rounded-lg hover:bg-blue-700 transition-colors"
        >
          + Add Category
        </button>
      </div>

      {/* 新增行 */}
      {showAdd && (
        <div className="flex items-center gap-3 px-5 py-3 bg-blue-50 border-b border-blue-100">
          <input
            type="text"
            placeholder="Name (e.g. BBQ)"
            value={newName}
            onChange={e => setNewName(e.target.value)}
            className="flex-1 px-3 py-2 text-sm border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none"
          />
          <input
            type="text"
            placeholder="Icon (emoji)"
            value={newIcon}
            onChange={e => setNewIcon(e.target.value)}
            className="w-24 px-3 py-2 text-sm border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none"
          />
          <input
            type="number"
            placeholder="Order"
            value={newOrder}
            onChange={e => setNewOrder(Number(e.target.value))}
            className="w-20 px-3 py-2 text-sm border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none"
          />
          <button
            onClick={handleAdd}
            disabled={saving || !newName.trim()}
            className="px-4 py-2 text-sm font-medium text-white bg-green-600 rounded-lg hover:bg-green-700 disabled:opacity-50 transition-colors"
          >
            {saving ? '...' : 'Add'}
          </button>
          <button
            onClick={() => setShowAdd(false)}
            className="px-3 py-2 text-sm text-gray-500 hover:text-gray-700"
          >
            Cancel
          </button>
        </div>
      )}

      {/* 分类列表 */}
      <table className="w-full">
        <thead>
          <tr className="text-left text-xs font-medium text-gray-500 uppercase tracking-wider border-b border-gray-100">
            <th className="px-5 py-3 w-16">Order</th>
            <th className="px-5 py-3 w-16">Icon</th>
            <th className="px-5 py-3">Name</th>
            <th className="px-5 py-3 w-32">Merchants</th>
            <th className="px-5 py-3 w-40 text-right">Actions</th>
          </tr>
        </thead>
        <tbody>
          {categories.length === 0 ? (
            <tr>
              <td colSpan={5} className="px-5 py-12 text-center text-gray-400">
                No categories yet. Click &quot;+ Add Category&quot; to create one.
              </td>
            </tr>
          ) : (
            categories
              .sort((a, b) => a.order - b.order)
              .map(cat => (
                <tr key={cat.id} className="border-b border-gray-50 hover:bg-gray-50 transition-colors">
                  {editingId === cat.id ? (
                    // 编辑模式
                    <>
                      <td className="px-5 py-3">
                        <input
                          type="number"
                          value={editOrder}
                          onChange={e => setEditOrder(Number(e.target.value))}
                          className="w-16 px-2 py-1 text-sm border border-gray-300 rounded focus:ring-2 focus:ring-blue-500 outline-none"
                        />
                      </td>
                      <td className="px-5 py-3">
                        <input
                          type="text"
                          value={editIcon}
                          onChange={e => setEditIcon(e.target.value)}
                          className="w-12 px-2 py-1 text-sm border border-gray-300 rounded focus:ring-2 focus:ring-blue-500 outline-none"
                        />
                      </td>
                      <td className="px-5 py-3">
                        <input
                          type="text"
                          value={editName}
                          onChange={e => setEditName(e.target.value)}
                          className="w-full px-2 py-1 text-sm border border-gray-300 rounded focus:ring-2 focus:ring-blue-500 outline-none"
                        />
                      </td>
                      <td className="px-5 py-3 text-sm text-gray-500">
                        {cat.merchant_count}
                      </td>
                      <td className="px-5 py-3 text-right space-x-2">
                        <button
                          onClick={() => handleUpdate(cat.id)}
                          disabled={saving}
                          className="px-3 py-1 text-xs font-medium text-white bg-green-600 rounded hover:bg-green-700 disabled:opacity-50"
                        >
                          Save
                        </button>
                        <button
                          onClick={() => setEditingId(null)}
                          className="px-3 py-1 text-xs text-gray-500 hover:text-gray-700"
                        >
                          Cancel
                        </button>
                      </td>
                    </>
                  ) : (
                    // 展示模式
                    <>
                      <td className="px-5 py-3 text-sm text-gray-600">{cat.order}</td>
                      <td className="px-5 py-3 text-lg">{cat.icon || '—'}</td>
                      <td className="px-5 py-3 text-sm font-medium text-gray-900">{cat.name}</td>
                      <td className="px-5 py-3">
                        {cat.merchant_count > 0 ? (
                          <span className="inline-flex items-center px-2 py-0.5 text-xs font-medium bg-blue-50 text-blue-700 rounded-full">
                            {cat.merchant_count} stores
                          </span>
                        ) : (
                          <span className="text-xs text-gray-400">0</span>
                        )}
                      </td>
                      <td className="px-5 py-3 text-right space-x-2">
                        <button
                          onClick={() => startEdit(cat)}
                          className="px-3 py-1 text-xs font-medium text-blue-600 hover:text-blue-800 hover:bg-blue-50 rounded transition-colors"
                        >
                          Edit
                        </button>
                        <button
                          onClick={() => handleDelete(cat.id, cat.name, cat.merchant_count)}
                          disabled={saving}
                          className="px-3 py-1 text-xs font-medium text-red-600 hover:text-red-800 hover:bg-red-50 rounded transition-colors disabled:opacity-50"
                        >
                          Delete
                        </button>
                      </td>
                    </>
                  )}
                </tr>
              ))
          )}
        </tbody>
      </table>
    </div>
  )
}
