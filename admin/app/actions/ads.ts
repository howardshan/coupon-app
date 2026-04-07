'use server'

import { revalidatePath } from 'next/cache'
import { createClient } from '@/lib/supabase/server'
import { getServiceRoleClient } from '@/lib/supabase/service'

// 鉴权：要求 admin 角色，返回 user id
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
  return user
}

// 写操作日志（fire-and-forget，不阻塞主流程）
async function logCampaignEvent(
  campaignId: string | null,
  merchantId: string,
  actorUserId: string,
  eventType: string,
  detail?: Record<string, unknown>
) {
  try {
    const supabase = getServiceRoleClient()
    await supabase.from('ad_campaign_logs').insert({
      campaign_id: campaignId,
      merchant_id: merchantId,
      actor_type: 'admin',
      actor_user_id: actorUserId,
      event_type: eventType,
      detail: detail ?? {},
    })
  } catch (e) {
    console.error('[ads] logCampaignEvent error:', e)
  }
}

// Admin 暂停 campaign
export async function pauseCampaign(campaignId: string, adminNote: string) {
  const user = await requireAdmin()
  const supabase = getServiceRoleClient()

  // 先查 merchant_id（写日志用）
  const { data: campaign } = await supabase
    .from('ad_campaigns')
    .select('merchant_id')
    .eq('id', campaignId)
    .single()

  const { error } = await supabase
    .from('ad_campaigns')
    .update({ status: 'admin_paused', admin_note: adminNote || 'Paused by admin' })
    .eq('id', campaignId)

  if (error) throw new Error(`Failed to pause campaign: ${error.message}`)

  // 写日志
  if (campaign) {
    await logCampaignEvent(campaignId, campaign.merchant_id, user.id, 'admin_paused', {
      reason: adminNote || 'Paused by admin',
    })
  }

  revalidatePath('/ads')
  revalidatePath(`/ads/${campaignId}`)
}

// Admin 恢复 campaign
export async function resumeCampaign(campaignId: string) {
  const user = await requireAdmin()
  const supabase = getServiceRoleClient()

  const { data: campaign } = await supabase
    .from('ad_campaigns')
    .select('merchant_id')
    .eq('id', campaignId)
    .single()

  const { error } = await supabase
    .from('ad_campaigns')
    .update({ status: 'active', admin_note: null })
    .eq('id', campaignId)

  if (error) throw new Error(`Failed to resume campaign: ${error.message}`)

  if (campaign) {
    await logCampaignEvent(campaignId, campaign.merchant_id, user.id, 'admin_resumed')
  }

  revalidatePath('/ads')
  revalidatePath(`/ads/${campaignId}`)
}

// 启用广告位竞价投放（R15: splash 用 toggle_splash_placement RPC 原子操作）
export async function enablePlacement(placement: string) {
  const user = await requireAdmin()
  const supabase = getServiceRoleClient()

  if (placement === 'splash') {
    // 原子事务：改配置 + 批量恢复自动暂停的 campaigns + 写日志
    const { error } = await supabase.rpc('toggle_splash_placement', {
      p_enabled: true,
      p_admin_user_id: user.id,
    })
    if (error) throw new Error(`Failed: ${error.message}`)
  } else {
    const { error } = await supabase
      .from('ad_placement_config')
      .update({ is_enabled: true })
      .eq('placement', placement)
    if (error) throw new Error(`Failed: ${error.message}`)
  }

  revalidatePath('/settings/splash')
  revalidatePath('/ads')
}

// 禁用广告位竞价投放（R15: splash 用 toggle_splash_placement RPC 原子操作）
export async function disablePlacement(placement: string) {
  const user = await requireAdmin()
  const supabase = getServiceRoleClient()

  if (placement === 'splash') {
    // 原子事务：改配置 + 批量暂停 active splash campaigns + 写日志
    const { error } = await supabase.rpc('toggle_splash_placement', {
      p_enabled: false,
      p_admin_user_id: user.id,
    })
    if (error) throw new Error(`Failed: ${error.message}`)
  } else {
    const { error } = await supabase
      .from('ad_placement_config')
      .update({ is_enabled: false })
      .eq('placement', placement)
    if (error) throw new Error(`Failed: ${error.message}`)
  }

  revalidatePath('/settings/splash')
  revalidatePath('/ads')
}
