import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import Link from 'next/link'
import DealReviewActions from '@/components/deal-review-actions'

export default async function DealReviewPage({
  params,
}: {
  params: Promise<{ id: string }>
}) {
  const { id } = await params
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  const { data: profile } = await supabase.from('users').select('role').eq('id', user!.id).single()

  if (profile?.role !== 'admin') redirect('/dashboard')

  const { data: deal } = await supabase
    .from('deals')
    .select(`
      id, merchant_id, title, description, category,
      original_price, discount_price, discount_label,
      image_urls, stock_limit, total_sold, rating, review_count,
      is_featured, is_active, refund_policy, address,
      dishes, merchant_hours, expires_at,
      applicable_merchant_ids,
      created_at, updated_at,
      merchants(name, user_id, brand_id, brands(name))
    `)
    .eq('id', id)
    .single()

  if (!deal) {
    return (
      <div>
        <p className="text-gray-500">Deal not found.</p>
        <Link href="/deals" className="mt-3 inline-flex items-center gap-2 px-4 py-2 text-sm font-medium rounded-lg border border-gray-300 bg-white text-gray-700 shadow-sm hover:bg-gray-50 transition-colors">
          ← Back to Deals
        </Link>
      </div>
    )
  }

  const merchantName = (deal.merchants as any)?.name ?? '—'
  const brandName = (deal.merchants as any)?.brands?.name
  const isExpired = deal.expires_at ? new Date(deal.expires_at) < new Date() : false
  const dishesRaw = deal.dishes
  const dishesList = Array.isArray(dishesRaw)
    ? dishesRaw.map((d: unknown) => (typeof d === 'string' ? d : (d as { name?: string })?.name ?? String(d)))
    : []

  // 查询适用门店名称
  const applicableIds = deal.applicable_merchant_ids as string[] | null
  let applicableStores: { id: string; name: string }[] = []
  if (applicableIds && applicableIds.length > 0) {
    const { data } = await supabase
      .from('merchants')
      .select('id, name')
      .in('id', applicableIds)
    applicableStores = data ?? []
  }

  return (
    <div>
      <div className="mb-6 flex items-center justify-between">
        <div>
          <Link href="/deals" className="mb-3 inline-flex items-center gap-2 px-3 py-2 text-sm font-medium rounded-lg border border-gray-300 bg-white text-gray-700 shadow-sm hover:bg-gray-50 transition-colors">
            ← Back to Deals
          </Link>
          <h1 className="text-2xl font-bold text-gray-900">Deal Review</h1>
        </div>
        <DealReviewActions dealId={deal.id} isActive={deal.is_active} />
      </div>

      <div className="space-y-6">
        <div className="bg-white rounded-xl border border-gray-200 p-6">
          <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-3">Status</h2>
          <span className={`inline-block px-3 py-1 rounded-full text-sm font-medium ${isExpired ? 'bg-red-100 text-red-700' : deal.is_active ? 'bg-green-100 text-green-700' : 'bg-gray-100 text-gray-600'}`}>
            {isExpired ? 'expired' : deal.is_active ? 'active' : 'inactive'}
          </span>
        </div>

        <div className="bg-white rounded-xl border border-gray-200 p-6">
          <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-4">Basic Information</h2>
          <dl className="grid grid-cols-1 sm:grid-cols-2 gap-x-4 gap-y-3 text-sm">
            <div><dt className="text-gray-500">Title</dt><dd className="font-medium text-gray-900">{deal.title}</dd></div>
            <div>
              <dt className="text-gray-500">Merchant</dt>
              <dd className="font-medium text-gray-900">
                {merchantName}
                {brandName && <span className="text-xs text-purple-600 ml-1">({brandName})</span>}
              </dd>
            </div>
            <div><dt className="text-gray-500">Category</dt><dd className="font-medium text-gray-900">{deal.category || '—'}</dd></div>
            <div><dt className="text-gray-500">Original price</dt><dd className="font-medium text-gray-900">${deal.original_price}</dd></div>
            <div><dt className="text-gray-500">Sale price</dt><dd className="font-medium text-gray-900">${deal.discount_price}</dd></div>
            {deal.discount_label && <div><dt className="text-gray-500">Discount label</dt><dd className="font-medium text-gray-900">{deal.discount_label}</dd></div>}
            <div><dt className="text-gray-500">Expires at</dt><dd className="font-medium text-gray-900">{deal.expires_at ? new Date(deal.expires_at).toLocaleString() : '—'}</dd></div>
            <div><dt className="text-gray-500">Stock limit</dt><dd className="font-medium text-gray-900">{deal.stock_limit ?? '—'}</dd></div>
            <div><dt className="text-gray-500">Total sold</dt><dd className="font-medium text-gray-900">{deal.total_sold ?? 0}</dd></div>
            <div><dt className="text-gray-500">Created</dt><dd className="font-medium text-gray-900">{deal.created_at ? new Date(deal.created_at).toLocaleString() : '—'}</dd></div>
          </dl>
          {deal.description && (
            <div className="mt-3 pt-3 border-t border-gray-100">
              <dt className="text-gray-500 text-sm">Description</dt>
              <dd className="mt-1 text-gray-900">{deal.description}</dd>
            </div>
          )}
        </div>

        {/* 适用门店列表 */}
        {applicableStores.length > 0 && (
          <div className="bg-white rounded-xl border border-gray-200 p-6">
            <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-4">Applicable Stores ({applicableStores.length})</h2>
            <ul className="space-y-1">
              {applicableStores.map(s => (
                <li key={s.id} className="text-sm">
                  <Link href={`/merchants/${s.id}`} className="text-blue-600 hover:underline">{s.name}</Link>
                </li>
              ))}
            </ul>
          </div>
        )}

        {dishesList.length > 0 && (
          <div className="bg-white rounded-xl border border-gray-200 p-6">
            <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-4">Dishes / Included items</h2>
            <ul className="list-disc pl-4 space-y-1 text-sm text-gray-900">
              {dishesList.map((name, i) => (<li key={i}>{name}</li>))}
            </ul>
          </div>
        )}

        <div className="bg-white rounded-xl border border-gray-200 p-6">
          <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-4">Location & Hours</h2>
          <dl className="grid grid-cols-1 sm:grid-cols-2 gap-x-4 gap-y-3 text-sm">
            {deal.address && <div className="sm:col-span-2"><dt className="text-gray-500">Address</dt><dd className="font-medium text-gray-900">{deal.address}</dd></div>}
            {deal.merchant_hours && <div className="sm:col-span-2"><dt className="text-gray-500">Merchant hours</dt><dd className="font-medium text-gray-900">{deal.merchant_hours}</dd></div>}
            {!deal.address && !deal.merchant_hours && <p className="text-gray-500 text-sm">Not provided.</p>}
          </dl>
        </div>

        {deal.refund_policy && (
          <div className="bg-white rounded-xl border border-gray-200 p-6">
            <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-2">Refund policy</h2>
            <p className="text-sm text-gray-900">{deal.refund_policy}</p>
          </div>
        )}

        {deal.image_urls && Array.isArray(deal.image_urls) && deal.image_urls.length > 0 && (
          <div className="bg-white rounded-xl border border-gray-200 p-6">
            <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-4">Images</h2>
            <div className="flex flex-wrap gap-3">
              {(deal.image_urls as string[]).map((url, i) => (
                <a key={i} href={url} target="_blank" rel="noopener noreferrer" className="block w-24 h-24 rounded-lg overflow-hidden border border-gray-200 hover:opacity-90">
                  <img src={url} alt="" className="w-full h-full object-cover" />
                </a>
              ))}
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
