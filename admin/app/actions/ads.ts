'use server'

import { revalidatePath } from 'next/cache'
import { createClient } from '@/lib/supabase/server'
import { getServiceRoleClient } from '@/lib/supabase/service'

// 鉴权：要求 admin 角色
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

// Admin 暂停 campaign
export async function pauseCampaign(campaignId: string, adminNote: string) {
  await requireAdmin()
  const supabase = getServiceRoleClient()

  const { error } = await supabase
    .from('ad_campaigns')
    .update({ status: 'admin_paused', admin_note: adminNote || 'Paused by admin' })
    .eq('id', campaignId)

  if (error) throw new Error(`Failed to pause campaign: ${error.message}`)
  revalidatePath('/ads')
  revalidatePath(`/ads/${campaignId}`)
}

// Admin 恢复 campaign
export async function resumeCampaign(campaignId: string) {
  await requireAdmin()
  const supabase = getServiceRoleClient()

  const { error } = await supabase
    .from('ad_campaigns')
    .update({ status: 'active', admin_note: null })
    .eq('id', campaignId)

  if (error) throw new Error(`Failed to resume campaign: ${error.message}`)
  revalidatePath('/ads')
  revalidatePath(`/ads/${campaignId}`)
}
