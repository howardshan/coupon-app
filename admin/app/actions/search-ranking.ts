'use server'

import { createClient } from '@/lib/supabase/server'
import { getServiceRoleClient } from '@/lib/supabase/service'
import { revalidatePath } from 'next/cache'

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

export interface RankingConfig {
  distance_weight: number
  rating_weight: number
  click_weight: number
  order_weight: number
  refund_weight: number
  updated_at: string
}

export async function getRankingConfig(): Promise<RankingConfig> {
  const supabase = await createClient()
  const { data, error } = await supabase
    .from('search_ranking_config')
    .select('distance_weight, rating_weight, click_weight, order_weight, refund_weight, updated_at')
    .single()

  if (error || !data) {
    return {
      distance_weight: 60,
      rating_weight: 40,
      click_weight: 20,
      order_weight: 10,
      refund_weight: 20,
      updated_at: '',
    }
  }
  return data as RankingConfig
}

export async function updateRankingConfig(
  config: Omit<RankingConfig, 'updated_at'>
): Promise<{ success: boolean; error?: string }> {
  try {
    await requireAdmin()

    const { distance_weight, rating_weight, click_weight, order_weight, refund_weight } = config

    if ([distance_weight, rating_weight, click_weight, order_weight, refund_weight].some(w => w < 0)) {
      return { success: false, error: 'All weights must be non-negative' }
    }
    if (distance_weight + rating_weight + click_weight + order_weight + refund_weight === 0) {
      return { success: false, error: 'At least one weight must be greater than 0' }
    }

    const supabase = getServiceRoleClient()
    const { error } = await supabase
      .from('search_ranking_config')
      .update({
        distance_weight,
        rating_weight,
        click_weight,
        order_weight,
        refund_weight,
        updated_at: new Date().toISOString(),
      })
      .eq('id', 1)

    if (error) return { success: false, error: error.message }

    revalidatePath('/settings/search-ranking')
    return { success: true }
  } catch (e) {
    return { success: false, error: (e as Error).message }
  }
}
