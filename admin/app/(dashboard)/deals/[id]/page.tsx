import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import Link from 'next/link'
import RejectionHistory from '@/components/rejection-history'
import DealOperationalActions from '@/components/deal-operational-actions'

/** 只允许回到订单相关页，避免开放重定向 */
function isValidReturnTo(returnTo: string | null | undefined): boolean {
  if (!returnTo || typeof returnTo !== 'string') return false
  const path = returnTo.startsWith('/') ? returnTo : `/${returnTo}`
  return path === '/orders' || path.startsWith('/orders/') || path.startsWith('/orders?')
}

// 菜品解析：支持 "name::qty::subtotal" 格式和对象格式
function parseDish(d: unknown): { name: string; qty?: string; subtotal?: string } {
  if (typeof d === 'string') {
    const parts = d.split('::')
    return { name: parts[0], qty: parts[1], subtotal: parts[2] }
  }
  if (d && typeof d === 'object') {
    const obj = d as Record<string, unknown>
    return {
      name: (obj.name as string) ?? String(d),
      qty: obj.qty != null ? String(obj.qty) : undefined,
      subtotal: obj.subtotal != null ? String(obj.subtotal) : undefined,
    }
  }
  return { name: String(d) }
}

// 有效期类型显示
function validityLabel(type: string | null, days: number | null): string {
  if (!type || type === 'fixed_date') return 'Fixed date'
  if (type === 'short_after_purchase') return `${days ?? '?'} days after purchase (short-term)`
  if (type === 'long_after_purchase') return `${days ?? '?'} days after purchase (long-term)`
  return type
}

// 星期显示
const DAY_LABELS: Record<string, string> = {
  Mon: 'Monday', Tue: 'Tuesday', Wed: 'Wednesday',
  Thu: 'Thursday', Fri: 'Friday', Sat: 'Saturday', Sun: 'Sunday',
}

