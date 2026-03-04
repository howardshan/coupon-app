'use server'

import { revalidatePath } from 'next/cache'
import { createClient } from '@/lib/supabase/server'

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

// 审核商家：通过
export async function approveMerchant(merchantId: string, merchantUserId: string) {
  const supabase = await requireAdmin()

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

// 审核商家：拒绝
export async function rejectMerchant(merchantId: string) {
  const supabase = await requireAdmin()

  const { error } = await supabase
    .from('merchants')
    .update({ status: 'rejected' })
    .eq('id', merchantId)

  if (error) throw new Error(error.message)
  revalidatePath('/merchants')
}
