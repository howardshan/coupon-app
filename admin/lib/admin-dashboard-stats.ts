import { getServiceRoleClient } from '@/lib/supabase/service'

type ServiceDb = ReturnType<typeof getServiceRoleClient>

export type PlatformSnapshot = {
  totalUsers: number
  totalMerchants: number
  totalDeals: number
  totalBrands: number
  ordersLast7Days: number
}

/** 平台级累计与近 7 日订单量（UTC 日起算），供 Overview 快照区 */
export async function fetchPlatformSnapshot(db: ServiceDb): Promise<PlatformSnapshot> {
  const since = new Date()
  since.setUTCDate(since.getUTCDate() - 7)
  since.setUTCHours(0, 0, 0, 0)
  const sinceIso = since.toISOString()

  const [users, merchants, deals, brands, orders7] = await Promise.all([
    db.from('users').select('id', { count: 'exact', head: true }),
    db.from('merchants').select('id', { count: 'exact', head: true }),
    db.from('deals').select('id', { count: 'exact', head: true }),
    db.from('brands').select('id', { count: 'exact', head: true }),
    db.from('orders').select('id', { count: 'exact', head: true }).gte('created_at', sinceIso),
  ])

  return {
    totalUsers: users.count ?? 0,
    totalMerchants: merchants.count ?? 0,
    totalDeals: deals.count ?? 0,
    totalBrands: brands.count ?? 0,
    ordersLast7Days: orders7.count ?? 0,
  }
}
