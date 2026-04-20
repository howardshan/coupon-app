'use server'

import { revalidatePath } from 'next/cache'
import { createClient } from '@/lib/supabase/server'
import { getServiceRoleClient } from '@/lib/supabase/service'
import { normalizeMenuItemName, normalizeMenuItemNameFromFileName } from '@/lib/menu-item-name'

const BUCKET = 'menu-items'
const MAX_FILES = 20
const MAX_FILE_BYTES = 8 * 1024 * 1024

type AdminSession = { adminUserId: string }

async function requireAdmin(): Promise<AdminSession> {
  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) throw new Error('Unauthorized')
  const { data: profile } = await supabase.from('users').select('role').eq('id', user.id).single()
  if (profile?.role !== 'admin') throw new Error('Forbidden')
  return { adminUserId: user.id }
}

function publicUrlForPath(path: string): string {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL
  if (!url) throw new Error('NEXT_PUBLIC_SUPABASE_URL is not set')
  return `${url}/storage/v1/object/public/${BUCKET}/${path}`
}

function extractObjectPathFromPublicUrl(imageUrl: string | null | undefined): string | null {
  if (!imageUrl) return null
  const marker = `/object/public/${BUCKET}/`
  const i = imageUrl.indexOf(marker)
  if (i === -1) return null
  return imageUrl.slice(i + marker.length)
}

function extFromFile(file: File): string {
  const n = file.name
  const last = n.lastIndexOf('.')
  if (last <= 0) return 'jpg'
  const ext = n.slice(last + 1).toLowerCase().replace(/[^a-z0-9]/g, '')
  if (!ext || ext.length > 8) return 'jpg'
  return ext
}

export type MenuItemRow = {
  id: string
  merchant_id: string
  name: string
  name_normalized: string
  image_url: string | null
  price: number | null
  category: string
  sort_order: number
  created_at: string
}

export async function updateMenuItemPrice(
  merchantId: string,
  itemId: string,
  price: number | null
): Promise<void> {
  await requireAdmin()
  const db = getServiceRoleClient()
  const { data: row } = await db
    .from('menu_items')
    .select('id')
    .eq('id', itemId)
    .eq('merchant_id', merchantId)
    .maybeSingle()
  if (!row) throw new Error('Item not found for this merchant')

  const { error } = await db
    .from('menu_items')
    .update({ price })
    .eq('id', itemId)
    .eq('merchant_id', merchantId)
  if (error) throw new Error(error.message)
  revalidatePath(`/merchants/${merchantId}/menu`)
}

export type BatchUploadResult = {
  created: { name: string; id: string }[]
  replaced: { name: string; id: string }[]
  errors: { fileName: string; message: string }[]
}

export async function batchUploadMenuImages(merchantId: string, formData: FormData): Promise<BatchUploadResult> {
  await requireAdmin()
  const db = getServiceRoleClient()
  const files = formData.getAll('files').filter((x): x is File => x instanceof File)
  if (files.length === 0) throw new Error('No files')
  if (files.length > MAX_FILES) throw new Error(`At most ${MAX_FILES} files per batch`)

  const result: BatchUploadResult = { created: [], replaced: [], errors: [] }

  for (const file of files) {
    if (file.size > MAX_FILE_BYTES) {
      result.errors.push({ fileName: file.name, message: 'File too large' })
      continue
    }
    if (!file.type.startsWith('image/')) {
      result.errors.push({ fileName: file.name, message: 'Not an image' })
      continue
    }

    const displayName = normalizeMenuItemNameFromFileName(file.name)
    if (!displayName) {
      result.errors.push({ fileName: file.name, message: 'Empty name after normalize' })
      continue
    }

    const keyNorm = normalizeMenuItemName(displayName)
    const { data: existing } = await db
      .from('menu_items')
      .select('id, name, image_url')
      .eq('merchant_id', merchantId)
      .eq('name_normalized', keyNorm)
      .maybeSingle()

    const ext = extFromFile(file)
    const pathFor = (itemId: string) => `${merchantId}/${itemId}.${ext}`

    try {
      if (existing) {
        const oldKey = extractObjectPathFromPublicUrl(existing.image_url)
        const newPath = pathFor(existing.id)
        const buf = Buffer.from(await file.arrayBuffer())
        const { error: upErr } = await db.storage.from(BUCKET).upload(newPath, buf, {
          contentType: file.type,
          upsert: true,
        })
        if (upErr) throw new Error(upErr.message)
        const publicUrl = publicUrlForPath(newPath)
        const { error: uErr } = await db
          .from('menu_items')
          .update({ image_url: publicUrl })
          .eq('id', existing.id)
        if (uErr) throw new Error(uErr.message)
        if (oldKey && oldKey !== newPath) {
          await db.storage.from(BUCKET).remove([oldKey]).catch(() => {})
        }
        result.replaced.push({ name: displayName, id: existing.id })
        continue
      }

      const { data: ins, error: iErr } = await db
        .from('menu_items')
        .insert({
          merchant_id: merchantId,
          name: displayName,
          image_url: null,
          price: null,
          category: 'regular',
        })
        .select('id')
        .single()
      if (iErr || !ins) throw new Error(iErr?.message ?? 'insert failed')

      const newId = ins.id as string
      const newPath = pathFor(newId)
      const buf = Buffer.from(await file.arrayBuffer())
      const { error: upErr } = await db.storage.from(BUCKET).upload(newPath, buf, {
        contentType: file.type,
        upsert: true,
      })
      if (upErr) {
        await db.from('menu_items').delete().eq('id', newId)
        throw new Error(upErr.message)
      }
      const publicUrl = publicUrlForPath(newPath)
      const { error: uErr } = await db
        .from('menu_items')
        .update({ image_url: publicUrl })
        .eq('id', newId)
      if (uErr) throw new Error(uErr.message)

      const { data: orderRow } = await db
        .from('menu_items')
        .select('sort_order')
        .eq('merchant_id', merchantId)
        .order('sort_order', { ascending: false })
        .limit(1)
        .maybeSingle()
      const nextOrder = (orderRow?.sort_order as number | undefined) != null
        ? Number(orderRow?.sort_order) + 1
        : 0
      await db.from('menu_items').update({ sort_order: nextOrder }).eq('id', newId)

      result.created.push({ name: displayName, id: newId })
    } catch (e) {
      result.errors.push({
        fileName: file.name,
        message: e instanceof Error ? e.message : 'Unknown error',
      })
    }
  }

  revalidatePath(`/merchants/${merchantId}/menu`)
  return result
}

