import { createClient } from '@/lib/supabase/server'
import { getServiceRoleClient } from '@/lib/supabase/service'
import { redirect, notFound } from 'next/navigation'
import Link from 'next/link'
import AddBrandAdminForm from '@/components/add-brand-admin-form'
import AddStoreToBrand from '@/components/add-store-to-brand'
import RemoveBrandAdminButton from './remove-brand-admin-button'
import RemoveStoreButton from './remove-store-button'

export default async function BrandDetailPage({
  params,
}: {
  params: Promise<{ id: string }>
}) {
  const { id } = await params
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  const { data: profile } = await supabase.from('users').select('role').eq('id', user!.id).single()

  if (profile?.role !== 'admin') redirect('/dashboard')

  // 使用 service role client 绕过 RLS（admin 页面需要读取所有数据）
  const adminDb = getServiceRoleClient()

  // 品牌基本信息
  const { data: brand } = await adminDb
    .from('brands')
    .select('id, name, logo_url, created_at')
    .eq('id', id)
    .single()

  if (!brand) notFound()

  // 品牌下所有门店
  const { data: stores } = await adminDb
    .from('merchants')
    .select('id, name, category, status, address, created_at')
    .eq('brand_id', id)
    .order('created_at', { ascending: false })

  // 品牌管理员（brand_admins.user_id 指向 auth.users，无法直接 join public.users）
  const { data: rawBrandAdmins } = await adminDb
    .from('brand_admins')
    .select('id, user_id, role, created_at')
    .eq('brand_id', id)
    .order('created_at', { ascending: true })

  // 手动补充用户信息
  const brandAdminUserIds = rawBrandAdmins?.map(a => a.user_id) ?? []
  let brandAdminUsers: Record<string, { email: string; full_name: string | null }> = {}
  if (brandAdminUserIds.length > 0) {
    const { data: users } = await adminDb
      .from('users')
      .select('id, email, full_name')
      .in('id', brandAdminUserIds)
    for (const u of users ?? []) {
      brandAdminUsers[u.id] = { email: u.email, full_name: u.full_name }
    }
  }
  const brandAdmins = rawBrandAdmins?.map(a => ({
    ...a,
    users: brandAdminUsers[a.user_id] ?? null,
  })) ?? []

  // 品牌邀请
  const { data: invitations } = await adminDb
    .from('brand_invitations')
    .select('id, email, role, status, created_at, expires_at')
    .eq('brand_id', id)
    .order('created_at', { ascending: false })
    .limit(20)

  // 品牌下所有 staff（merchant_staff.user_id 也指向 auth.users，无法 join public.users）
  const storeIds = stores?.map(s => s.id) ?? []
  let allStaff: any[] = []
  if (storeIds.length > 0) {
    const { data: rawStaff } = await adminDb
      .from('merchant_staff')
      .select('id, merchant_id, user_id, role, is_active, created_at')
      .in('merchant_id', storeIds)
      .order('created_at', { ascending: false })

    // 手动补充 staff 用户信息
    const staffUserIds = rawStaff?.map(s => s.user_id) ?? []
    let staffUsers: Record<string, { email: string; full_name: string | null }> = {}
    if (staffUserIds.length > 0) {
      const { data: users } = await adminDb
        .from('users')
        .select('id, email, full_name')
        .in('id', staffUserIds)
      for (const u of users ?? []) {
        staffUsers[u.id] = { email: u.email, full_name: u.full_name }
      }
    }
    allStaff = (rawStaff ?? []).map(s => ({
      ...s,
      users: staffUsers[s.user_id] ?? null,
    }))
  }

  // 未关联品牌的已通过门店（给 AddStoreToBrand 下拉用）
  const { data: unlinkedStores } = await adminDb
    .from('merchants')
    .select('id, name, category, address')
    .is('brand_id', null)
    .eq('status', 'approved')
    .order('name', { ascending: true })

  return (
    <div>
      <div className="mb-6">
        <Link
          href="/brands"
          className="mb-3 inline-flex items-center gap-2 px-3 py-2 text-sm font-medium rounded-lg border border-gray-300 bg-white text-gray-700 shadow-sm hover:bg-gray-50 transition-colors"
        >
          ← Back to Brands
        </Link>
        <div className="flex items-center gap-4 mt-2">
          {brand.logo_url ? (
            <img src={brand.logo_url} alt="" className="w-12 h-12 rounded-full object-cover border border-gray-200" />
          ) : (
            <div className="w-12 h-12 rounded-full bg-gray-100 flex items-center justify-center text-gray-400 text-lg font-bold">
              {brand.name?.charAt(0)?.toUpperCase() ?? '?'}
            </div>
          )}
          <h1 className="text-2xl font-bold text-gray-900">{brand.name}</h1>
        </div>
      </div>

      <div className="space-y-6">
        {/* 品牌信息 */}
        <div className="bg-white rounded-xl border border-gray-200 p-6">
          <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-3">Brand Info</h2>
          <dl className="grid grid-cols-1 sm:grid-cols-2 gap-3 text-sm">
            <div><dt className="text-gray-500">Name</dt><dd className="font-medium text-gray-900">{brand.name}</dd></div>
            <div><dt className="text-gray-500">Created</dt><dd className="font-medium text-gray-900">{new Date(brand.created_at).toLocaleString()}</dd></div>
            <div><dt className="text-gray-500">Total Stores</dt><dd className="font-medium text-gray-900">{stores?.length ?? 0}</dd></div>
            <div><dt className="text-gray-500">Total Staff</dt><dd className="font-medium text-gray-900">{allStaff.length}</dd></div>
          </dl>
        </div>

        {/* 门店列表 */}
        <div className="bg-white rounded-xl border border-gray-200 p-6">
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide">
              Member Stores ({stores?.length ?? 0})
            </h2>
            <AddStoreToBrand brandId={id} availableStores={unlinkedStores ?? []} />
          </div>
          {stores && stores.length > 0 ? (
            <table className="w-full text-sm">
              <thead className="border-b border-gray-200">
                <tr>
                  <th className="text-left pb-2 font-medium text-gray-500">Name</th>
                  <th className="text-left pb-2 font-medium text-gray-500">Category</th>
                  <th className="text-left pb-2 font-medium text-gray-500">Status</th>
                  <th className="text-left pb-2 font-medium text-gray-500">Address</th>
                  <th className="text-right pb-2 font-medium text-gray-500">Action</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {stores.map(s => (
                  <tr key={s.id}>
                    <td className="py-2">
                      <Link href={`/merchants/${s.id}`} className="text-blue-600 hover:underline font-medium">
                        {s.name}
                      </Link>
                    </td>
                    <td className="py-2 text-gray-600">{s.category || '—'}</td>
                    <td className="py-2">
                      <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${
                        s.status === 'approved' ? 'bg-green-100 text-green-700' :
                        s.status === 'rejected' ? 'bg-red-100 text-red-700' :
                        s.status === 'closed' ? 'bg-gray-100 text-gray-500' :
                        'bg-yellow-100 text-yellow-700'
                      }`}>
                        {s.status}
                      </span>
                    </td>
                    <td className="py-2 text-gray-500 text-xs">{s.address || '—'}</td>
                    <td className="py-2 text-right">
                      <RemoveStoreButton merchantId={s.id} brandId={id} storeName={s.name} />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          ) : (
            <p className="text-sm text-gray-500">No stores in this brand.</p>
          )}
        </div>

        {/* 品牌管理员 */}
        <div className="bg-white rounded-xl border border-gray-200 p-6">
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide">
              Brand Admins ({brandAdmins?.length ?? 0})
            </h2>
          </div>
          <div className="mb-4">
            <AddBrandAdminForm brandId={id} />
          </div>
          {brandAdmins && brandAdmins.length > 0 ? (
            <table className="w-full text-sm">
              <thead className="border-b border-gray-200">
                <tr>
                  <th className="text-left pb-2 font-medium text-gray-500">User</th>
                  <th className="text-left pb-2 font-medium text-gray-500">Role</th>
                  <th className="text-left pb-2 font-medium text-gray-500">Since</th>
                  <th className="text-right pb-2 font-medium text-gray-500">Action</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {brandAdmins.map((a: any) => (
                  <tr key={a.id}>
                    <td className="py-2 font-medium text-gray-900">
                      {a.users?.full_name || a.users?.email || a.user_id?.slice(0, 8)}
                    </td>
                    <td className="py-2">
                      <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${
                        a.role === 'owner' ? 'bg-purple-100 text-purple-700' : 'bg-blue-100 text-blue-700'
                      }`}>
                        {a.role}
                      </span>
                    </td>
                    <td className="py-2 text-gray-500">{new Date(a.created_at).toLocaleDateString('en-US')}</td>
                    <td className="py-2 text-right">
                      <RemoveBrandAdminButton brandAdminId={a.id} brandId={id} userName={a.users?.email || 'this admin'} />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          ) : (
            <p className="text-sm text-gray-500">No brand admins.</p>
          )}
        </div>

        {/* 邀请记录 */}
        {invitations && invitations.length > 0 && (
          <div className="bg-white rounded-xl border border-gray-200 p-6">
            <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-4">
              Invitations ({invitations.length})
            </h2>
            <table className="w-full text-sm">
              <thead className="border-b border-gray-200">
                <tr>
                  <th className="text-left pb-2 font-medium text-gray-500">Email</th>
                  <th className="text-left pb-2 font-medium text-gray-500">Role</th>
                  <th className="text-left pb-2 font-medium text-gray-500">Status</th>
                  <th className="text-left pb-2 font-medium text-gray-500">Created</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {invitations.map((inv: any) => (
                  <tr key={inv.id}>
                    <td className="py-2 text-gray-900">{inv.email}</td>
                    <td className="py-2 text-gray-600">{inv.role?.replace('_', ' ')}</td>
                    <td className="py-2">
                      <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${
                        inv.status === 'accepted' ? 'bg-green-100 text-green-700' :
                        inv.status === 'expired' ? 'bg-red-100 text-red-700' :
                        'bg-yellow-100 text-yellow-700'
                      }`}>
                        {inv.status}
                      </span>
                    </td>
                    <td className="py-2 text-gray-500">{new Date(inv.created_at).toLocaleDateString('en-US')}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        {/* 全部员工 */}
        {allStaff.length > 0 && (
          <div className="bg-white rounded-xl border border-gray-200 p-6">
            <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-4">
              All Staff Across Stores ({allStaff.length})
            </h2>
            <table className="w-full text-sm">
              <thead className="border-b border-gray-200">
                <tr>
                  <th className="text-left pb-2 font-medium text-gray-500">User</th>
                  <th className="text-left pb-2 font-medium text-gray-500">Store</th>
                  <th className="text-left pb-2 font-medium text-gray-500">Role</th>
                  <th className="text-left pb-2 font-medium text-gray-500">Active</th>
                  <th className="text-left pb-2 font-medium text-gray-500">Since</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {allStaff.map((s: any) => {
                  const storeName = stores?.find(st => st.id === s.merchant_id)?.name ?? s.merchant_id?.slice(0, 8)
                  return (
                    <tr key={s.id}>
                      <td className="py-2 font-medium text-gray-900">
                        {s.users?.full_name || s.users?.email || s.user_id?.slice(0, 8)}
                      </td>
                      <td className="py-2">
                        <Link href={`/merchants/${s.merchant_id}`} className="text-blue-600 hover:underline text-xs">
                          {storeName}
                        </Link>
                      </td>
                      <td className="py-2">
                        <span className="px-2 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-600">
                          {s.role?.replace('_', ' ')}
                        </span>
                      </td>
                      <td className="py-2">
                        {s.is_active ? (
                          <span className="text-green-600 text-xs font-medium">Active</span>
                        ) : (
                          <span className="text-red-500 text-xs font-medium">Disabled</span>
                        )}
                      </td>
                      <td className="py-2 text-gray-500 text-xs">{new Date(s.created_at).toLocaleDateString('en-US')}</td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  )
}
