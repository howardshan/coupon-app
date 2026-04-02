import { createClient } from '@/lib/supabase/server'
import { getServiceRoleClient } from '@/lib/supabase/service'
import { redirect } from 'next/navigation'
import Link from 'next/link'

export const dynamic = 'force-dynamic'

export default async function AdsRevenuePage() {
  // 鉴权
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  const { data: profile } = await supabase.from('users').select('role').eq('id', user!.id).single()
  if (profile?.role !== 'admin') redirect('/dashboard')

  const serviceClient = getServiceRoleClient()

  // 最近 30 天的每日统计（按天聚合）
  const thirtyDaysAgo = new Date()
  thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30)
  const fromDate = thirtyDaysAgo.toISOString().slice(0, 10)

  const { data: dailyStats, error } = await serviceClient
    .from('ad_daily_stats')
    .select('stat_date, spend, impressions, clicks')
    .gte('stat_date', fromDate)
    .order('stat_date', { ascending: false })

  // 按天聚合（可能有多个 campaign 的记录）
  const dailyAgg: Record<string, { spend: number; impressions: number; clicks: number }> = {}
  for (const s of (dailyStats ?? [])) {
    const date = s.stat_date
    if (!dailyAgg[date]) {
      dailyAgg[date] = { spend: 0, impressions: 0, clicks: 0 }
    }
    dailyAgg[date].spend += Number(s.spend ?? 0)
    dailyAgg[date].impressions += Number(s.impressions ?? 0)
    dailyAgg[date].clicks += Number(s.clicks ?? 0)
  }

  const sortedDays = Object.entries(dailyAgg).sort((a, b) => b[0].localeCompare(a[0]))

  // 今日收入
  const today = new Date().toISOString().slice(0, 10)
  const todayRevenue = dailyAgg[today]?.spend ?? 0

  // 本月收入
  const currentMonth = today.slice(0, 7) // YYYY-MM
  const monthRevenue = sortedDays
    .filter(([date]) => date.startsWith(currentMonth))
    .reduce((sum, [, d]) => sum + d.spend, 0)

  // 活跃 campaign 数
  const { count: activeCampaignCount } = await serviceClient
    .from('ad_campaigns')
    .select('id', { count: 'exact', head: true })
    .eq('status', 'active')

  // 活跃商家数（有 active campaign 的 distinct merchant）
  const { data: activeMerchants } = await serviceClient
    .from('ad_campaigns')
    .select('merchant_id')
    .eq('status', 'active')

  const uniqueMerchants = new Set((activeMerchants ?? []).map(c => c.merchant_id))

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold text-gray-900">Ad Revenue</h1>
        {/* 子导航 */}
        <div className="flex items-center gap-2 text-sm">
          <Link href="/ads" className="text-gray-500 hover:text-blue-600">Campaigns</Link>
          <span className="text-gray-300">|</span>
          <Link href="/ads/accounts" className="text-gray-500 hover:text-blue-600">Accounts</Link>
          <span className="text-gray-300">|</span>
          <Link href="/ads/revenue" className="text-blue-600 hover:underline font-medium">Revenue</Link>
        </div>
      </div>

      {/* 汇总卡片 */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-4 mb-6">
        <div className="bg-white rounded-xl border border-gray-200 p-4">
          <p className="text-xs font-medium text-gray-500 uppercase tracking-wide">Today Revenue</p>
          <p className="text-2xl font-bold text-blue-700 mt-1">${todayRevenue.toFixed(2)}</p>
        </div>
        <div className="bg-white rounded-xl border border-gray-200 p-4">
          <p className="text-xs font-medium text-gray-500 uppercase tracking-wide">This Month</p>
          <p className="text-2xl font-bold text-green-700 mt-1">${monthRevenue.toFixed(2)}</p>
        </div>
        <div className="bg-white rounded-xl border border-gray-200 p-4">
          <p className="text-xs font-medium text-gray-500 uppercase tracking-wide">Active Campaigns</p>
          <p className="text-2xl font-bold text-gray-900 mt-1">{activeCampaignCount ?? 0}</p>
        </div>
        <div className="bg-white rounded-xl border border-gray-200 p-4">
          <p className="text-xs font-medium text-gray-500 uppercase tracking-wide">Active Merchants</p>
          <p className="text-2xl font-bold text-gray-900 mt-1">{uniqueMerchants.size}</p>
        </div>
      </div>

      {error && (
        <div className="bg-red-50 border border-red-200 rounded-lg p-4 mb-4 text-sm text-red-700">
          {error.message}
        </div>
      )}

      {/* 每日收入表格 */}
      <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
        <table className="w-full text-sm">
          <thead className="bg-gray-50 border-b border-gray-200">
            <tr>
              <th className="text-left px-4 py-3 font-medium text-gray-600">Date</th>
              <th className="text-right px-4 py-3 font-medium text-gray-600">Revenue</th>
              <th className="text-right px-4 py-3 font-medium text-gray-600">Impressions</th>
              <th className="text-right px-4 py-3 font-medium text-gray-600">Clicks</th>
              <th className="text-right px-4 py-3 font-medium text-gray-600">CTR</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100">
            {sortedDays.map(([date, d]) => {
              const ctr = d.impressions > 0 ? ((d.clicks / d.impressions) * 100).toFixed(2) : '0.00'
              return (
                <tr key={date} className="hover:bg-gray-50">
                  <td className="px-4 py-3 text-gray-900 font-medium">{date}</td>
                  <td className="px-4 py-3 text-right font-medium text-gray-900">${d.spend.toFixed(2)}</td>
                  <td className="px-4 py-3 text-right text-gray-700">{d.impressions.toLocaleString()}</td>
                  <td className="px-4 py-3 text-right text-gray-700">{d.clicks.toLocaleString()}</td>
                  <td className="px-4 py-3 text-right text-gray-700">{ctr}%</td>
                </tr>
              )
            })}
          </tbody>
        </table>
        {sortedDays.length === 0 && (
          <p className="text-center text-gray-400 py-8">No revenue data in the last 30 days</p>
        )}
      </div>
    </div>
  )
}
