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

// 更新用户角色
export async function updateUserRole(userId: string, role: 'user' | 'merchant' | 'admin') {
  const supabase = await requireAdmin()

  const { error } = await supabase
    .from('users')
    .update({ role })
    .eq('id', userId)

  if (error) throw new Error(error.message)
  revalidatePath('/users')
}

// 审核商家：通过（使用 service_role 写库，避免 merchant_staff RLS 无限递归）
export async function approveMerchant(merchantId: string, merchantUserId: string) {
  await requireAdmin()
  const supabase = getServiceRoleClient()

  // 更新商家状态
  const { error: merchantError } = await supabase
    .from('merchants')
    .update({ status: 'approved' })
    .eq('id', merchantId)

  if (merchantError) throw new Error(merchantError.message)

  // 同时把对应用户的 role 升级为 merchant
  await supabase
    .from('users')
    .update({ role: 'merchant' })
    .eq('id', merchantUserId)

  revalidatePath('/merchants')
}

// 审核商家：拒绝（使用 service_role 写库，避免 merchant_staff RLS 无限递归）
export async function rejectMerchant(merchantId: string, rejectionReason?: string | null) {
  await requireAdmin()

  const supabase = getServiceRoleClient()
  const { error } = await supabase
    .from('merchants')
    .update({
      status: 'rejected',
      rejection_reason: rejectionReason?.trim() || null,
    })
    .eq('id', merchantId)

  if (error) throw new Error(error.message)
  revalidatePath('/merchants')
  revalidatePath(`/merchants/${merchantId}`)
}

// 撤销审批：将已通过的商家改回待审核（使用 service_role 写库，避免 RLS 递归）
export async function revokeMerchantApproval(merchantId: string) {
  await requireAdmin()

  const supabase = getServiceRoleClient()
  const { error } = await supabase
    .from('merchants')
    .update({
      status: 'pending',
      rejection_reason: null,
    })
    .eq('id', merchantId)

  if (error) throw new Error(error.message)
  revalidatePath('/merchants')
  revalidatePath(`/merchants/${merchantId}`)
}

// 更新 Deal 首页展示排序（null = 不在首页展示）
export async function updateDealSortOrder(dealId: string, sortOrder: number | null) {
  const supabase = await requireAdmin()

  const { error } = await supabase
    .from('deals')
    .update({ sort_order: sortOrder })
    .eq('id', dealId)

  if (error) throw new Error(error.message)
  revalidatePath('/deals')
}

// Deal 审核：上架/下架（同时设置 is_active 与 deal_status，商家端按 deal_status 显示）
// 使用 service_role 客户端执行更新，避免 RLS 中 merchants ↔ merchant_staff 递归
export async function setDealActive(dealId: string, active: boolean) {
  await requireAdmin()

  const supabase = getServiceRoleClient()
  const { error } = await supabase
    .from('deals')
    .update({
      is_active: active,
      deal_status: active ? 'active' : 'inactive',
      ...(active ? { published_at: new Date().toISOString() } : {}),
    })
    .eq('id', dealId)

  if (error) throw new Error(error.message)
  revalidatePath('/deals')
  revalidatePath(`/deals/${dealId}`)
}
