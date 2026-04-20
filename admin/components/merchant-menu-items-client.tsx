'use client'

import { useCallback, useEffect, useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import {
  batchUploadMenuImages,
  importMenuItemPricesFromCsv,
  updateMenuItemPrice,
  deleteMenuItem,
  type MenuItemRow,
  type BatchUploadResult,
} from '@/app/actions/menu-items'

const MAX_FILES = 20
const MAX_BYTES = 8 * 1024 * 1024

type Props = {
  merchantId: string
  initialItems: MenuItemRow[]
}

export default function MerchantMenuItemsClient({ merchantId, initialItems }: Props) {
  const router = useRouter()
  const [isPending, startTransition] = useTransition()
  const [items, setItems] = useState(initialItems)
  const [editing, setEditing] = useState<Record<string, string>>({})
  const [message, setMessage] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [batchInfo, setBatchInfo] = useState<BatchUploadResult | null>(null)

  useEffect(() => {
    setItems(initialItems)
  }, [initialItems])

  const onPriceBlur = (row: MenuItemRow) => {
    const key = row.id
    const raw = editing[key]
    if (raw === undefined) return
    setMessage(null)
    setError(null)
    startTransition(async () => {
      try {
        const t = raw.trim()
        const price: number | null = t === '' || t.toLowerCase() === 'null' ? null : Number.parseFloat(t)
        if (t !== '' && t.toLowerCase() !== 'null' && (Number.isNaN(price) || price! < 0)) {
          setError('Invalid price')
          return
        }
        await updateMenuItemPrice(merchantId, key, price)
        setItems((prev) =>
          prev.map((i) => (i.id === key ? { ...i, price: price } : i))
        )
        setEditing((e) => {
          const n = { ...e }
          delete n[key]
          return n
        })
        setMessage('Saved')
        router.refresh()
      } catch (e) {
        setError(e instanceof Error ? e.message : 'Save failed')
      }
    })
  }

  const onFiles = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      const fileList = e.target.files
      if (!fileList?.length) return
      if (fileList.length > MAX_FILES) {
        setError(`At most ${MAX_FILES} files`)
        return
      }
      for (let i = 0; i < fileList.length; i++) {
        if (fileList[i]!.size > MAX_BYTES) {
          setError('A file exceeds size limit (8MB)')
          return
        }
      }
      setMessage(null)
      setError(null)
      setBatchInfo(null)
      const fd = new FormData()
      for (let i = 0; i < fileList.length; i++) {
        fd.append('files', fileList[i]!)
      }
      startTransition(async () => {
        try {
          const r = await batchUploadMenuImages(merchantId, fd)
          setBatchInfo(r)
          if (r.errors.length) {
            setError(r.errors.map((x) => `${x.fileName}: ${x.message}`).join(' · '))
          } else {
            setMessage(
              `Created ${r.created.length} · Replaced image ${r.replaced.length}`
            )
          }
          e.target.value = ''
          router.refresh()
        } catch (err) {
          setError(err instanceof Error ? err.message : 'Upload failed')
        }
      })
    },
    [merchantId, router]
  )

  const onImportFile = (e: React.ChangeEvent<HTMLInputElement>) => {
    const f = e.target.files?.[0]
    if (!f) return
    setMessage(null)
    setError(null)
    const reader = new FileReader()
    reader.onload = () => {
      const text = String(reader.result ?? '')
      startTransition(async () => {
        try {
          const r = await importMenuItemPricesFromCsv(merchantId, text)
          setMessage(`Updated ${r.updated} row(s)${r.errors.length ? `, ${r.errors.length} line error(s)` : ''}`)
          if (r.errors.length) {
            setError(r.errors.slice(0, 5).map((x) => `Line ${x.line}: ${x.message}`).join(' | '))
          }
          e.target.value = ''
          router.refresh()
        } catch (err) {
          setError(err instanceof Error ? err.message : 'Import failed')
        }
      })
    }
    reader.readAsText(f, 'utf-8')
  }

  const onDelete = (id: string) => {
    if (!confirm('Delete this menu item?')) return
    setError(null)
    setMessage(null)
    startTransition(async () => {
      try {
        await deleteMenuItem(merchantId, id)
        setItems((prev) => prev.filter((i) => i.id !== id))
        setMessage('Deleted')
        router.refresh()
      } catch (e) {
        setError(e instanceof Error ? e.message : 'Delete failed')
      }
    })
  }

  return (
    <div className="space-y-6">
      {message && <p className="text-sm text-emerald-700 bg-emerald-50 border border-emerald-200 rounded-lg px-3 py-2">{message}</p>}
      {error && <p className="text-sm text-red-700 bg-red-50 border border-red-200 rounded-lg px-3 py-2">{error}</p>}
      {batchInfo && (batchInfo.created.length > 0 || batchInfo.replaced.length > 0) && (
        <div className="text-xs text-slate-600 border border-slate-200 rounded-lg p-3 space-y-1">
          {batchInfo.created.length > 0 && (
            <p><span className="font-medium">New:</span> {batchInfo.created.map((c) => c.name).join(', ')}</p>
          )}
          {batchInfo.replaced.length > 0 && (
            <p><span className="font-medium">Image replaced:</span> {batchInfo.replaced.map((c) => c.name).join(', ')}</p>
          )}
        </div>
      )}

      <div className="flex flex-wrap items-center gap-3">
        <label className="inline-flex">
          <span className="sr-only">Batch upload images</span>
          <input
            type="file"
            accept="image/*"
            multiple
            disabled={isPending}
            onChange={onFiles}
            className="text-sm"
          />
        </label>
        <span className="text-xs text-slate-500">Max {MAX_FILES} files, 8MB each. Filename = product name (ext stripped).</span>
      </div>

      <div className="flex flex-wrap items-center gap-3">
        <label className="inline-flex items-center gap-2 text-sm text-slate-700">
          <span>Import prices (CSV)</span>
          <input type="file" accept=".csv,text/csv" disabled={isPending} onChange={onImportFile} className="text-sm" />
        </label>
        <a
          href={`/api/merchants/${merchantId}/menu/export`}
          className="text-sm font-medium text-blue-600 hover:underline"
        >
          Download CSV (UTF-8 BOM)
        </a>
      </div>

      <p className="text-xs text-amber-800 bg-amber-50 border border-amber-200 rounded px-2 py-1.5">
        Unpriced items are draft-only and must not be shown to customers or used in deals (see app filters / price not null).
      </p>

      <div className="overflow-x-auto border border-slate-200 rounded-xl">
        <table className="w-full text-sm text-left">
          <thead className="bg-slate-50 text-slate-600 uppercase text-xs">
            <tr>
              <th className="px-3 py-2">Image</th>
              <th className="px-3 py-2">Name</th>
              <th className="px-3 py-2">ID</th>
              <th className="px-3 py-2">Price (USD)</th>
              <th className="px-3 py-2">Status</th>
              <th className="px-3 py-2">Action</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-100">
            {items.length === 0 && (
              <tr>
                <td colSpan={6} className="px-3 py-4 text-slate-500">No menu items. Upload images to create.</td>
              </tr>
            )}
            {items.map((row) => {
              const draft = row.price == null
              return (
                <tr key={row.id} className="bg-white">
                  <td className="px-3 py-2 w-20">
                    {row.image_url ? (
                      <img src={row.image_url} alt="" className="w-16 h-16 object-cover rounded border border-slate-200" />
                    ) : (
                      <span className="text-slate-400">—</span>
                    )}
                  </td>
                  <td className="px-3 py-2 font-medium text-slate-900">{row.name}</td>
                  <td className="px-3 py-2 font-mono text-xs text-slate-500">{row.id.slice(0, 8)}…</td>
                  <td className="px-3 py-2">
                    <input
                      type="text"
                      className="w-24 border border-slate-200 rounded px-2 py-1"
                      defaultValue={row.price != null ? String(row.price) : ''}
                      placeholder="—"
                      onChange={(e) => setEditing((m) => ({ ...m, [row.id]: e.target.value }))}
                      onBlur={() => onPriceBlur(row)}
                      disabled={isPending}
                    />
                  </td>
                  <td className="px-3 py-2">
                    {draft ? (
                      <span className="text-amber-700 text-xs font-medium">Unpriced (draft)</span>
                    ) : (
                      <span className="text-emerald-700 text-xs">Priced</span>
                    )}
                  </td>
                  <td className="px-3 py-2">
                    <button
                      type="button"
                      onClick={() => onDelete(row.id)}
                      disabled={isPending}
                      className="text-xs text-red-600 hover:underline"
                    >
                      Delete
                    </button>
                  </td>
                </tr>
              )
            })}
          </tbody>
        </table>
      </div>
    </div>
  )
}
