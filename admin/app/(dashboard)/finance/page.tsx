import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import Link from 'next/link'

export default async function FinancePage({
  searchParams,
}: {
  searchParams: Promise<{ brand?: string }>
}) {
  const { brand: brandFilter } = await searchParams
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  const { data: profile } = await supabase.from('users').select('role').eq('id', user!.id).single()

  if (profile?.role !== 'admin') redirect('/dashboard')

  const { data: brands } = await supabase.from('brands').select('id, name').order('name')

  const { data: withdrawals } = await supabase
    .from('withdrawals')
    .select('id, merchant_id, amount, status, created_at, merchants(name, brand_id, brands(name))')
    .order('created_at', { ascending: false })
    .limit(100)

  let filteredWithdrawals = withdrawals ?? []
  if (brandFilter) {
    filteredWithdrawals = filteredWithdrawals.filter((w: any) => w.merchants?.brand_id === brandFilter)
  }

  const brandSummary: Record<string, { name: string; totalAmount: number; count: number }> = {}
  for (const w of (withdrawals ?? [])) {
    const m = w.merchants as any
    if (m?.brand_id && m?.brands?.name) {
      if (!brandSummary[m.brand_id]) {
        brandSummary[m.brand_id] = { name: m.brands.name, totalAmount: 0, count: 0 }
      }
      brandSummary[m.brand_id].totalAmount += Number(w.amount)
      brandSummary[m.brand_id].count++
    }
  }

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold text-gray-900">Finance</h1>
        <div className="flex items-center gap-2">
          <label className="text-sm text-gray-500">Brand:</label>
          <div className="flex items-center gap-1 flex-wrap">
            <a href="/finance" className={`px-2 py-1 rounded text-xs font-medium transition-colors ${!brandFilter ? 'bg-blue-100 text-blue-700' : 'bg-gray-100 text-gray-600 hover:bg-gray-200'}`}>All</a>
            {brands?.map(b => (
              <a key={b.id} href={`/finance?brand=${b.id}`} className={`px-2 py-1 rounded text-xs font-medium transition-colors ${brandFilter === b.id ? 'bg-blue-100 text-blue-700' : 'bg-gray-100 text-gray-600 hover:bg-gray-200'}`}>{b.name}</a>
            ))}
          </div>
        </div>
      </div>

      {Object.keys(brandSummary).length > 0 && !brandFilter && (
        <div className="mb-6 bg-white rounded-xl border border-gray-200 p-6">
          <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-4">Brand Summary</h2>
          <div className="grid grid-cols-2 sm:grid-cols-3 gap-4">
            {Object.entries(brandSummary).map(([id, s]) => (
              <a key={id} href={`/finance?brand=${id}`} className="block rounded-lg border border-gray-200 p-4 hover:border-blue-300 hover:bg-blue-50/50 transition-colors">
                <p className="text-sm font-medium text-gray-900">{s.name}</p>
                <p className="text-2xl font-bold text-blue-700 mt-1">${s.totalAmount.toFixed(2)}</p>
                <p className="text-xs text-gray-500 mt-1">{s.count} withdrawals</p>
              </a>
            ))}
          </div>
        </div>
      )}

      <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
        <table className="w-full text-sm">
          <thead className="bg-gray-50 border-b border-gray-200">
            <tr>
              <th className="text-left px-4 py-3 font-medium text-gray-600">Merchant</th>
              <th className="text-left px-4 py-3 font-medium text-gray-600">Brand</th>
              <th className="text-left px-4 py-3 font-medium text-gray-600">Amount</th>
              <th className="text-left px-4 py-3 font-medium text-gray-600">Status</th>
              <th className="text-left px-4 py-3 font-medium text-gray-600">Date</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100">
            {filteredWithdrawals.map((w: any) => (
              <tr key={w.id} className="hover:bg-gray-50">
                <td className="px-4 py-3">
                  <Link href={`/merchants/${w.merchant_id}`} className="text-blue-600 hover:underline font-medium">{w.merchants?.name ?? '—'}</Link>
                </td>
                <td className="px-4 py-3 text-gray-600 text-xs">
                  {w.merchants?.brands?.name ? (
                    <Link href={`/brands/${w.merchants.brand_id}`} className="text-purple-600 hover:underline">{w.merchants.brands.name}</Link>
                  ) : '—'}
                </td>
                <td className="px-4 py-3 font-medium text-gray-900">${Number(w.amount).toFixed(2)}</td>
                <td className="px-4 py-3">
                  <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${w.status === 'completed' ? 'bg-green-100 text-green-700' : w.status === 'pending' ? 'bg-yellow-100 text-yellow-700' : w.status === 'processing' ? 'bg-blue-100 text-blue-700' : w.status === 'failed' ? 'bg-red-100 text-red-700' : 'bg-gray-100 text-gray-600'}`}>
                    {w.status}
                  </span>
                </td>
                <td className="px-4 py-3 text-gray-500">{new Date(w.created_at).toLocaleDateString()}</td>
              </tr>
            ))}
          </tbody>
        </table>
        {filteredWithdrawals.length === 0 && (
          <p className="text-center text-gray-400 py-8">No withdrawal records found</p>
        )}
      </div>
    </div>
  )
}
