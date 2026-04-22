'use server'

import { getServiceRoleClient } from '@/lib/supabase/service'
import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'

/** 校验当前用户是 admin，否则抛异常 */
async function requireAdmin() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const { data: profile } = await supabase
    .from('users')
    .select('role')
    .eq('id', user.id)
    .single()

  if (profile?.role !== 'admin') throw new Error('Unauthorized')
}

export interface CategoryRow {
  id: number
  name: string
  icon: string | null
  order: number
}

/** 新增分类 */
export async function addCategory(
  name: string,
  icon: string | null,
  order: number,
): Promise<{ data: CategoryRow | null; error: string | null }> {
  try {
    await requireAdmin()
    const client = getServiceRoleClient()
    const { data, error } = await client
      .from('categories')
      .insert({ name, icon, order })
      .select('id, name, icon, order')
      .single()

    if (error) return { data: null, error: error.message }
    return { data: data as CategoryRow, error: null }
  } catch (e) {
    return { data: null, error: e instanceof Error ? e.message : String(e) }
  }
}

/** 更新分类 */
export async function updateCategory(
  id: number,
  name: string,
  icon: string | null,
  order: number,
): Promise<{ error: string | null }> {
  try {
    await requireAdmin()
    const client = getServiceRoleClient()
    const { error } = await client
      .from('categories')
      .update({ name, icon, order })
      .eq('id', id)

    if (error) return { error: error.message }
    return { error: null }
  } catch (e) {
    return { error: e instanceof Error ? e.message : String(e) }
  }
}

/** 删除分类 */
export async function deleteCategory(
  id: number,
): Promise<{ error: string | null }> {
  try {
    await requireAdmin()
    const client = getServiceRoleClient()
    const { error } = await client
      .from('categories')
      .delete()
      .eq('id', id)

    if (error) return { error: error.message }
    return { error: null }
  } catch (e) {
    return { error: e instanceof Error ? e.message : String(e) }
  }
}

/** 交换两个分类的 order（上下移动时调用） */
export async function reorderCategories(
  idA: number, orderA: number,
  idB: number, orderB: number,
): Promise<{ error: string | null }> {
  try {
    await requireAdmin()
    const client = getServiceRoleClient()

    // 先把 A 改成临时值避免唯一约束冲突（如果有的话）
    const [r1, r2] = await Promise.all([
      client.from('categories').update({ order: orderB }).eq('id', idA),
      client.from('categories').update({ order: orderA }).eq('id', idB),
    ])

    if (r1.error) return { error: r1.error.message }
    if (r2.error) return { error: r2.error.message }
    return { error: null }
  } catch (e) {
    return { error: e instanceof Error ? e.message : String(e) }
  }
}

/** 上传分类图标到 admin-uploads/category-icons/，返回公开 URL */
export async function uploadCategoryIcon(
  formData: FormData,
): Promise<{ url: string | null; error: string | null }> {
  try {
    await requireAdmin()

    const file = formData.get('file') as File | null
    if (!file || file.size === 0) return { url: null, error: 'No file provided' }

    // 最大 2MB
    if (file.size > 2 * 1024 * 1024) {
      return { url: null, error: 'File too large (max 2MB)' }
    }

    const ext = file.name.split('.').pop()?.toLowerCase() || 'png'
    const allowed = ['jpg', 'jpeg', 'png', 'webp', 'svg']
    if (!allowed.includes(ext)) {
      return { url: null, error: 'Only JPG / PNG / WebP / SVG allowed' }
    }

    // 文件名：category-icons/{timestamp}-{random}.{ext}
    const path = `category-icons/${Date.now()}-${Math.random().toString(36).slice(2)}.${ext}`

    const arrayBuffer = await file.arrayBuffer()
    const buffer = Buffer.from(arrayBuffer)

    const client = getServiceRoleClient()
    const { error: uploadError } = await client.storage
      .from('admin-uploads')
      .upload(path, buffer, {
        contentType: file.type || `image/${ext}`,
        upsert: true,
      })

    if (uploadError) return { url: null, error: uploadError.message }

    const { data } = client.storage.from('admin-uploads').getPublicUrl(path)
    return { url: data.publicUrl, error: null }
  } catch (e) {
    return { url: null, error: e instanceof Error ? e.message : String(e) }
  }
}
