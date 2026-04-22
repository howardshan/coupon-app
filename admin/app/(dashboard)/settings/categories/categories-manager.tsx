'use client'

import { useState, useRef } from 'react'
import Image from 'next/image'
import { useRouter } from 'next/navigation'
import { addCategory, updateCategory, deleteCategory, uploadCategoryIcon, reorderCategories } from './actions'

interface Category {
  id: number
  name: string
  icon: string | null
  order: number
  merchant_count: number
}

/** 判断是否是 URL（http/https 开头） */
function isUrl(v: string | null): boolean {
  return !!v && (v.startsWith('http://') || v.startsWith('https://'))
}

/** 分类图标展示：URL → <Image>，其他 → emoji 文字 */
function IconDisplay({ icon, size = 32 }: { icon: string | null; size?: number }) {
  if (!icon) return <span className="text-gray-300">—</span>
  if (isUrl(icon)) {
    return (
      <Image
        src={icon}
        alt="icon"
        width={size}
        height={size}
        className="rounded object-cover"
        style={{ width: size, height: size }}
      />
    )
  }
  return <span style={{ fontSize: size * 0.7 }}>{icon}</span>
}

/** 图标上传小组件，上传完成后回调 URL */
function IconUploader({
  current,
  onChange,
  uploading,
  setUploading,
}: {
  current: string
  onChange: (url: string) => void
  uploading: boolean
  setUploading: (v: boolean) => void
}) {
  const inputRef = useRef<HTMLInputElement>(null)

  async function handleFile(file: File) {
    setUploading(true)
    try {
      const fd = new FormData()
      fd.append('file', file)
      const { url, error } = await uploadCategoryIcon(fd)
      if (error) { alert(`Upload failed: ${error}`); return }
      if (url) onChange(url)
    } finally {
      setUploading(false)
    }
  }

  return (
    <div className="flex items-center gap-2">
      {/* 当前图标预览 */}
      <div
        className="w-10 h-10 border border-gray-200 rounded-lg flex items-center justify-center bg-gray-50 overflow-hidden cursor-pointer hover:bg-gray-100 transition-colors flex-shrink-0"
        onClick={() => inputRef.current?.click()}
        title="Click to upload icon"
      >
        {uploading ? (
          <svg className="animate-spin w-4 h-4 text-blue-500" fill="none" viewBox="0 0 24 24">
            <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
            <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8z" />
          </svg>
        ) : current ? (
          <IconDisplay icon={current} size={28} />
        ) : (
          <svg className="w-5 h-5 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5}
              d="M4 16l4-4m0 0l4 4m-4-4v9M20 16l-4-4m0 0l-4 4m4-4V4" />
          </svg>
        )}
      </div>

      {/* 上传按钮 */}
      <button
        type="button"
        onClick={() => inputRef.current?.click()}
        disabled={uploading}
        className="px-2 py-1 text-xs text-blue-600 border border-blue-200 rounded hover:bg-blue-50 disabled:opacity-50 transition-colors whitespace-nowrap"
      >
        {uploading ? 'Uploading…' : current ? 'Change' : 'Upload'}
      </button>

      {/* 清除按钮 */}
      {current && !uploading && (
        <button
          type="button"
          onClick={() => onChange('')}
          className="px-2 py-1 text-xs text-red-500 border border-red-200 rounded hover:bg-red-50 transition-colors"
        >
          Remove
        </button>
      )}

      {/* 隐藏的文件输入 */}
      <input
        ref={inputRef}
        type="file"
        accept="image/png,image/jpeg,image/webp,image/svg+xml"
        className="hidden"
        onChange={e => {
          const file = e.target.files?.[0]
          if (file) handleFile(file)
          e.target.value = ''
        }}
      />
    </div>
  )
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
  const [uploadingNew, setUploadingNew] = useState(false)
  const [uploadingEdit, setUploadingEdit] = useState(false)
  const router = useRouter()

  // 新增分类
  async function handleAdd() {
    if (!newName.trim()) return
    setSaving(true)
    try {
      const { data, error } = await addCategory(
        newName.trim(),
        newIcon.trim() || null,
        newOrder,
      )
      if (error) throw new Error(error)

      setCategories(prev => [...prev, { ...data!, merchant_count: 0 }])
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
      const { error } = await updateCategory(
        id,
        editName.trim(),
        editIcon.trim() || null,
        editOrder,
      )
      if (error) throw new Error(error)

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
      const { error } = await deleteCategory(id)
      if (error) throw new Error(error)

      setCategories(prev => prev.filter(c => c.id !== id))
      router.refresh()
    } catch (e: unknown) {
      alert(`Failed to delete: ${e instanceof Error ? e.message : String(e)}`)
    } finally {
      setSaving(false)
    }
  }

  // 上移 / 下移（交换相邻两条的 order 值）
  async function handleMove(id: number, direction: 'up' | 'down') {
    const sorted = [...categories].sort((a, b) => a.order - b.order)
    const idx = sorted.findIndex(c => c.id === id)
    const swapIdx = direction === 'up' ? idx - 1 : idx + 1
    if (swapIdx < 0 || swapIdx >= sorted.length) return

    const a = sorted[idx]
    const b = sorted[swapIdx]

    // 乐观更新本地状态
    setCategories(prev =>
      prev.map(c => {
        if (c.id === a.id) return { ...c, order: b.order }
        if (c.id === b.id) return { ...c, order: a.order }
        return c
      })
    )

    const { error } = await reorderCategories(a.id, b.order, b.id, a.order)
    if (error) {
      // 回滚
      setCategories(prev =>
        prev.map(c => {
          if (c.id === a.id) return { ...c, order: a.order }
          if (c.id === b.id) return { ...c, order: b.order }
          return c
        })
      )
      alert(`Failed to reorder: ${error}`)
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
        <div className="flex items-center gap-3 px-5 py-3 bg-blue-50 border-b border-blue-100 flex-wrap">
          <input
            type="text"
            placeholder="Name (e.g. BBQ)"
            value={newName}
            onChange={e => setNewName(e.target.value)}
            onKeyDown={e => e.key === 'Enter' && handleAdd()}
            className="flex-1 min-w-40 px-3 py-2 text-sm border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none"
          />
          {/* 图标上传 */}
          <IconUploader
            current={newIcon}
            onChange={setNewIcon}
            uploading={uploadingNew}
            setUploading={setUploadingNew}
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
            disabled={saving || uploadingNew || !newName.trim()}
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
            <th className="px-5 py-3 w-20">Icon</th>
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
          ) : (() => {
            const sorted = [...categories].sort((a, b) => a.order - b.order)
            return sorted.map((cat, idx) => (
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
                      {/* 编辑图标 */}
                      <td className="px-5 py-3">
                        <IconUploader
                          current={editIcon}
                          onChange={setEditIcon}
                          uploading={uploadingEdit}
                          setUploading={setUploadingEdit}
                        />
                      </td>
                      <td className="px-5 py-3">
                        <input
                          type="text"
                          value={editName}
                          onChange={e => setEditName(e.target.value)}
                          onKeyDown={e => e.key === 'Enter' && handleUpdate(cat.id)}
                          className="w-full px-2 py-1 text-sm border border-gray-300 rounded focus:ring-2 focus:ring-blue-500 outline-none"
                        />
                      </td>
                      <td className="px-5 py-3 text-sm text-gray-500">
                        {cat.merchant_count}
                      </td>
                      <td className="px-5 py-3 text-right space-x-2">
                        <button
                          onClick={() => handleUpdate(cat.id)}
                          disabled={saving || uploadingEdit}
                          className="px-3 py-1 text-xs font-medium text-white bg-green-600 rounded hover:bg-green-700 disabled:opacity-50"
                        >
                          {saving ? '...' : 'Save'}
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
                      <td className="px-3 py-3">
                        <div className="flex items-center gap-1">
                          {/* 上移 */}
                          <button
                            onClick={() => handleMove(cat.id, 'up')}
                            disabled={idx === 0 || saving}
                            className="p-0.5 rounded text-gray-400 hover:text-gray-700 hover:bg-gray-100 disabled:opacity-20 disabled:cursor-not-allowed transition-colors"
                            title="Move up"
                          >
                            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 15l7-7 7 7" />
                            </svg>
                          </button>
                          <span className="text-xs text-gray-500 w-5 text-center">{cat.order}</span>
                          {/* 下移 */}
                          <button
                            onClick={() => handleMove(cat.id, 'down')}
                            disabled={idx === sorted.length - 1 || saving}
                            className="p-0.5 rounded text-gray-400 hover:text-gray-700 hover:bg-gray-100 disabled:opacity-20 disabled:cursor-not-allowed transition-colors"
                            title="Move down"
                          >
                            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
                            </svg>
                          </button>
                        </div>
                      </td>
                      <td className="px-5 py-3">
                        <IconDisplay icon={cat.icon} size={32} />
                      </td>
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
          })()}
        </tbody>
      </table>
    </div>
  )
}