export type CsvImportResult = { updated: number; errors: { line: number; message: string }[] }

/**
 * 导入 CSV：仅按 id 更新 price；BOM 由调用方可先去 BOM
 * 表头: id,name,price — price 可为空表示 NULL
 */
export async function importMenuItemPricesFromCsv(merchantId: string, csvText: string): Promise<CsvImportResult> {
  await requireAdmin()
  const db = getServiceRoleClient()
  const text = csvText.charCodeAt(0) === 0xfeff ? csvText.slice(1) : csvText
  const lines = text.split(/\r?\n/).map((l) => l.trim()).filter((l) => l.length > 0)
  if (lines.length < 2) {
    return { updated: 0, errors: [{ line: 0, message: 'No data rows' }] }
  }
  const header = lines[0]!.toLowerCase()
  if (!header.includes('id')) {
    return { updated: 0, errors: [{ line: 1, message: 'Expected header with id' }] }
  }

  const errors: { line: number; message: string }[] = []
  let updated = 0
  for (let i = 1; i < lines.length; i++) {
    const line = lines[i]!
    const lineNo = i + 1
    const parts = simpleCsvSplit(line)
    if (parts.length < 1) {
      errors.push({ line: lineNo, message: 'Empty line' })
      continue
    }
    const id = parts[0]!.trim()
    const priceStr = parts[2]?.trim() ?? ''
    if (!/^[0-9a-f-]{36}$/i.test(id)) {
      errors.push({ line: lineNo, message: 'Invalid id' })
      continue
    }
    let price: number | null = null
    if (priceStr !== '' && priceStr.toLowerCase() !== 'null') {
      const n = Number.parseFloat(priceStr)
      if (Number.isNaN(n) || n < 0) {
        errors.push({ line: lineNo, message: 'Invalid price' })
        continue
      }
      price = n
    }
    const { data: own } = await db
      .from('menu_items')
      .select('id')
      .eq('id', id)
      .eq('merchant_id', merchantId)
      .maybeSingle()
    if (!own) {
      errors.push({ line: lineNo, message: 'id not in this merchant' })
      continue
    }
    const { error } = await db
      .from('menu_items')
      .update({ price })
      .eq('id', id)
      .eq('merchant_id', merchantId)
    if (error) {
      errors.push({ line: lineNo, message: error.message })
      continue
    }
    updated++
  }
  revalidatePath(`/merchants/${merchantId}/menu`)
  return { updated, errors }
}

/** 极简 CSV 行解析，支持带引号字段 */
function simpleCsvSplit(line: string): string[] {
  const out: string[] = []
  let cur = ''
  let inQ = false
  for (let i = 0; i < line.length; i++) {
    const c = line[i]!
    if (c === '"') {
      inQ = !inQ
      continue
    }
    if (!inQ && c === ',') {
      out.push(cur)
      cur = ''
      continue
    }
    cur += c
  }
  out.push(cur)
  return out
}

export async function deleteMenuItem(merchantId: string, itemId: string): Promise<void> {
  await requireAdmin()
  const db = getServiceRoleClient()
  const { data: row } = await db
    .from('menu_items')
    .select('image_url')
    .eq('id', itemId)
    .eq('merchant_id', merchantId)
    .maybeSingle()
  if (!row) throw new Error('Not found')
  const key = extractObjectPathFromPublicUrl(row.image_url as string | null)
  const { error } = await db.from('menu_items').delete().eq('id', itemId).eq('merchant_id', merchantId)
  if (error) throw new Error(error.message)
  if (key) await db.storage.from(BUCKET).remove([key]).catch(() => {})
  revalidatePath(`/merchants/${merchantId}/menu`)
}
