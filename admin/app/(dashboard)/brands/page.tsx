import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import Link from 'next/link'

export default async function BrandsPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  const { data: profile } = await supabase.from('users').select('role').eq('id', user!.id).single()

  if (profile?.role !== 'admin') redirect('/dashboard')

  // 查询所有品牌 + 关联门店数量 + 品牌管理员数量
  const { data: brands } = await supabase
    .from('brands')
    .select('id, name, logo_url, created_at')
    .order('created_at', { ascending: false })

  // 获取每个品牌的门店数量
  const brandIds = brands?.map(b => b.id) ?? []
  let storeCountMap: Record<string, number> = {}
  let adminCountMap: Record<string, number> = {}

  if (brandIds.length > 0) {
    const { data: merchants } = await supabase
      .from('merchants')
      .select('brand_id')
      .in('brand_id', brandIds)

    if (merchants) {
      for (const m of merchants) {
        if (m.brand_id) {
          storeCountMap[m.brand_id] = (storeCountMap[m.brand_id] || 0) + 1
        }
      }
    }

    const { data: admins } = await supabase
      .from('brand_admins')
      .select('brand_id')
      .in('brand_id', brandIds)

    if (admins) {
      for (const a of admins) {
        adminCountMap[a.brand_id] = (adminCountMap[a.brand_id] || 0) + 1
      }
    }
  }

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold text-gray-900">Brands</h1>
        <span className="text-sm text-gray-500">{brands?.length ?? 0} total</span>
      </div>

      <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
        <table className="w-full text-sm">
          <thead className="bg-gray-50 border-b border-gray-200">
            <tr>
              <th className="text-left px-4 py-3 font-medium text-gray-600">Brand</th>
              <th className="text-left px-4 py-3 font-medium text-gray-600">Stores</th>
              <th className="text-left px-4 py-3 font-medium text-gray-600">Admins</th>
              <th className="text-left px-4 py-3 font-medium text-gray-600">Created</th>
              <th className="text-left px-4 py-3 font-medium text-gray-600"></th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100">
            {brands?.map(b => (
              <tr key={b.id} className="hover:bg-gray-50">
                <td className="px-4 py-3">
                  <div className="flex items-center gap-3">
                    {b.logo_url ? (
                      <img src={b.logo_url} alt="" className="w-8 h-8 rounded-full object-cover border border-gray-200" />
                    ) : (
                      <div className="w-8 h-8 rounded-full bg-gray-100 flex items-center justify-center text-gray-400 text-xs font-bold">
                        {b.name?.charAt(0)?.toUpperCase() ?? '?'}
                      </div>
                    )}
                    <Link href={`/brands/${b.id}`} className="font-medium text-blue-600 hover:text-blue-800 hover:underline">
                      {b.name}
                    </Link>
                  </div>
                </td>
                <td className="px-4 py-3 text-gray-600">{storeCountMap[b.id] ?? 0}</td>
                <td className="px-4 py-3 text-gray-600">{adminCountMap[b.id] ?? 0}</td>
                <td className="px-4 py-3 text-gray-500">{new Date(b.created_at).toLocaleDateString('en-US')}</td>
                <td className="px-4 py-3">
                  <Link
                    href={`/brands/${b.id}`}
                    className="inline-flex items-center justify-center px-3 py-1.5 text-sm font-medium rounded-lg border border-blue-200 bg-blue-50 text-blue-700 hover:bg-blue-100 transition-colors"
                  >
                    View
                  </Link>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        {(!brands || brands.length === 0) && (
          <p className="text-center text-gray-400 py-8">No brands found</p>
        )}
      </div>
    </div>
  )
}
