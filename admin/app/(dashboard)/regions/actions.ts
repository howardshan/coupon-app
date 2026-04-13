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
}

/** 添加地区 */
export async function addServiceArea(
  level: 'state' | 'metro' | 'city',
  stateName: string,
  metroName: string | null,
  cityName: string | null,
  sortOrder: number = 0,
) {
  await requireAdmin()
  const supabase = getServiceRoleClient()

  const { error } = await supabase
    .from('service_areas')
    .insert({
      level,
      state_name: stateName.trim(),
      metro_name: metroName?.trim() || null,
      city_name: cityName?.trim() || null,
      sort_order: sortOrder,
    })

  if (error) throw new Error(error.message)
  revalidatePath('/regions')
}

/** 更新地区 */
export async function updateServiceArea(
  id: string,
  updates: {
    state_name?: string
    metro_name?: string | null
    city_name?: string | null
    sort_order?: number
    is_active?: boolean
  },
) {
  await requireAdmin()
  const supabase = getServiceRoleClient()

  const { error } = await supabase
    .from('service_areas')
    .update({ ...updates, updated_at: new Date().toISOString() })
    .eq('id', id)

  if (error) throw new Error(error.message)
  revalidatePath('/regions')
}

/** 删除地区 */
export async function deleteServiceArea(id: string) {
  await requireAdmin()
  const supabase = getServiceRoleClient()

  const { error } = await supabase
    .from('service_areas')
    .delete()
    .eq('id', id)

  if (error) throw new Error(error.message)
  revalidatePath('/regions')
}

/** 一键添加城市到指定 metro（用于未匹配城市快速添加） */
export async function addCityToMetro(
  cityName: string,
  metroName: string,
  stateName: string,
) {
  await requireAdmin()
  const supabase = getServiceRoleClient()

  // 获取该 metro 下最大 sort_order，新城市排在最后
  const { data: existing } = await supabase
    .from('service_areas')
    .select('sort_order')
    .eq('level', 'city')
    .eq('state_name', stateName)
    .eq('metro_name', metroName)
    .order('sort_order', { ascending: false })
    .limit(1)

  const nextSort = (existing?.[0]?.sort_order ?? -1) + 1

  const { error } = await supabase
    .from('service_areas')
    .insert({
      level: 'city',
      state_name: stateName.trim(),
      metro_name: metroName.trim(),
      city_name: cityName.trim(),
      sort_order: nextSort,
    })

  if (error) throw new Error(error.message)
  revalidatePath('/regions')
}
