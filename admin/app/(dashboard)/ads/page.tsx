import { createClient } from '@/lib/supabase/server'
import { getServiceRoleClient } from '@/lib/supabase/service'
import { redirect } from 'next/navigation'
import Link from 'next/link'
import CampaignActions from './campaign-actions'

export const dynamic = 'force-dynamic'

// 状态徽章样式映射
function statusBadge(status: string) {
  const map: Record<string, string> = {
    active: 'bg-green-100 text-green-700',
    paused: 'bg-yellow-100 text-yellow-700',
    admin_paused: 'bg-red-100 text-red-700',
    completed: 'bg-gray-100 text-gray-600',
    draft: 'bg-blue-100 text-blue-700',
    budget_exhausted: 'bg-orange-100 text-orange-700',
  }
  return map[status] ?? 'bg-gray-100 text-gray-600'
}

export default async function AdsPage({
  searchParams,
}: {
  searchParams: Promise<{ status?: string }>
}) {
  const params = await searchParams

  // 鉴权
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  const { data: profile } = await supabase.from('users').select('role').eq('id', user!.id).single()
  if (profile?.role !== 'admin') redirect('/dashboard')

  // 查询 campaigns（service role 确保可读）
  const serviceClient = getServiceRoleClient()
  let query = serviceClient
    .from('ad_campaigns')
    .select('*, merchants(id, name), ad_accounts(balance)')
    .order('created_at', { ascending: false })
    .limit(200)

  if (params.status) {
    query = query.eq('status', params.status)
  }

  const { data: campaigns, error } = await query

  // 查询今日消费（聚合 ad_daily_stats）
  const today = new Date().toISOString().slice(0, 10)
  const { data: todayStats } = await serviceClient
    .from('ad_daily_stats')
    .select('campaign_id, spend')
    .eq('stat_date', today)

  // 构建今日消费 map
  const todaySpendMap: Record<string, number> = {}
  for (const s of (todayStats ?? [])) {
    todaySpendMap[s.campaign_id] = (todaySpendMap[s.campaign_id] ?? 0) + Number(s.spend ?? 0)
  }

  // 所有可能的状态（用于过滤标签）
  const statuses = ['active', 'paused', 'admin_paused', 'draft', 'completed', 'budget_exhausted']

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold text-gray-900">Ad Campaigns</h1>
        {/* 子导航 */}
        <div className="flex items-center gap-2 text-sm">
          <Link href="/ads" className="text-blue-600 hover:underline font-medium">Campaigns</Link>
          <span className="text-gray-300">|</span>
          <Link href="/ads/accounts" className="text-gray-500 hover:text-blue-600">Accounts</Link>
          <span className="text-gray-300">|</span>
          <Link href="/ads/revenue" className="text-gray-500 hover:text-blue-600">Revenue</Link>
        </div>
      </div>

      {/* 状态过滤 */}
      <div className="flex items-center gap-1 mb-4 flex-wrap">
        <a
          href="/ads"
          className={`px-2 py-1 rounded text-xs font-medium transition-colors ${
            !params.status ? 'bg-blue-100 text-blue-700' : 'bg-gray-100 text-gray-600 hover:bg-gray-200'
          }`}
        >
          All
        </a>
        {statuses.map(s => (
          <a
            key={s}
            href={`/ads?status=${s}`}
            className={`px-2 py-1 rounded text-xs font-medium transition-colors ${
              params.status === s ? 'bg-blue-100 text-blue-700' : 'bg-gray-100 text-gray-600 hover:bg-gray-200'
            }`}
          >
            {s.replace('_', ' ')}
          </a>
        ))}
      </div>

      {error && (
        <div className="bg-red-50 border border-red-200 rounded-lg p-4 mb-4 text-sm text-red-700">
          {error.message}
        </div>
      )}

      {/* Campaign 表格 */}
      <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
        <table className="w-full text-sm">
          <thead className="bg-gray-50 border-b border-gray-200">
            <tr>
              <th className="text-left px-4 py-3 font-medium text-gray-600">Campaign ID</th>
              <th className="text-left px-4 py-3 font-medium text-gray-600">Merchant</th>
              <th className="text-left px-4 py-3 font-medium text-gray-600">Placement</th>
              <th className="text-right px-4 py-3 font-medium text-gray-600">Bid</th>
              <th className="text-right px-4 py-3 font-medium text-gray-600">Daily Budget</th>
              <th className="text-right px-4 py-3 font-medium text-gray-600">Today Spend</th>
              <th className="text-right px-4 py-3 font-medium text-gray-600">Balance</th>
              <th className="text-left px-4 py-3 font-medium text-gray-600">Status</th>
              <th className="text-left px-4 py-3 font-medium text-gray-600">Actions</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100">
            {(campaigns ?? []).map((c: any) => {
              const todaySpend = todaySpendMap[c.id] ?? 0
              const balance = c.ad_accounts?.balance ?? 0
              return (
                <tr key={c.id} className="hover:bg-gray-50">
                  <td className="px-4 py-3">
                    <Link href={`/ads/${c.id}`} className="text-blue-600 hover:underline font-mono text-xs">
                      {c.id.slice(0, 8)}...
                    </Link>
                  </td>
                  <td className="px-4 py-3">
                    <Link href={`/merchants/${c.merchants?.id}`} className="text-blue-600 hover:underline font-medium">
                      {c.merchants?.name ?? '—'}
                    </Link>
                  </td>
                  <td className="px-4 py-3 text-gray-700">{c.placement ?? '—'}</td>
                  <td className="px-4 py-3 text-right font-medium text-gray-900">
                    ${Number(c.bid_price ?? 0).toFixed(2)}
                  </td>
                  <td className="px-4 py-3 text-right text-gray-700">
                    ${Number(c.daily_budget ?? 0).toFixed(2)}
                  </td>
                  <td className="px-4 py-3 text-right text-gray-700">
                    ${todaySpend.toFixed(2)}
                  </td>
                  <td className="px-4 py-3 text-right text-gray-700">
                    ${Number(balance).toFixed(2)}
                  </td>
                  <td className="px-4 py-3">
                    <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${statusBadge(c.status)}`}>
                      {c.status?.replace('_', ' ') ?? '—'}
                    </span>
                  </td>
                  <td className="px-4 py-3">
                    <CampaignActions campaignId={c.id} status={c.status} />
                  </td>
                </tr>
              )
            })}
          </tbody>
        </table>
        {(!campaigns || campaigns.length === 0) && (
          <p className="text-center text-gray-400 py-8">No campaigns found</p>
        )}
      </div>
    </div>
  )
}
