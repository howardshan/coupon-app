import { createClient } from '@/lib/supabase/server'
import Link from 'next/link'
import DealSortOrder from '@/components/deal-sort-order'

export default async function DealsPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  const { data: profile } = await supabase.from('users').select('role').eq('id', user!.id).single()

  let deals
  if (profile?.role === 'admin') {
    // 增加 applicable_merchant_ids 字段
    const { data } = await supabase
      .from('deals')
      .select('id, title, discount_price, original_price, is_active, deal_status, expires_at, created_at, sort_order, applicable_merchant_ids, merchant_id, merchants(name, brand_id, brands(name))')
      .order('created_at', { ascending: false })
      .limit(50)
    deals = data
  } else {
    const { data: merchant } = await supabase
      .from('merchants')
      .select('id')
      .eq('user_id', user!.id)
      .single()

    if (merchant) {
      const { data } = await supabase
        .from('deals')
        .select('id, title, discount_price, original_price, is_active, expires_at, created_at, sort_order')
        .eq('merchant_id', merchant.id)
        .order('created_at', { ascending: false })
      deals = data
    }
  }

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold text-gray-900">Deals</h1>
      </div>

      <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
        <table className="w-full text-sm">
          <thead className="bg-gray-50 border-b border-gray-200">
            <tr>
              <th className="text-left px-4 py-3 font-medium text-gray-600">Title</th>
              {profile?.role === 'admin' && (
                <th className="text-left px-4 py-3 font-medium text-gray-600">Merchant</th>
              )}
              <th className="text-left px-4 py-3 font-medium text-gray-600">Sale Price</th>
              {profile?.role === 'admin' && (
                <th className="text-left px-4 py-3 font-medium text-gray-600">Scope</th>
              )}
              <th className="text-left px-4 py-3 font-medium text-gray-600">Status</th>
              <th className="text-left px-4 py-3 font-medium text-gray-600">Created</th>
              {profile?.role === 'admin' && (
                <th className="text-left px-4 py-3 font-medium text-gray-600">Sort Order</th>
              )}
              <th className="text-left px-4 py-3 font-medium text-gray-600"></th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100">
            {deals?.map((d: any) => {
              const applicableIds = d.applicable_merchant_ids as string[] | null
              const isMultiStore = applicableIds && applicableIds.length > 0
              const brandName = d.merchants?.brands?.name

              return (
                <tr key={d.id} className="hover:bg-gray-50">
                  <td className="px-4 py-3 font-medium text-gray-900">
                    <Link href={`/deals/${d.id}`} className="text-blue-600 hover:text-blue-800 hover:underline">
                      {d.title}
                    </Link>
                  </td>
                  {profile?.role === 'admin' && (
                    <td className="px-4 py-3 text-gray-600">
                      {d.merchants?.name ?? '—'}
                      {brandName && (
                        <span className="text-xs text-purple-600 ml-1">({brandName})</span>
                      )}
                    </td>
                  )}
                  <td className="px-4 py-3 text-gray-900">
                    ${d.discount_price}
                    {d.original_price != null && (
                      <span className="text-gray-400 line-through ml-2">${d.original_price}</span>
                    )}
                  </td>
                  {profile?.role === 'admin' && (
                    <td className="px-4 py-3">
                      {isMultiStore ? (
                        <span className="px-2 py-0.5 rounded-full text-xs font-medium bg-purple-100 text-purple-700">
                          {applicableIds.length} stores
                        </span>
                      ) : (
                        <span className="px-2 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-600">
                          Single
                        </span>
                      )}
                    </td>
                  )}
                  <td className="px-4 py-3">
                    <DealStatusBadge isActive={d.is_active} expiresAt={d.expires_at} />
                  </td>
                  <td className="px-4 py-3 text-gray-500">
                    {new Date(d.created_at).toLocaleDateString()}
                  </td>
                  {profile?.role === 'admin' && (
                    <td className="px-4 py-3">
                      <DealSortOrder dealId={d.id} sortOrder={d.sort_order ?? null} />
                    </td>
                  )}
                  <td className="px-4 py-3">
                    <Link href={`/deals/${d.id}`} className="inline-flex items-center justify-center px-3 py-1.5 text-sm font-medium rounded-lg border border-blue-200 bg-blue-50 text-blue-700 hover:bg-blue-100 transition-colors">
                      {d.is_active || d.deal_status === 'inactive' ? 'View' : 'Review'}
                    </Link>
                  </td>
                </tr>
              )
            })}
          </tbody>
        </table>
        {(!deals || deals.length === 0) && (
          <p className="text-center text-gray-400 py-8">No deals found</p>
        )}
      </div>
    </div>
  )
}

function DealStatusBadge({ isActive, expiresAt }: { isActive: boolean; expiresAt: string }) {
  const now = new Date()
  const expired = new Date(expiresAt) < now
  const status = expired ? 'expired' : isActive ? 'active' : 'inactive'
  const styles: Record<string, string> = {
    active: 'bg-green-100 text-green-700',
    inactive: 'bg-gray-100 text-gray-600',
    expired: 'bg-red-100 text-red-700',
  }
  return (
    <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${styles[status] ?? 'bg-gray-100 text-gray-600'}`}>
      {status}
    </span>
  )
}
