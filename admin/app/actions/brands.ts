'use server'

import { revalidatePath } from 'next/cache'
import { createClient } from '@/lib/supabase/server'
import { getServiceRoleClient } from '@/lib/supabase/service'

async function requireAdmin() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) throw new Error('Unauthorized')

  const { data: profile } = await supabase
    .from('users')
    .select('role')
    .eq('id', user.id)
    .single()

  if (profile?.role !== 'admin') throw new Error('Forbidden')
  return supabase
}

// 强制禁用员工账号
export async function toggleStaffActive(staffId: string, isActive: boolean) {
  await requireAdmin()
  const supabase = getServiceRoleClient()

  const { error } = await supabase
    .from('merchant_staff')
    .update({ is_active: isActive })
    .eq('id', staffId)

  if (error) throw new Error(error.message)
  revalidatePath('/merchants')
}

// 添加 Brand Admin（通过 email 查用户，插入 brand_admins）
export async function addBrandAdmin(brandId: string, email: string, role: 'owner' | 'admin') {
  await requireAdmin()
  const supabase = getServiceRoleClient()

  // 通过 email 查用户
  const { data: user, error: userError } = await supabase
    .from('users')
    .select('id')
    .eq('email', email.trim().toLowerCase())
    .maybeSingle()

  if (userError) throw new Error(userError.message)
  if (!user) throw new Error(`User not found: ${email}`)

  const { error } = await supabase
    .from('brand_admins')
    .insert({ brand_id: brandId, user_id: user.id, role })

  if (error) {
    if (error.code === '23505') throw new Error('This user is already a brand admin')
    throw new Error(error.message)
  }

  revalidatePath(`/brands/${brandId}`)
}

// 移除 Brand Admin
export async function removeBrandAdmin(brandAdminId: string, brandId: string) {
  await requireAdmin()
  const supabase = getServiceRoleClient()

  const { error } = await supabase
    .from('brand_admins')
    .delete()
    .eq('id', brandAdminId)

  if (error) throw new Error(error.message)
  revalidatePath(`/brands/${brandId}`)
}

// 关联门店到 Brand
export async function addStoreToBrand(brandId: string, merchantId: string) {
  await requireAdmin()
  const supabase = getServiceRoleClient()

  const { error } = await supabase
    .from('merchants')
    .update({ brand_id: brandId })
    .eq('id', merchantId)

  if (error) throw new Error(error.message)
  revalidatePath(`/brands/${brandId}`)
  revalidatePath('/merchants')
}

// 解除门店与 Brand 的关联
export async function removeStoreFromBrand(merchantId: string, brandId: string) {
  await requireAdmin()
  const supabase = getServiceRoleClient()

  const { error } = await supabase
    .from('merchants')
    .update({ brand_id: null })
    .eq('id', merchantId)

  if (error) throw new Error(error.message)
  revalidatePath(`/brands/${brandId}`)
  revalidatePath('/merchants')
}
