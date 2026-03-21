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

  // 读取全局免费期月数，计算免费期截止时间
  const { data: config } = await supabase
    .from('platform_commission_config')
    .select('free_months')
    .single()
  const freeMonths = config?.free_months ?? 3
  const commissionFreeUntil = new Date()
  commissionFreeUntil.setMonth(commissionFreeUntil.getMonth() + freeMonths)

  // 更新商家状态和免费期截止时间
  const { error: merchantError } = await supabase
    .from('merchants')
    .update({
      status: 'approved',
      commission_free_until: commissionFreeUntil.toISOString(),
    })
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

// 更新全局抽成配置（唯一一行，先查 id 再 update）
export async function updateCommissionConfig(data: {
  free_months: number
  fixed_date_rate: number
  short_after_purchase_rate: number
  long_after_purchase_rate: number
  stripe_processing_rate: number
  stripe_flat_fee: number
  effective_from: string | null
  effective_to: string | null
}) {
  await requireAdmin()
  const supabase = getServiceRoleClient()

  const { data: existing } = await supabase
    .from('platform_commission_config')
    .select('id')
    .single()

  if (!existing) throw new Error('Commission config not found')

  const { error } = await supabase
    .from('platform_commission_config')
    .update({
      free_months: data.free_months,
      fixed_date_rate: data.fixed_date_rate,
      short_after_purchase_rate: data.short_after_purchase_rate,
      long_after_purchase_rate: data.long_after_purchase_rate,
      stripe_processing_rate: data.stripe_processing_rate,
      stripe_flat_fee: data.stripe_flat_fee,
      effective_from: data.effective_from,
      effective_to: data.effective_to,
    })
    .eq('id', existing.id)

  if (error) throw new Error(error.message)
  revalidatePath('/finance')
}

// 按商家单独设置完整抽成配置（费率 + 免费期）
export async function updateMerchantCommission(merchantId: string, data: {
  commission_free_until:     string | null
  commission_fixed_date_rate: number | null
  commission_short_rate:     number | null
  commission_long_rate:      number | null
  commission_stripe_rate:    number | null
  commission_stripe_flat_fee: number | null
  commission_effective_from: string | null
  commission_effective_to:   string | null
}) {
  await requireAdmin()
  const supabase = getServiceRoleClient()

  const { error } = await supabase
    .from('merchants')
    .update(data)
    .eq('id', merchantId)

  if (error) throw new Error(error.message)
  revalidatePath(`/merchants/${merchantId}`)
}

// 保留旧函数以兼容（内部调用新函数）
export async function updateMerchantCommissionFreeUntil(merchantId: string, freeUntil: string | null) {
  await requireAdmin()
  const supabase = getServiceRoleClient()
  const { error } = await supabase
    .from('merchants')
    .update({ commission_free_until: freeUntil })
    .eq('id', merchantId)
  if (error) throw new Error(error.message)
  revalidatePath(`/merchants/${merchantId}`)
}

// 发送客服回复（admin → merchant）
export async function sendSupportReply(conversationId: string, content: string) {
  await requireAdmin()
  const supabase = getServiceRoleClient()

  const { error } = await supabase
    .from('support_messages')
    .insert({ conversation_id: conversationId, sender_role: 'admin', content })

  if (error) throw new Error(error.message)
}

// 关闭客服会话
export async function closeSupportConversation(conversationId: string) {
  await requireAdmin()
  const supabase = getServiceRoleClient()

  const { error } = await supabase
    .from('support_conversations')
    .update({ status: 'closed' })
    .eq('id', conversationId)

  if (error) throw new Error(error.message)
  revalidatePath('/support')
}

// 重新开启客服会话
export async function reopenSupportConversation(conversationId: string) {
  await requireAdmin()
  const supabase = getServiceRoleClient()

  const { error } = await supabase
    .from('support_conversations')
    .update({ status: 'open' })
    .eq('id', conversationId)

  if (error) throw new Error(error.message)
  revalidatePath('/support')
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

// Deal 审核：驳回（设置 deal_status = rejected，保存 deal 快照 + 驳回历史记录）
export async function rejectDeal(dealId: string, rejectionReason?: string | null) {
  const userSupabase = await requireAdmin()
  const { data: { user } } = await userSupabase.auth.getUser()

  const supabase = getServiceRoleClient()
  const reason = rejectionReason?.trim() || null

  // 先查询 deal 当前全量数据作为快照
  const { data: dealSnapshot } = await supabase
    .from('deals')
    .select(`
      id, merchant_id, title, description, category,
      original_price, discount_price, discount_label, discount_percent,
      image_urls, stock_limit, total_sold, rating, review_count,
      is_active, is_featured, deal_status, rejection_reason,
      refund_policy, address, dishes, merchant_hours,
      package_contents, usage_notes, usage_days, max_per_person,
      is_stackable, validity_type, validity_days,
      expires_at, published_at, applicable_merchant_ids,
      created_at, updated_at,
      merchants(name, address, phone, brand_id, brands(name)),
      deal_images(id, image_url, sort_order, is_primary)
    `)
    .eq('id', dealId)
    .single()

  // 更新 deal 状态和最新驳回理由
  const { error: updateError } = await supabase
    .from('deals')
    .update({
      is_active: false,
      deal_status: 'rejected',
      rejection_reason: reason,
    })
    .eq('id', dealId)

  if (updateError) throw new Error(updateError.message)

  // 插入驳回历史记录（含 deal 快照）
  if (reason) {
    const { error: insertError } = await supabase
      .from('deal_rejections')
      .insert({
        deal_id: dealId,
        reason,
        rejected_by: user?.id ?? null,
        deal_snapshot: dealSnapshot ?? null,
      })

    if (insertError) throw new Error(insertError.message)
  }

  revalidatePath('/deals')
  revalidatePath(`/deals/${dealId}`)
}

// 封禁用户（设置 ban_duration）
export async function banUser(userId: string, durationDays: number) {
  await requireAdmin()
  const supabase = getServiceRoleClient()

  const { error } = await supabase.auth.admin.updateUserById(userId, {
    ban_duration: `${durationDays * 24}h`,
  })

  if (error) throw new Error(error.message)
  revalidatePath(`/users/${userId}`)
  revalidatePath('/users')
}

// 永久封禁用户
export async function banUserPermanently(userId: string) {
  await requireAdmin()
  const supabase = getServiceRoleClient()

  const { error } = await supabase.auth.admin.updateUserById(userId, {
    ban_duration: `${365 * 100 * 24}h`,
  })

  if (error) throw new Error(error.message)
  revalidatePath(`/users/${userId}`)
  revalidatePath('/users')
}

// 解除封禁
export async function unbanUser(userId: string) {
  await requireAdmin()
  const supabase = getServiceRoleClient()

  const { error } = await supabase.auth.admin.updateUserById(userId, {
    ban_duration: 'none',
  })

  if (error) throw new Error(error.message)
  revalidatePath(`/users/${userId}`)
  revalidatePath('/users')
}
