import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import Link from 'next/link'
import MerchantActionButtons from '@/components/merchant-action-buttons'

export default async function MerchantsPage({
  searchParams,
}: {
  searchParams: Promise<{ brand?: string }>
}) {
  const { brand: brandFilter } = await searchParams
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  const { data: profile } = await supabase.from('users').select('role').eq('id', user!.id).single()

  if (profile?.role !== 'admin') redirect('/dashboard')

  // 查询商家列表，JOIN brands 获取品牌信息
  let query = supabase
    .from('merchants')
    .select('id, name, category, status, user_id, brand_id, created_at, brands(id, name)')
    .order('created_at', { ascending: false })

  if (brandFilter) {
    query = query.eq('brand_id', brandFilter)
  }

  const { data: merchants, error: merchantsError } = await query

  // 获取所有品牌，用于筛选下拉
  const { data: allBrands } = await supabase
    .from('brands')
    .select('id, name')
    .order('name')

  const pendingCount = merchants?.filter(m => m.status === 'pending').length ?? 0

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <div className="flex items-center gap-3">
          <h1 className="text-2xl font-bold text-gray-900">Merchants</h1>
          {pendingCount > 0 && (
            <span className="text-sm bg-yellow-100 text-yellow-700 px-3 py-1 rounded-full font-medium">
              {pendingCount} pending review
            </span>
          )}
        </div>
        {/* 品牌筛选 */}
        <div className="flex items-center gap-2">
          <label className="text-sm text-gray-500">Brand:</label>
          <BrandFilter brands={allBrands ?? []} currentBrand={brandFilter} />
        </div>
      </div>

      <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
        <table className="w-full text-sm">
          <thead className="bg-gray-50 border-b border-gray-200">
            <tr>
              <th className="text-left px-4 py-3 font-medium text-gray-600">Name</th>
              <th className="text-left px-4 py-3 font-medium text-gray-600">Brand</th>
              <th className="text-left px-4 py-3 font-medium text-gray-600">Category</th>
              <th className="text-left px-4 py-3 font-medium text-gray-600">Status / Action</th>
              <th className="text-left px-4 py-3 font-medium text-gray-600">Applied</th>
              <th className="text-left px-4 py-3 font-medium text-gray-600"></th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100">
            {merchants?.map((m: any) => (
              <tr key={m.id} className={`hover:bg-gray-50 ${m.status === 'pending' ? 'bg-yellow-50/50' : ''}`}>
                <td className="px-4 py-3 font-medium text-gray-900">
                  <Link
                    href={`/merchants/${m.id}`}
                    className="font-medium text-blue-600 hover:text-blue-800 hover:underline"
                  >
                    {m.name}
                  </Link>
                </td>
                <td className="px-4 py-3 text-gray-600">
                  {m.brands ? (
                    <Link
                      href={`/brands/${m.brands.id}`}
                      className="text-blue-600 hover:underline text-xs"
                    >
                      {m.brands.name}
                    </Link>
                  ) : (
                    <span className="text-gray-400">—</span>
                  )}
                </td>
                <td className="px-4 py-3 text-gray-600">{m.category || '—'}</td>
                <td className="px-4 py-3">
                  <MerchantActionButtons
                    merchantId={m.id}
                    merchantUserId={m.user_id}
                    status={m.status}
                  />
                </td>
                <td className="px-4 py-3 text-gray-500">
                  {new Date(m.created_at).toLocaleDateString()}
                </td>
                <td className="px-4 py-3">
                  <Link
                    href={`/merchants/${m.id}`}
                    className="inline-flex items-center justify-center px-3 py-1.5 text-sm font-medium rounded-lg border border-blue-200 bg-blue-50 text-blue-700 hover:bg-blue-100 transition-colors"
                  >
                    {m.status === 'pending' ? 'Review' : 'View'}
                  </Link>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        {merchantsError && (
          <p className="text-center text-red-500 py-4 text-xs">Error: {merchantsError.message} | Code: {merchantsError.code}</p>
        )}
        {(!merchants || merchants.length === 0) && !merchantsError && (
          <p className="text-center text-gray-400 py-8">No merchants found</p>
        )}
      </div>
    </div>
  )
}

// 品牌筛选下拉（客户端组件用 <a> 实现简单筛选）
function BrandFilter({ brands, currentBrand }: { brands: { id: string; name: string }[]; currentBrand?: string }) {
  return (
    <div className="flex items-center gap-1 flex-wrap">
      <a
        href="/merchants"
        className={`px-2 py-1 rounded text-xs font-medium transition-colors ${
          !currentBrand ? 'bg-blue-100 text-blue-700' : 'bg-gray-100 text-gray-600 hover:bg-gray-200'
        }`}
      >
        All
      </a>
      {brands.map(b => (
        <a
          key={b.id}
          href={`/merchants?brand=${b.id}`}
          className={`px-2 py-1 rounded text-xs font-medium transition-colors ${
            currentBrand === b.id ? 'bg-blue-100 text-blue-700' : 'bg-gray-100 text-gray-600 hover:bg-gray-200'
          }`}
        >
          {b.name}
        </a>
      ))}
    </div>
  )
}
