'use client'

import { useCallback, useEffect, useRef, useState, useTransition } from 'react'
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

function IconUpload(props: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} className={props.className} aria-hidden>
      <path d="M12 16V4m0 0 4 4m-4-4L8 8" strokeLinecap="round" strokeLinejoin="round" />
      <path d="M4 14v4a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-4" strokeLinecap="round" />
    </svg>
  )
}

function IconTable(props: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.75} className={props.className} aria-hidden>
      <rect x="3" y="4" width="18" height="16" rx="2" />
      <path d="M3 10h18M10 4v16" />
    </svg>
  )
}

function IconDownload(props: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} className={props.className} aria-hidden>
      <path d="M12 4v12m0 0 4-4m-4 4-4-4M5 20h14" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  )
}

export default function MerchantMenuItemsClient({ merchantId, initialItems }: Props) {
  const router = useRouter()
  const [isPending, startTransition] = useTransition()
  const [items, setItems] = useState(initialItems)
  const [editing, setEditing] = useState<Record<string, string>>({})
  const [message, setMessage] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [batchInfo, setBatchInfo] = useState<BatchUploadResult | null>(null)
  const [batchExpanded, setBatchExpanded] = useState(true)
  const imageInputRef = useRef<HTMLInputElement>(null)
  const csvInputRef = useRef<HTMLInputElement>(null)

  useEffect(() => {
    setItems(initialItems)
  }, [initialItems])

  const pricedCount = items.filter((i) => i.price != null).length
  const draftCount = items.length - pricedCount

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
        setItems((prev) => prev.map((i) => (i.id === key ? { ...i, price: price } : i)))
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
            setMessage(`Created ${r.created.length} · Replaced image ${r.replaced.length}`)
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
    <div className="space-y-8">
      {/* 顶部反馈 */}
      <div className="space-y-3" role="status" aria-live="polite">
        {message && (
          <div className="flex items-start gap-3 rounded-xl border border-emerald-200/90 bg-emerald-50/95 px-4 py-3 text-sm text-emerald-900 shadow-sm">
            <span className="mt-0.5 flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-emerald-600 text-xs font-bold text-white">
              ✓
            </span>
            <p className="leading-snug">{message}</p>
          </div>
        )}
        {error && (
          <div className="rounded-xl border border-red-200/90 bg-red-50/95 px-4 py-3 text-sm text-red-900 shadow-sm">
            {error}
          </div>
        )}
        {batchInfo && (batchInfo.created.length > 0 || batchInfo.replaced.length > 0) && (
          <div className="overflow-hidden rounded-xl border border-stone-200 bg-white shadow-sm">
            <button
              type="button"
              onClick={() => setBatchExpanded((v) => !v)}
              className="flex w-full items-center justify-between gap-2 px-4 py-3 text-left text-sm font-medium text-stone-800 transition hover:bg-stone-50"
            >
              <span>Last upload details</span>
              <span className="text-stone-400">{batchExpanded ? '▼' : '▶'}</span>
            </button>
            {batchExpanded && (
              <div className="space-y-2 border-t border-stone-100 px-4 py-3 text-xs leading-relaxed text-stone-600">
                {batchInfo.created.length > 0 && (
                  <p>
                    <span className="font-semibold text-teal-800">New:</span> {batchInfo.created.map((c) => c.name).join(', ')}
                  </p>
                )}
                {batchInfo.replaced.length > 0 && (
                  <p>
                    <span className="font-semibold text-stone-800">Image replaced:</span>{' '}
                    {batchInfo.replaced.map((c) => c.name).join(', ')}
                  </p>
                )}
              </div>
            )}
          </div>
        )}
      </div>

      {/* 统计条 */}
      <div className="flex flex-wrap items-center gap-3 rounded-xl border border-stone-200 bg-stone-50/80 px-4 py-3 text-sm text-stone-700">
        <span className="font-medium text-stone-900">{items.length}</span>
        <span className="text-stone-500">items</span>
        <span className="hidden h-4 w-px bg-stone-300 sm:inline" aria-hidden />
        <span className="rounded-full bg-emerald-100 px-2.5 py-0.5 text-xs font-semibold text-emerald-900">
          Priced {pricedCount}
        </span>
        <span className="rounded-full bg-amber-100 px-2.5 py-0.5 text-xs font-semibold text-amber-900">
          Draft {draftCount}
        </span>
        {isPending && (
          <span className="ml-auto inline-flex items-center gap-2 text-xs font-medium text-teal-800">
            <span className="inline-block h-3.5 w-3.5 animate-spin rounded-full border-2 border-teal-600 border-t-transparent" />
            Working…
          </span>
        )}
      </div>

      {/* 操作分区 */}
      <div className="grid gap-5 md:grid-cols-2">
        <section
          className="group relative rounded-2xl border border-stone-200/90 bg-white p-6 shadow-[0_1px_0_rgba(15,23,42,0.04)] ring-1 ring-stone-900/[0.03] transition hover:shadow-md"
          aria-busy={isPending}
        >
          <div className="mb-4 flex items-start gap-3">
            <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-teal-600 text-white shadow-inner">
              <IconUpload className="h-5 w-5" />
            </span>
            <div>
              <h2 className="text-sm font-semibold tracking-tight text-stone-900">Bulk images</h2>
              <p className="mt-1 text-xs leading-relaxed text-stone-500">
                Filename becomes the product name (extension removed). Existing names get their image updated.
              </p>
            </div>
          </div>
          <input
            ref={imageInputRef}
            type="file"
            accept="image/*"
            multiple
            disabled={isPending}
            onChange={onFiles}
            className="sr-only"
            aria-label="Batch upload product images"
          />
          <button
            type="button"
            disabled={isPending}
            onClick={() => imageInputRef.current?.click()}
            className="inline-flex w-full items-center justify-center gap-2 rounded-xl bg-stone-900 px-4 py-3 text-sm font-semibold text-white shadow-md transition hover:bg-stone-800 disabled:cursor-not-allowed disabled:opacity-50 sm:w-auto sm:justify-start sm:px-5"
          >
            <IconUpload className="h-4 w-4" />
            Choose images
          </button>
          <p className="mt-3 text-xs text-stone-500">
            Up to {MAX_FILES} files · {Math.round(MAX_BYTES / (1024 * 1024))} MB each
          </p>
        </section>

        <section
          className="relative rounded-2xl border border-stone-200/90 bg-white p-6 shadow-[0_1px_0_rgba(15,23,42,0.04)] ring-1 ring-stone-900/[0.03] transition hover:shadow-md"
          aria-busy={isPending}
        >
          <div className="mb-4 flex items-start gap-3">
            <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-stone-800 text-white shadow-inner">
              <IconTable className="h-5 w-5" />
            </span>
            <div>
              <h2 className="text-sm font-semibold tracking-tight text-stone-900">Prices & export</h2>
              <p className="mt-1 text-xs leading-relaxed text-stone-500">
                Import a CSV to update prices by row <code className="rounded bg-stone-100 px-1 py-0.5 font-mono text-[10px]">id</code>
                . Download current rows anytime.
              </p>
            </div>
          </div>
          <div className="flex flex-col gap-3 sm:flex-row sm:flex-wrap sm:items-center">
            <input
              ref={csvInputRef}
              type="file"
              accept=".csv,text/csv"
              disabled={isPending}
              onChange={onImportFile}
              className="sr-only"
              aria-label="Import prices from CSV file"
            />
            <button
              type="button"
              disabled={isPending}
              onClick={() => csvInputRef.current?.click()}
              className="inline-flex flex-1 items-center justify-center gap-2 rounded-xl border-2 border-stone-300 bg-stone-50 px-4 py-3 text-sm font-semibold text-stone-800 transition hover:border-stone-400 hover:bg-white disabled:cursor-not-allowed disabled:opacity-50 sm:flex-none"
            >
              Import CSV
            </button>
            <a
              href={`/api/merchants/${merchantId}/menu/export`}
              className="inline-flex flex-1 items-center justify-center gap-2 rounded-xl border border-teal-200 bg-teal-50/80 px-4 py-3 text-sm font-semibold text-teal-900 transition hover:bg-teal-100 sm:flex-none"
            >
              <IconDownload className="h-4 w-4" />
              Download CSV
            </a>
          </div>
          <p className="mt-3 text-[11px] text-stone-500">Export uses UTF-8 with BOM for Excel compatibility.</p>
        </section>
      </div>

      {/* 业务提示 */}
      <aside className="flex gap-3 rounded-xl border-l-4 border-amber-500 bg-amber-50/60 px-4 py-3 text-sm text-amber-950 shadow-sm">
        <span className="shrink-0 text-lg leading-none" aria-hidden>
          ⚠
        </span>
        <p className="leading-relaxed">
          <strong className="font-semibold">Draft rule:</strong> unpriced rows stay internal only — they are hidden from
          the customer app and cannot be used as deal-linked menu items until a price is set.
        </p>
      </aside>

      {/* 表格 */}
      <div className="relative overflow-hidden rounded-2xl border border-stone-200/90 bg-white shadow-[0_1px_0_rgba(15,23,42,0.04)]">
        {isPending && (
          <div
            className="pointer-events-none absolute inset-0 z-10 bg-white/40 backdrop-blur-[1px]"
            aria-hidden
          />
        )}
        <div className="overflow-x-auto">
          <table className="w-full min-w-[640px] text-left text-sm">
            <thead>
              <tr className="border-b border-stone-200 bg-gradient-to-b from-stone-100 to-stone-50/90">
                <th className="px-4 py-3.5 text-[11px] font-bold uppercase tracking-wider text-stone-500">Image</th>
                <th className="px-4 py-3.5 text-[11px] font-bold uppercase tracking-wider text-stone-500">Name</th>
                <th className="px-4 py-3.5 text-[11px] font-bold uppercase tracking-wider text-stone-500">ID</th>
                <th className="px-4 py-3.5 text-[11px] font-bold uppercase tracking-wider text-stone-500">
                  Price <span className="font-normal normal-case text-stone-400">(USD)</span>
                </th>
                <th className="px-4 py-3.5 text-[11px] font-bold uppercase tracking-wider text-stone-500">Status</th>
                <th className="px-4 py-3.5 text-[11px] font-bold uppercase tracking-wider text-stone-500">Action</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-stone-100">
              {items.length === 0 && (
                <tr>
                  <td colSpan={6} className="px-6 py-16 text-center">
                    <p className="text-base font-medium text-stone-700">No menu items yet</p>
                    <p className="mx-auto mt-2 max-w-sm text-sm text-stone-500">
                      Upload one or more images above — each file creates a row named after the file.
                    </p>
                  </td>
                </tr>
              )}
              {items.map((row) => {
                const draft = row.price == null
                return (
                  <tr
                    key={row.id}
                    className={`transition-colors hover:bg-stone-50/90 ${draft ? 'bg-amber-50/25' : 'bg-white'}`}
                  >
                    <td className="px-4 py-3 align-middle">
                      {row.image_url ? (
                        // Storage URL 域名不固定，不用 next/image
                        // eslint-disable-next-line @next/next/no-img-element
                        <img
                          src={row.image_url}
                          alt=""
                          className="h-16 w-16 rounded-lg border border-stone-200 object-cover shadow-sm"
                        />
                      ) : (
                        <span className="flex h-16 w-16 items-center justify-center rounded-lg border border-dashed border-stone-200 bg-stone-50 text-xs text-stone-400">
                          —
                        </span>
                      )}
                    </td>
                    <td className="px-4 py-3 align-middle font-medium text-stone-900">{row.name}</td>
                    <td className="px-4 py-3 align-middle">
                      <code className="rounded-md bg-stone-100 px-2 py-1 font-mono text-[11px] text-stone-600">
                        {row.id.slice(0, 8)}…
                      </code>
                    </td>
                    <td className="px-4 py-3 align-middle">
                      <div className="flex max-w-[8rem] flex-col gap-1">
                        <input
                          type="text"
                          inputMode="decimal"
                          className="w-full rounded-lg border border-stone-300 bg-white px-3 py-2 text-sm font-medium tabular-nums text-stone-900 shadow-inner outline-none ring-teal-600/0 transition focus:border-teal-600 focus:ring-2 focus:ring-teal-600/25 disabled:opacity-50"
                          defaultValue={row.price != null ? String(row.price) : ''}
                          placeholder="—"
                          onChange={(e) => setEditing((m) => ({ ...m, [row.id]: e.target.value }))}
                          onBlur={() => onPriceBlur(row)}
                          disabled={isPending}
                          aria-label={`Price for ${row.name}`}
                        />
                        <span className="text-[10px] text-stone-400">Tab out to save</span>
                      </div>
                    </td>
                    <td className="px-4 py-3 align-middle">
                      {draft ? (
                        <span className="inline-flex items-center rounded-full border border-amber-200/80 bg-amber-50 px-2.5 py-1 text-[11px] font-semibold uppercase tracking-wide text-amber-900">
                          Draft
                        </span>
                      ) : (
                        <span className="inline-flex items-center rounded-full border border-emerald-200/80 bg-emerald-50 px-2.5 py-1 text-[11px] font-semibold uppercase tracking-wide text-emerald-900">
                          Priced
                        </span>
                      )}
                    </td>
                    <td className="px-4 py-3 align-middle">
                      <button
                        type="button"
                        onClick={() => onDelete(row.id)}
                        disabled={isPending}
                        className="rounded-lg px-2 py-1.5 text-xs font-semibold text-red-700 transition hover:bg-red-50 disabled:opacity-50"
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
    </div>
  )
}
