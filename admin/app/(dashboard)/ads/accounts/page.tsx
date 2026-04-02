import { createClient } from '@/lib/supabase/server'
import { getServiceRoleClient } from '@/lib/supabase/service'
import { redirect } from 'next/navigation'
import Link from 'next/link'

export const dynamic = 'force-dynamic'

export default async function AdsAccountsPage() {
  // 鉴权
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  const { data: profile } = await supabase.from('users').select('role').eq('id', user!.id).single()
  if (profile?.role !== 'admin') redirect('/dashboard')

  const serviceClient = getServiceRoleClient()

  // 查询广告账户 + 商家名
  const { data: accounts, error } = await serviceClient
    .from('ad_accounts')
    .select('*, merchants(id, name)')
    .order('balance', { ascending: false })

  // 查询每个账户的活跃 campaign 数量
  const { data: activeCampaigns } = await serviceClient
    .from('ad_campaigns')
    .select('merchant_id')
    .eq('status', 'active')

  // 构建 merchant_id -> 活跃 campaign 数 map
  const activeCampaignMap: Record<string, number> = {}
  for (const c of (activeCampaigns ?? [])) {
    activeCampaignMap[c.merchant_id] = (activeCampaignMap[c.merchant_id] ?? 0) + 1
  }

  // 汇总统计
  const totalBalance = (accounts ?? []).reduce((sum: number, a: any) => sum + Number(a.balance ?? 0), 0)
  const totalDeposit = (accounts ?? []).reduce((sum: number, a: any) => sum + Number(a.total_deposit ?? 0), 0)
  const totalSpend = (accounts ?? []).reduce((sum: number, a: any) => sum + Number(a.total_spend ?? 0), 0)

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold text-gray-900">Ad Accounts</h1>
        {/* 子导航 */}
        <div className="flex items-center gap-2 text-sm">
          <Link href="/ads" className="text-gray-500 hover:text-blue-600">Campaigns</Link>
          <span className="text-gray-300">|</span>
          <Link href="/ads/accounts" className="text-blue-600 hover:underline font-medium">Accounts</Link>
          <span className="text-gray-300">|</span>
          <Link href="/ads/revenue" className="text-gray-500 hover:text-blue-600">Revenue</Link>
        </div>
      </div>

      {/* 汇总卡片 */}
      <div className="grid grid-cols-3 gap-4 mb-6">
        <div className="bg-white rounded-xl border border-gray-200 p-4">
          <p className="text-xs font-medium text-gray-500 uppercase tracking-wide">Total Balance</p>
          <p className="text-2xl font-bold text-blue-700 mt-1">${totalBalance.toFixed(2)}</p>
        </div>
        <div className="bg-white rounded-xl border border-gray-200 p-4">
          <p className="text-xs font-medium text-gray-500 uppercase tracking-wide">Total Deposits</p>
          <p className="text-2xl font-bold text-green-700 mt-1">${totalDeposit.toFixed(2)}</p>
        </div>
        <div className="bg-white rounded-xl border border-gray-200 p-4">
          <p className="text-xs font-medium text-gray-500 uppercase tracking-wide">Total Spend</p>
          <p className="text-2xl font-bold text-red-700 mt-1">${totalSpend.toFixed(2)}</p>
        </div>
      </div>

      {error && (
        <div className="bg-red-50 border border-red-200 rounded-lg p-4 mb-4 text-sm text-red-700">
          {error.message}
        </div>
      )}

      {/* 账户表格 */}
      <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
        <table className="w-full text-sm">
          <thead className="bg-gray-50 border-b border-gray-200">
            <tr>
              <th className="text-left px-4 py-3 font-medium text-gray-600">Merchant</th>
              <th className="text-right px-4 py-3 font-medium text-gray-600">Balance</th>
              <th className="text-right px-4 py-3 font-medium text-gray-600">Total Deposit</th>
              <th className="text-right px-4 py-3 font-medium text-gray-600">Total Spend</th>
              <th className="text-right px-4 py-3 font-medium text-gray-600">Active Campaigns</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100">
            {(accounts ?? []).map((a: any) => (
              <tr key={a.id} className="hover:bg-gray-50">
                <td className="px-4 py-3">
                  <Link href={`/merchants/${a.merchants?.id}`} className="text-blue-600 hover:underline font-medium">
                    {a.merchants?.name ?? '—'}
                  </Link>
                </td>
                <td className="px-4 py-3 text-right font-medium text-gray-900">
                  ${Number(a.balance ?? 0).toFixed(2)}
                </td>
                <td className="px-4 py-3 text-right text-gray-700">
                  ${Number(a.total_deposit ?? 0).toFixed(2)}
                </td>
                <td className="px-4 py-3 text-right text-gray-700">
                  ${Number(a.total_spend ?? 0).toFixed(2)}
                </td>
                <td className="px-4 py-3 text-right text-gray-700">
                  {activeCampaignMap[a.merchant_id] ?? 0}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        {(!accounts || accounts.length === 0) && (
          <p className="text-center text-gray-400 py-8">No ad accounts found</p>
        )}
      </div>
    </div>
  )
}
