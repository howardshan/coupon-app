import { createClient } from '@/lib/supabase/server'
import { getServiceRoleClient } from '@/lib/supabase/service'
import { redirect, notFound } from 'next/navigation'
import Link from 'next/link'
import CampaignDetailActions from './campaign-detail-actions'

export const dynamic = 'force-dynamic'

// 状态徽章样式
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

export default async function CampaignDetailPage({
  params,
}: {
  params: Promise<{ id: string }>
}) {
  const { id } = await params

  // 鉴权
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  const { data: profile } = await supabase.from('users').select('role').eq('id', user!.id).single()
  if (profile?.role !== 'admin') redirect('/dashboard')

  const serviceClient = getServiceRoleClient()

  // 查询 campaign 详情
  const { data: campaign } = await serviceClient
    .from('ad_campaigns')
    .select('*, merchants(id, name), ad_accounts(balance, total_deposit, total_spend)')
    .eq('id', id)
    .single()

  if (!campaign) notFound()

  // 查询该 campaign 的每日统计
  const { data: dailyStats } = await serviceClient
    .from('ad_daily_stats')
    .select('*')
    .eq('campaign_id', id)
    .order('stat_date', { ascending: false })
    .limit(30)

  // 汇总统计
  const totalSpend = (dailyStats ?? []).reduce((sum: number, s: any) => sum + Number(s.spend ?? 0), 0)
  const totalImpressions = (dailyStats ?? []).reduce((sum: number, s: any) => sum + Number(s.impressions ?? 0), 0)
  const totalClicks = (dailyStats ?? []).reduce((sum: number, s: any) => sum + Number(s.clicks ?? 0), 0)

  return (
    <div>
      {/* 面包屑 */}
      <div className="flex items-center gap-2 text-sm text-gray-500 mb-4">
        <Link href="/ads" className="hover:text-blue-600">Ad Campaigns</Link>
        <span>/</span>
        <span className="text-gray-900 font-medium">{campaign.id.slice(0, 8)}...</span>
      </div>

      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold text-gray-900">Campaign Detail</h1>
        <span className={`px-3 py-1 rounded-full text-sm font-medium ${statusBadge(campaign.status)}`}>
          {campaign.status?.replace('_', ' ')}
        </span>
      </div>

      {/* Campaign 信息卡片 */}
      <div className="grid grid-cols-2 gap-6 mb-6">
        {/* 基本信息 */}
        <div className="bg-white rounded-xl border border-gray-200 p-6">
          <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-4">Campaign Info</h2>
          <dl className="space-y-3 text-sm">
            <div className="flex justify-between">
              <dt className="text-gray-500">Campaign ID</dt>
              <dd className="text-gray-900 font-mono text-xs">{campaign.id}</dd>
            </div>
            <div className="flex justify-between">
              <dt className="text-gray-500">Merchant</dt>
              <dd>
                <Link href={`/merchants/${campaign.merchants?.id}`} className="text-blue-600 hover:underline">
                  {campaign.merchants?.name ?? '—'}
                </Link>
              </dd>
            </div>
            <div className="flex justify-between">
              <dt className="text-gray-500">Placement</dt>
              <dd className="text-gray-900">{campaign.placement ?? '—'}</dd>
            </div>
            <div className="flex justify-between">
              <dt className="text-gray-500">Bid Amount</dt>
              <dd className="text-gray-900 font-medium">${Number(campaign.bid_amount ?? 0).toFixed(2)}</dd>
            </div>
            <div className="flex justify-between">
              <dt className="text-gray-500">Daily Budget</dt>
              <dd className="text-gray-900 font-medium">${Number(campaign.daily_budget ?? 0).toFixed(2)}</dd>
            </div>
            {campaign.deal_id && (
              <div className="flex justify-between">
                <dt className="text-gray-500">Deal ID</dt>
                <dd>
                  <Link href={`/deals/${campaign.deal_id}`} className="text-blue-600 hover:underline font-mono text-xs">
                    {campaign.deal_id.slice(0, 8)}...
                  </Link>
                </dd>
              </div>
            )}
            <div className="flex justify-between">
              <dt className="text-gray-500">Created</dt>
              <dd className="text-gray-700">{new Date(campaign.created_at).toLocaleString('en-US')}</dd>
            </div>
            {campaign.start_date && (
              <div className="flex justify-between">
                <dt className="text-gray-500">Start Date</dt>
                <dd className="text-gray-700">{campaign.start_date}</dd>
              </div>
            )}
            {campaign.end_date && (
              <div className="flex justify-between">
                <dt className="text-gray-500">End Date</dt>
                <dd className="text-gray-700">{campaign.end_date}</dd>
              </div>
            )}
            {campaign.admin_note && (
              <div className="flex justify-between">
                <dt className="text-gray-500">Admin Note</dt>
                <dd className="text-red-600 text-xs">{campaign.admin_note}</dd>
              </div>
            )}
          </dl>
        </div>

        {/* 统计信息 + 账户余额 */}
        <div className="space-y-6">
          <div className="bg-white rounded-xl border border-gray-200 p-6">
            <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-4">Performance (Last 30 Days)</h2>
            <div className="grid grid-cols-2 gap-4">
              <div>
                <p className="text-xs text-gray-500">Total Spend</p>
                <p className="text-xl font-bold text-blue-700">${totalSpend.toFixed(2)}</p>
              </div>
              <div>
                <p className="text-xs text-gray-500">Impressions</p>
                <p className="text-xl font-bold text-gray-900">{totalImpressions.toLocaleString()}</p>
              </div>
              <div>
                <p className="text-xs text-gray-500">Clicks</p>
                <p className="text-xl font-bold text-gray-900">{totalClicks.toLocaleString()}</p>
              </div>
              <div>
                <p className="text-xs text-gray-500">CTR</p>
                <p className="text-xl font-bold text-gray-900">
                  {totalImpressions > 0 ? ((totalClicks / totalImpressions) * 100).toFixed(2) : '0.00'}%
                </p>
              </div>
            </div>
          </div>

          {campaign.ad_accounts && (
            <div className="bg-white rounded-xl border border-gray-200 p-6">
              <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-4">Account Balance</h2>
              <div className="grid grid-cols-3 gap-4">
                <div>
                  <p className="text-xs text-gray-500">Balance</p>
                  <p className="text-xl font-bold text-blue-700">${Number(campaign.ad_accounts.balance ?? 0).toFixed(2)}</p>
                </div>
                <div>
                  <p className="text-xs text-gray-500">Total Deposit</p>
                  <p className="text-xl font-bold text-green-700">${Number(campaign.ad_accounts.total_deposit ?? 0).toFixed(2)}</p>
                </div>
                <div>
                  <p className="text-xs text-gray-500">Total Spend</p>
                  <p className="text-xl font-bold text-red-700">${Number(campaign.ad_accounts.total_spend ?? 0).toFixed(2)}</p>
                </div>
              </div>
            </div>
          )}

          {/* Admin 操作 */}
          <div className="bg-white rounded-xl border border-gray-200 p-6">
            <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-4">Admin Actions</h2>
            <CampaignDetailActions campaignId={campaign.id} status={campaign.status} />
          </div>
        </div>
      </div>

      {/* 每日统计表格 */}
      <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
        <div className="px-4 py-3 border-b border-gray-200">
          <h2 className="text-sm font-semibold text-gray-700">Daily Stats</h2>
        </div>
        <table className="w-full text-sm">
          <thead className="bg-gray-50 border-b border-gray-200">
            <tr>
              <th className="text-left px-4 py-3 font-medium text-gray-600">Date</th>
              <th className="text-right px-4 py-3 font-medium text-gray-600">Spend</th>
              <th className="text-right px-4 py-3 font-medium text-gray-600">Impressions</th>
              <th className="text-right px-4 py-3 font-medium text-gray-600">Clicks</th>
              <th className="text-right px-4 py-3 font-medium text-gray-600">CTR</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100">
            {(dailyStats ?? []).map((s: any) => {
              const ctr = s.impressions > 0 ? ((s.clicks / s.impressions) * 100).toFixed(2) : '0.00'
              return (
                <tr key={s.stat_date} className="hover:bg-gray-50">
                  <td className="px-4 py-3 text-gray-900">{s.stat_date}</td>
                  <td className="px-4 py-3 text-right font-medium text-gray-900">${Number(s.spend ?? 0).toFixed(2)}</td>
                  <td className="px-4 py-3 text-right text-gray-700">{Number(s.impressions ?? 0).toLocaleString()}</td>
                  <td className="px-4 py-3 text-right text-gray-700">{Number(s.clicks ?? 0).toLocaleString()}</td>
                  <td className="px-4 py-3 text-right text-gray-700">{ctr}%</td>
                </tr>
              )
            })}
          </tbody>
        </table>
        {(!dailyStats || dailyStats.length === 0) && (
          <p className="text-center text-gray-400 py-8">No daily stats yet</p>
        )}
      </div>
    </div>
  )
}
