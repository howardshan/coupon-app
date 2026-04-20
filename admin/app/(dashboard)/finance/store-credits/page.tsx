import { createClient } from '@/lib/supabase/server'
import { getServiceRoleClient } from '@/lib/supabase/service'
import { redirect } from 'next/navigation'

export default async function StoreCreditsPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  const { data: profile } = await supabase
    .from('users')
    .select('role')
    .eq('id', user!.id)
    .single()

  if (profile?.role !== 'admin') redirect('/dashboard')

  const service = getServiceRoleClient()

  // 汇总统计
  const { data: allCredits } = await service
    .from('store_credits')
    .select('user_id, amount')

  const rows = (allCredits ?? []) as Array<{ user_id: string; amount: number }>
  const totalOutstanding = rows.reduce((s, r) => s + Number(r.amount), 0)
  const usersWithCredit = rows.filter(r => Number(r.amount) > 0).length
  const totalUsers = rows.length

  // 有余额的用户明细（按金额降序）
  const usersWithBalance = rows
    .filter(r => Number(r.amount) > 0)
    .sort((a, b) => Number(b.amount) - Number(a.amount))

  // 批量查用户信息
  const userIds = usersWithBalance.map(r => r.user_id)
  const { data: usersData } = userIds.length > 0
    ? await service.from('users').select('id, email, full_name').in('id', userIds)
    : { data: [] }
  const userMap = new Map(
    ((usersData ?? []) as Array<{ id: string; email: string; full_name: string | null }>)
      .map(u => [u.id, u])
  )

  const fmt = (n: number) => `$${n.toFixed(2)}`

  return (
    <div className="p-6">
      <h1 className="text-2xl font-bold text-gray-900 mb-2">Store Credits</h1>
      <p className="text-sm text-gray-500 mb-6">
        Outstanding store credit balances across all customers. This represents the platform&rsquo;s liability.
      </p>

      {/* 汇总卡片 */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 mb-8">
        <div className="bg-white rounded-lg border p-5">
          <p className="text-sm text-gray-500">Total Outstanding</p>
          <p className="text-3xl font-bold text-red-600 mt-1">{fmt(totalOutstanding)}</p>
          <p className="text-xs text-gray-400 mt-1">Platform liability</p>
        </div>
        <div className="bg-white rounded-lg border p-5">
          <p className="text-sm text-gray-500">Users with Balance</p>
          <p className="text-3xl font-bold text-gray-900 mt-1">{usersWithCredit}</p>
          <p className="text-xs text-gray-400 mt-1">of {totalUsers} total</p>
        </div>
        <div className="bg-white rounded-lg border p-5">
          <p className="text-sm text-gray-500">Average Balance</p>
          <p className="text-3xl font-bold text-gray-900 mt-1">
            {usersWithCredit > 0 ? fmt(totalOutstanding / usersWithCredit) : '$0.00'}
          </p>
          <p className="text-xs text-gray-400 mt-1">Per user with balance</p>
        </div>
      </div>

      {/* 用户明细表 */}
      <div className="bg-white rounded-lg shadow overflow-hidden">
        <table className="min-w-full divide-y divide-gray-200 text-sm">
          <thead className="bg-gray-50">
            <tr>
              <th className="px-4 py-3 text-left font-semibold text-gray-700">User</th>
              <th className="px-4 py-3 text-left font-semibold text-gray-700">Email</th>
              <th className="px-4 py-3 text-right font-semibold text-gray-700">Balance</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-200">
            {usersWithBalance.length === 0 && (
              <tr>
                <td colSpan={3} className="px-4 py-10 text-center text-gray-400">
                  No users with store credit balance.
                </td>
              </tr>
            )}
            {usersWithBalance.map((r) => {
              const u = userMap.get(r.user_id)
              return (
                <tr key={r.user_id} className="hover:bg-gray-50">
                  <td className="px-4 py-3 font-medium text-gray-900">
                    {u?.full_name || r.user_id.substring(0, 8) + '...'}
                  </td>
                  <td className="px-4 py-3 text-gray-600">{u?.email || '-'}</td>
                  <td className="px-4 py-3 text-right font-semibold text-red-600">
                    {fmt(Number(r.amount))}
                  </td>
                </tr>
              )
            })}
          </tbody>
          {usersWithBalance.length > 0 && (
            <tfoot className="bg-gray-50 border-t-2 border-gray-200">
              <tr className="font-semibold">
                <td className="px-4 py-3 text-gray-900">TOTAL</td>
                <td className="px-4 py-3"></td>
                <td className="px-4 py-3 text-right text-red-600">{fmt(totalOutstanding)}</td>
              </tr>
            </tfoot>
          )}
        </table>
      </div>
    </div>
  )
}
