import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getServiceRoleClient } from '@/lib/supabase/service'
import RegionsClient from './regions-client'

export const dynamic = 'force-dynamic'

export default async function RegionsPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  const { data: profile } = await supabase
    .from('users')
    .select('role')
    .eq('id', user!.id)
    .single()

  if (profile?.role !== 'admin') redirect('/dashboard')

  const adminSupabase = getServiceRoleClient()

  // 获取所有地区数据
  const { data: areas } = await adminSupabase
    .from('service_areas')
    .select('*')
    .order('state_name')
    .order('metro_name')
    .order('sort_order')

  // 获取所有商家的 city（用于检测未匹配城市）
  const { data: merchants } = await adminSupabase
    .from('merchants')
    .select('city')
    .not('city', 'is', null)
    .neq('city', '')

  // 计算未匹配城市：merchants 中有但 service_areas 中没有的 city
  const serviceCities = new Set(
    (areas ?? [])
      .filter(a => a.level === 'city' && a.is_active)
      .map(a => a.city_name?.toLowerCase())
  )

  const merchantCityCounts: Record<string, number> = {}
  for (const m of (merchants ?? [])) {
    const city = m.city as string
    if (!serviceCities.has(city.toLowerCase())) {
      merchantCityCounts[city] = (merchantCityCounts[city] ?? 0) + 1
    }
  }

  const unmatchedCities = Object.entries(merchantCityCounts)
    .map(([city, count]) => ({ city, merchantCount: count }))
    .sort((a, b) => b.merchantCount - a.merchantCount)

  return (
    <RegionsClient
      initialAreas={areas ?? []}
      unmatchedCities={unmatchedCities}
    />
  )
}