export default async function DealReviewPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>
  searchParams: Promise<{ returnTo?: string }>
}) {
  const { id } = await params
  const { returnTo } = await searchParams
  const backHref = isValidReturnTo(returnTo) ? returnTo! : '/deals'
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  const { data: profile } = await supabase.from('users').select('role').eq('id', user!.id).single()

  if (profile?.role !== 'admin') redirect('/dashboard')

  // 查询 deal 完整字段
  const { data: deal } = await supabase
    .from('deals')
    .select(`
      id, merchant_id, title, description, category, short_name,
      original_price, discount_price, discount_label, discount_percent,
      image_urls, stock_limit, total_sold, rating, review_count,
      is_featured, is_active, deal_status, rejection_reason, refund_policy, address,
      dishes, merchant_hours, expires_at,
      package_contents, usage_notes, usage_note_images,
      usage_days, max_per_person, is_stackable,
      validity_type, validity_days,
      deal_type, badge_text, deal_category_id, sort_order,
      detail_images, applicable_merchant_ids, store_confirmations,
      created_at, updated_at, published_at,
      merchants(name, address, phone, user_id, brand_id, brands(name)),
      deal_images(id, image_url, sort_order, is_primary)
    `)
    .eq('id', id)
    .single()

  if (!deal) {
    return (
      <div>
        <p className="text-gray-500">Deal not found.</p>
        <Link href={backHref} className="mt-3 inline-flex items-center gap-2 px-4 py-2 text-sm font-medium rounded-lg border border-gray-300 bg-white text-gray-700 shadow-sm hover:bg-gray-50 transition-colors">
          ← Back
        </Link>
      </div>
    )
  }

  const merchantName = (deal.merchants as any)?.name ?? '—'
  const brandName = (deal.merchants as any)?.brands?.name
  const isExpired = deal.expires_at ? new Date(deal.expires_at) < new Date() : false
  const dealStatusStr = deal.deal_status ?? 'inactive'
  // 待审仅走审批中心；有下架或驳回入口时才显示运营区
  const showDealOperations =
    dealStatusStr !== 'pending' &&
    (Boolean(deal.is_active) || dealStatusStr !== 'rejected')

  // 菜品解析
  const dishesRaw = deal.dishes
  const dishesList = Array.isArray(dishesRaw) ? dishesRaw.map(parseDish) : []

  // deal_images 排序
  const dealImages = Array.isArray(deal.deal_images)
    ? [...(deal.deal_images as any[])].sort((a, b) => {
        if (a.is_primary && !b.is_primary) return -1
        if (!a.is_primary && b.is_primary) return 1
        return (a.sort_order ?? 0) - (b.sort_order ?? 0)
      })
    : []

  // 使用须知图片
  const usageNoteImages = Array.isArray(deal.usage_note_images) ? (deal.usage_note_images as string[]) : []

  // 竖版详情图
  const detailImages = Array.isArray(deal.detail_images) ? (deal.detail_images as string[]) : []

  // 使用日期
  const usageDays = Array.isArray(deal.usage_days) ? (deal.usage_days as string[]) : []

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

  // 查询 deal 分类名称
  let dealCategoryName: string | null = null
  if (deal.deal_category_id) {
    const { data: cat } = await supabase
      .from('deal_categories')
      .select('name')
      .eq('id', deal.deal_category_id)
      .single()
    dealCategoryName = cat?.name ?? null
  }

  // 查询选项组
  let optionGroups: any[] = []
  const { data: groups } = await supabase
    .from('deal_option_groups')
    .select('id, name, min_select, max_select, items')
    .eq('deal_id', id)
    .order('created_at', { ascending: true })
  optionGroups = groups ?? []

  // 查询驳回历史记录
  const { data: rejectionHistory } = await supabase
    .from('deal_rejections')
    .select('id, reason, rejected_by, created_at, deal_snapshot, users(email)')
    .eq('deal_id', id)
    .order('created_at', { ascending: false })

  // 门店预确认
  const storeConfirmations = Array.isArray(deal.store_confirmations) ? (deal.store_confirmations as any[]) : []

  return (
    <div>
      <div className="mb-6">
        <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
          <div>
            <Link href={backHref} className="mb-3 inline-flex items-center gap-2 px-3 py-2 text-sm font-medium rounded-lg border border-gray-300 bg-white text-gray-700 shadow-sm hover:bg-gray-50 transition-colors">
              ← Back
            </Link>
            <h1 className="text-2xl font-bold text-gray-900">Deal Detail</h1>
          </div>
          {showDealOperations && (
            <div className="shrink-0">
              <p className="mb-2 text-xs font-medium text-gray-500 uppercase tracking-wide sm:text-right">
                Operations
              </p>
              <DealOperationalActions
                dealId={deal.id}
                isActive={Boolean(deal.is_active)}
                dealStatus={dealStatusStr}
              />
            </div>
          )}
        </div>
        {/* 审批操作已移至统一审批中心 */}
        {deal.deal_status === 'pending' && (
          <div className="mt-3 flex items-center gap-3 rounded-lg border border-yellow-200 bg-yellow-50 px-4 py-3">
            <span className="text-sm text-yellow-800">
              This deal is pending review.
            </span>
            <Link
              href={`/approvals?tab=deals`}
              className="text-sm font-semibold text-yellow-700 underline hover:text-yellow-900"
            >
              Review in Approvals Center →
            </Link>
          </div>
        )}
      </div>

      <div className="space-y-6">

        {/* ── Status ── */}
        <div className="bg-white rounded-xl border border-gray-200 p-6">
          <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-3">Status</h2>
          <div className="flex flex-wrap items-center gap-2">
            <span className={`inline-block px-3 py-1 rounded-full text-sm font-medium ${
              isExpired ? 'bg-red-100 text-red-700'
              : deal.deal_status === 'rejected' ? 'bg-red-100 text-red-700'
              : deal.deal_status === 'pending' ? 'bg-yellow-100 text-yellow-700'
              : deal.is_active ? 'bg-green-100 text-green-700'
              : 'bg-gray-100 text-gray-600'
            }`}>
              {isExpired ? 'expired' : deal.deal_status ?? (deal.is_active ? 'active' : 'inactive')}
            </span>
            {deal.is_featured && (
              <span className="inline-block px-3 py-1 rounded-full text-sm font-medium bg-amber-100 text-amber-700">Featured</span>
            )}
            {deal.deal_type && deal.deal_type !== 'regular' && (
              <span className="inline-block px-3 py-1 rounded-full text-sm font-medium bg-indigo-100 text-indigo-700">{deal.deal_type}</span>
            )}
            {deal.badge_text && (
              <span className="inline-block px-3 py-1 rounded-full text-sm font-medium bg-pink-100 text-pink-700">{deal.badge_text}</span>
            )}
          </div>
          <RejectionHistory records={rejectionHistory ?? []} />
        </div>

        {/* ── Basic Information ── */}
        <div className="bg-white rounded-xl border border-gray-200 p-6">
          <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-4">Basic Information</h2>
          <dl className="grid grid-cols-1 sm:grid-cols-2 gap-x-4 gap-y-3 text-sm">
            <div><dt className="text-gray-500">Title</dt><dd className="font-medium text-gray-900">{deal.title}</dd></div>
            {deal.short_name && <div><dt className="text-gray-500">Short name</dt><dd className="font-medium text-gray-900">{deal.short_name}</dd></div>}
            <div>
              <dt className="text-gray-500">Merchant</dt>
              <dd className="font-medium text-gray-900">
                <Link href={`/merchants/${deal.merchant_id}`} className="text-blue-600 hover:underline">{merchantName}</Link>
                {brandName && <span className="text-xs text-purple-600 ml-1">({brandName})</span>}
              </dd>
            </div>
            <div><dt className="text-gray-500">Category</dt><dd className="font-medium text-gray-900">{deal.category || '—'}</dd></div>
            {dealCategoryName && <div><dt className="text-gray-500">Deal category</dt><dd className="font-medium text-gray-900">{dealCategoryName}</dd></div>}
            <div><dt className="text-gray-500">Original price</dt><dd className="font-medium text-gray-900">${deal.original_price}</dd></div>
            <div>
              <dt className="text-gray-500">Sale price</dt>
              <dd className="font-medium text-gray-900">
                ${deal.discount_price}
                {deal.discount_percent != null && (
                  <span className="ml-2 text-xs text-red-600 font-semibold">{deal.discount_percent}% OFF</span>
                )}
              </dd>
            </div>
            {deal.discount_label && <div><dt className="text-gray-500">Discount label</dt><dd className="font-medium text-gray-900">{deal.discount_label}</dd></div>}
            <div><dt className="text-gray-500">Stock limit</dt><dd className="font-medium text-gray-900">{deal.stock_limit === -1 ? 'Unlimited' : (deal.stock_limit ?? '—')}</dd></div>
            <div><dt className="text-gray-500">Total sold</dt><dd className="font-medium text-gray-900">{deal.total_sold ?? 0}</dd></div>
            <div><dt className="text-gray-500">Rating</dt><dd className="font-medium text-gray-900">{(deal.rating ?? 0)} ({deal.review_count ?? 0} reviews)</dd></div>
            {deal.sort_order != null && <div><dt className="text-gray-500">Sort order</dt><dd className="font-medium text-gray-900">{deal.sort_order}</dd></div>}
            <div><dt className="text-gray-500">Created</dt><dd className="font-medium text-gray-900">{deal.created_at ? new Date(deal.created_at).toLocaleString() : '—'}</dd></div>
            {deal.updated_at && <div><dt className="text-gray-500">Updated</dt><dd className="font-medium text-gray-900">{new Date(deal.updated_at).toLocaleString()}</dd></div>}
            {deal.published_at && <div><dt className="text-gray-500">Published</dt><dd className="font-medium text-gray-900">{new Date(deal.published_at).toLocaleString()}</dd></div>}
          </dl>

          {/* Description */}
          {deal.description && (
            <div className="mt-4 pt-4 border-t border-gray-100">
              <dt className="text-gray-500 text-sm font-medium mb-1">Description</dt>
              <dd className="text-gray-900 text-sm whitespace-pre-wrap">{deal.description}</dd>
            </div>
          )}
        </div>

        {/* ── Validity & Rules ── */}
        <div className="bg-white rounded-xl border border-gray-200 p-6">
          <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-4">Validity & Usage Rules</h2>
          <dl className="grid grid-cols-1 sm:grid-cols-2 gap-x-4 gap-y-3 text-sm">
            <div>
              <dt className="text-gray-500">Validity type</dt>
              <dd className="font-medium text-gray-900">{validityLabel(deal.validity_type, deal.validity_days)}</dd>
            </div>
            <div><dt className="text-gray-500">Expires at</dt><dd className="font-medium text-gray-900">{deal.expires_at ? new Date(deal.expires_at).toLocaleString() : '—'}</dd></div>
            <div>
              <dt className="text-gray-500">Usage days</dt>
              <dd className="font-medium text-gray-900">
                {usageDays.length === 0 ? 'All week' : usageDays.map(d => DAY_LABELS[d] ?? d).join(', ')}
              </dd>
            </div>
            <div><dt className="text-gray-500">Max per person</dt><dd className="font-medium text-gray-900">{deal.max_per_person ?? 'No limit'}</dd></div>
            <div><dt className="text-gray-500">Stackable</dt><dd className="font-medium text-gray-900">{deal.is_stackable ? 'Yes' : 'No'}</dd></div>
          </dl>
        </div>

        {/* ── Package Contents ── */}
        {deal.package_contents && (
          <div className="bg-white rounded-xl border border-gray-200 p-6">
            <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-3">Package Contents</h2>
            <p className="text-sm text-gray-900 whitespace-pre-wrap">{deal.package_contents}</p>
          </div>
        )}

        {/* ── Dishes / Products ── */}
        {dishesList.length > 0 && (
          <div className="bg-white rounded-xl border border-gray-200 p-6">
            <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-4">Dishes / Included Items ({dishesList.length})</h2>
            <table className="w-full text-sm">
              <thead className="bg-gray-50 border-b border-gray-200">
                <tr>
                  <th className="text-left px-3 py-2 font-medium text-gray-600">Item</th>
                  <th className="text-left px-3 py-2 font-medium text-gray-600">Qty</th>
                  <th className="text-left px-3 py-2 font-medium text-gray-600">Subtotal</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {dishesList.map((d, i) => (
                  <tr key={i}>
                    <td className="px-3 py-2 text-gray-900">{d.name}</td>
                    <td className="px-3 py-2 text-gray-600">{d.qty ?? '—'}</td>
                    <td className="px-3 py-2 text-gray-600">{d.subtotal ? `$${d.subtotal}` : '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        {/* ── Option Groups ── */}
        {optionGroups.length > 0 && (
          <div className="bg-white rounded-xl border border-gray-200 p-6">
            <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-4">Option Groups ({optionGroups.length})</h2>
            <div className="space-y-4">
              {optionGroups.map((g: any) => (
                <div key={g.id} className="border border-gray-100 rounded-lg p-4">
                  <div className="flex items-center gap-2 mb-2">
                    <span className="font-medium text-gray-900">{g.name}</span>
                    <span className="text-xs text-gray-500">
                      (choose {g.min_select ?? 0}–{g.max_select ?? '∞'})
                    </span>
                  </div>
                  {Array.isArray(g.items) && g.items.length > 0 && (
                    <ul className="list-disc pl-5 space-y-0.5 text-sm text-gray-700">
                      {(g.items as any[]).map((item: any, j: number) => (
                        <li key={j}>
                          {typeof item === 'string' ? item : (item?.name ?? JSON.stringify(item))}
                          {item?.price != null && <span className="text-gray-500 ml-1">(+${item.price})</span>}
                        </li>
                      ))}
                    </ul>
                  )}
                </div>
              ))}
            </div>
          </div>
        )}

        {/* ── Usage Notes ── */}
        {(deal.usage_notes || usageNoteImages.length > 0) && (
          <div className="bg-white rounded-xl border border-gray-200 p-6">
            <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-3">Usage Notes</h2>
            {deal.usage_notes && (
              <p className="text-sm text-gray-900 whitespace-pre-wrap mb-3">{deal.usage_notes}</p>
            )}
            {usageNoteImages.length > 0 && (
              <div className="flex flex-wrap gap-3">
                {usageNoteImages.map((url, i) => (
                  <a key={i} href={url} target="_blank" rel="noopener noreferrer" className="block w-28 h-28 rounded-lg overflow-hidden border border-gray-200 hover:opacity-90">
                    <img src={url} alt={`Usage note ${i + 1}`} className="w-full h-full object-cover" />
                  </a>
                ))}
              </div>
            )}
          </div>
        )}

        {/* ── Applicable Stores ── */}
        {applicableStores.length > 0 && (
          <div className="bg-white rounded-xl border border-gray-200 p-6">
            <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-4">Applicable Stores ({applicableStores.length})</h2>
            <ul className="space-y-1">
              {applicableStores.map(s => {
                const confirmed = storeConfirmations.find((c: any) => c.store_id === s.id)
                return (
                  <li key={s.id} className="text-sm flex items-center gap-2">
                    <Link href={`/merchants/${s.id}`} className="text-blue-600 hover:underline">{s.name}</Link>
                    {confirmed?.pre_confirmed && (
                      <span className="text-xs px-1.5 py-0.5 rounded bg-green-100 text-green-700">Confirmed</span>
                    )}
                  </li>
                )
              })}
            </ul>
          </div>
        )}

        {/* ── Location & Hours ── */}
        <div className="bg-white rounded-xl border border-gray-200 p-6">
          <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-4">Location & Hours</h2>
          <dl className="grid grid-cols-1 sm:grid-cols-2 gap-x-4 gap-y-3 text-sm">
            {(deal.address || (deal.merchants as any)?.address) && (
              <div className="sm:col-span-2">
                <dt className="text-gray-500">Address</dt>
                <dd className="font-medium text-gray-900">
                  {deal.address || (deal.merchants as any)?.address}
                  {!deal.address && (deal.merchants as any)?.address && <span className="text-xs text-gray-400 ml-1">(from merchant)</span>}
                </dd>
              </div>
            )}
            {(deal.merchants as any)?.phone && (
              <div className="sm:col-span-2">
                <dt className="text-gray-500">Phone</dt>
                <dd className="font-medium text-gray-900">{(deal.merchants as any).phone}</dd>
              </div>
            )}
            {deal.merchant_hours && <div className="sm:col-span-2"><dt className="text-gray-500">Merchant hours</dt><dd className="font-medium text-gray-900">{deal.merchant_hours}</dd></div>}
            {!deal.address && !(deal.merchants as any)?.address && !deal.merchant_hours && <p className="text-gray-500 text-sm">Not provided.</p>}
          </dl>
        </div>

        {/* ── Refund Policy ── */}
        {deal.refund_policy && (
          <div className="bg-white rounded-xl border border-gray-200 p-6">
            <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-2">Refund Policy</h2>
            <p className="text-sm text-gray-900">{deal.refund_policy}</p>
          </div>
        )}

        {/* ── Cover Images (image_urls) ── */}
        {deal.image_urls && Array.isArray(deal.image_urls) && deal.image_urls.length > 0 && (
          <div className="bg-white rounded-xl border border-gray-200 p-6">
            <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-4">Cover Images ({(deal.image_urls as string[]).length})</h2>
            <div className="flex flex-wrap gap-3">
              {(deal.image_urls as string[]).map((url, i) => (
                <a key={i} href={url} target="_blank" rel="noopener noreferrer" className="block w-32 h-32 rounded-lg overflow-hidden border border-gray-200 hover:opacity-90">
                  <img src={url} alt={`Cover ${i + 1}`} className="w-full h-full object-cover" />
                </a>
              ))}
            </div>
          </div>
        )}

        {/* ── Deal Images (deal_images table) ── */}
        {dealImages.length > 0 && (
          <div className="bg-white rounded-xl border border-gray-200 p-6">
            <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-4">Gallery Images ({dealImages.length})</h2>
            <div className="flex flex-wrap gap-3">
              {dealImages.map((img: any) => (
                <a key={img.id} href={img.image_url} target="_blank" rel="noopener noreferrer" className="relative block w-32 h-32 rounded-lg overflow-hidden border border-gray-200 hover:opacity-90">
                  <img src={img.image_url} alt="" className="w-full h-full object-cover" />
                  {img.is_primary && (
                    <span className="absolute top-1 left-1 text-[10px] px-1.5 py-0.5 rounded bg-blue-600 text-white font-medium">Primary</span>
                  )}
                </a>
              ))}
            </div>
          </div>
        )}

        {/* ── Detail Images (竖版详情图) ── */}
        {detailImages.length > 0 && (
          <div className="bg-white rounded-xl border border-gray-200 p-6">
            <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-4">Detail Images ({detailImages.length})</h2>
            <div className="space-y-3">
              {detailImages.map((url, i) => (
                <a key={i} href={url} target="_blank" rel="noopener noreferrer" className="block max-w-md rounded-lg overflow-hidden border border-gray-200 hover:opacity-90">
                  <img src={url} alt={`Detail ${i + 1}`} className="w-full h-auto object-contain" />
                </a>
              ))}
            </div>
          </div>
        )}

      </div>
    </div>
  )
}
