import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import Link from 'next/link'
import MerchantReviewActions from '@/components/merchant-review-actions'
import StaffToggleButton from '@/components/staff-toggle-button'

const DOCUMENT_TYPE_LABELS: Record<string, string> = {
  business_license: 'Business License',
  health_permit: 'Health Permit',
  food_service_license: 'Food Service License',
  cosmetology_license: 'Cosmetology License',
  massage_therapy_license: 'Massage Therapy License',
  facility_license: 'Facility License',
  general_business_permit: 'General Business Permit',
  storefront_photo: 'Storefront Photo',
  owner_id: 'Owner ID',
}

export default async function MerchantReviewPage({
  params,
}: {
  params: Promise<{ id: string }>
}) {
  const { id } = await params
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  const { data: profile } = await supabase.from('users').select('role').eq('id', user!.id).single()

  if (profile?.role !== 'admin') redirect('/dashboard')

  const { data: merchant } = await supabase
    .from('merchants')
    .select('id, user_id, name, company_name, description, contact_name, contact_email, phone, category, ein, address, status, rejection_reason, submitted_at, created_at, updated_at, brand_id, brands(id, name, logo_url)')
    .eq('id', id)
    .single()

  if (!merchant) {
    return (
      <div>
        <p className="text-gray-500">Merchant not found.</p>
        <Link href="/merchants" className="mt-3 inline-flex items-center gap-2 px-4 py-2 text-sm font-medium rounded-lg border border-gray-300 bg-white text-gray-700 shadow-sm hover:bg-gray-50 transition-colors">
          ← Back to Merchants
        </Link>
      </div>
    )
  }

  const { data: documents } = await supabase
    .from('merchant_documents')
    .select('id, document_type, file_url, file_name, uploaded_at')
    .eq('merchant_id', id)
    .order('uploaded_at', { ascending: true })

  const { data: staff } = await supabase
    .from('merchant_staff')
    .select('id, role, nickname, is_active, created_at, user_id, users(email, full_name)')
    .eq('merchant_id', id)
    .order('created_at', { ascending: true })

  // brands join 可能返回数组或单对象，统一处理
  const brandsRaw = merchant.brands as any
  const brandInfo = Array.isArray(brandsRaw) ? brandsRaw[0] ?? null : brandsRaw ?? null

  return (
    <div>
      <div className="mb-6 flex items-center justify-between">
        <div>
          <Link href="/merchants" className="mb-3 inline-flex items-center gap-2 px-3 py-2 text-sm font-medium rounded-lg border border-gray-300 bg-white text-gray-700 shadow-sm hover:bg-gray-50 transition-colors">
            ← Back to Merchants
          </Link>
          <h1 className="text-2xl font-bold text-gray-900">Merchant Review</h1>
        </div>
        <MerchantReviewActions merchantId={merchant.id} merchantUserId={merchant.user_id} status={merchant.status} rejectionReason={merchant.rejection_reason} />
      </div>

      <div className="space-y-6">
        <div className="bg-white rounded-xl border border-gray-200 p-6">
          <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-3">Status</h2>
          <span className={`inline-block px-3 py-1 rounded-full text-sm font-medium ${merchant.status === 'approved' ? 'bg-green-100 text-green-700' : merchant.status === 'rejected' ? 'bg-red-100 text-red-700' : 'bg-yellow-100 text-yellow-700'}`}>
            {merchant.status}
          </span>
          {merchant.rejection_reason && (
            <p className="mt-2 text-sm text-red-600 bg-red-50 p-3 rounded-lg">Rejection reason: {merchant.rejection_reason}</p>
          )}
        </div>

        {brandInfo && (
          <div className="bg-white rounded-xl border border-gray-200 p-6">
            <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-3">Brand</h2>
            <div className="flex items-center gap-3">
              {brandInfo.logo_url ? (
                <img src={brandInfo.logo_url} alt="" className="w-8 h-8 rounded-full object-cover border border-gray-200" />
              ) : (
                <div className="w-8 h-8 rounded-full bg-gray-100 flex items-center justify-center text-gray-400 text-xs font-bold">
                  {brandInfo.name?.charAt(0)?.toUpperCase()}
                </div>
              )}
              <Link href={`/brands/${brandInfo.id}`} className="text-blue-600 hover:underline font-medium">
                {brandInfo.name}
              </Link>
            </div>
          </div>
        )}

        <div className="bg-white rounded-xl border border-gray-200 p-6">
          <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-4">Application Information</h2>
          <dl className="grid grid-cols-1 sm:grid-cols-2 gap-x-4 gap-y-3 text-sm">
            <div><dt className="text-gray-500">Company / Display name</dt><dd className="font-medium text-gray-900">{merchant.company_name || merchant.name || '—'}</dd></div>
            <div><dt className="text-gray-500">Contact name</dt><dd className="font-medium text-gray-900">{merchant.contact_name || '—'}</dd></div>
            <div><dt className="text-gray-500">Contact email</dt><dd className="font-medium text-gray-900">{merchant.contact_email || '—'}</dd></div>
            <div><dt className="text-gray-500">Phone</dt><dd className="font-medium text-gray-900">{merchant.phone || '—'}</dd></div>
            <div><dt className="text-gray-500">Category</dt><dd className="font-medium text-gray-900">{merchant.category || '—'}</dd></div>
            <div><dt className="text-gray-500">EIN / Tax ID</dt><dd className="font-medium text-gray-900">{merchant.ein || '—'}</dd></div>
            <div className="sm:col-span-2"><dt className="text-gray-500">Address</dt><dd className="font-medium text-gray-900">{merchant.address || '—'}</dd></div>
            {merchant.description && <div className="sm:col-span-2"><dt className="text-gray-500">Description</dt><dd className="font-medium text-gray-900">{merchant.description}</dd></div>}
            <div><dt className="text-gray-500">Registration type</dt><dd className="font-medium text-gray-900">{brandInfo ? 'Brand / Chain Store' : 'Single Location'}</dd></div>
            <div><dt className="text-gray-500">Submitted at</dt><dd className="font-medium text-gray-900">{merchant.submitted_at ? new Date(merchant.submitted_at).toLocaleString() : (merchant.created_at ? new Date(merchant.created_at).toLocaleString() : '—')}</dd></div>
          </dl>
        </div>

        <div className="bg-white rounded-xl border border-gray-200 p-6">
          <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-4">Submitted Documents</h2>
          {documents && documents.length > 0 ? (
            <ul className="space-y-2">
              {documents.map((doc) => (
                <li key={doc.id} className="flex items-center justify-between py-2 border-b border-gray-100 last:border-0">
                  <span className="text-sm font-medium text-gray-700">
                    {DOCUMENT_TYPE_LABELS[doc.document_type] || doc.document_type}
                    {doc.file_name && <span className="text-gray-500 font-normal ml-2">({doc.file_name})</span>}
                  </span>
                  <a href={doc.file_url} target="_blank" rel="noopener noreferrer" className="inline-flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium rounded-lg border border-blue-200 bg-blue-50 text-blue-700 hover:bg-blue-100 transition-colors">
                    View / Download ↗
                  </a>
                </li>
              ))}
            </ul>
          ) : (
            <p className="text-sm text-gray-500">No documents submitted.</p>
          )}
        </div>

        <div className="bg-white rounded-xl border border-gray-200 p-6">
          <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-4">Staff ({staff?.length ?? 0})</h2>
          {staff && staff.length > 0 ? (
            <table className="w-full text-sm">
              <thead className="border-b border-gray-100">
                <tr>
                  <th className="text-left py-2 font-medium text-gray-500">Name</th>
                  <th className="text-left py-2 font-medium text-gray-500">Email</th>
                  <th className="text-left py-2 font-medium text-gray-500">Role</th>
                  <th className="text-left py-2 font-medium text-gray-500">Status</th>
                  <th className="text-left py-2 font-medium text-gray-500">Joined</th>
                  <th className="text-left py-2 font-medium text-gray-500">Action</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-50">
                {staff.map((s: any) => (
                  <tr key={s.id}>
                    <td className="py-2 text-gray-900">{s.nickname || s.users?.full_name || '—'}</td>
                    <td className="py-2 text-gray-600 text-xs">{s.users?.email || '—'}</td>
                    <td className="py-2">
                      <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${s.role === 'manager' ? 'bg-purple-100 text-purple-700' : s.role === 'cashier' ? 'bg-blue-100 text-blue-700' : 'bg-green-100 text-green-700'}`}>
                        {s.role}
                      </span>
                    </td>
                    <td className="py-2">
                      <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${s.is_active ? 'bg-green-100 text-green-700' : 'bg-red-100 text-red-700'}`}>
                        {s.is_active ? 'Active' : 'Disabled'}
                      </span>
                    </td>
                    <td className="py-2 text-gray-500 text-xs">{new Date(s.created_at).toLocaleDateString()}</td>
                    <td className="py-2">
                      <StaffToggleButton staffId={s.id} isActive={s.is_active} />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          ) : (
            <p className="text-sm text-gray-500">No staff members.</p>
          )}
        </div>
      </div>
    </div>
  )
}
