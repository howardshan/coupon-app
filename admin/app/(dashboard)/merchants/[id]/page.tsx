import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import Link from 'next/link'
import MerchantReviewActions from '@/components/merchant-review-actions'

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
    .select('id, user_id, name, company_name, description, contact_name, contact_email, phone, category, ein, address, status, rejection_reason, submitted_at, created_at, updated_at')
    .eq('id', id)
    .single()

  if (!merchant) {
    return (
      <div>
        <p className="text-gray-500">Merchant not found.</p>
        <Link href="/merchants" className="text-blue-600 hover:underline mt-2 inline-block">← Back to Merchants</Link>
      </div>
    )
  }

  const { data: documents } = await supabase
    .from('merchant_documents')
    .select('id, document_type, file_url, file_name, uploaded_at')
    .eq('merchant_id', id)
    .order('uploaded_at', { ascending: true })

  return (
    <div>
      <div className="mb-6 flex items-center justify-between">
        <div>
          <Link href="/merchants" className="text-sm text-gray-500 hover:text-gray-700 mb-1 inline-block">← Back to Merchants</Link>
          <h1 className="text-2xl font-bold text-gray-900">Merchant Review</h1>
        </div>
        <MerchantReviewActions
          merchantId={merchant.id}
          merchantUserId={merchant.user_id}
          status={merchant.status}
          rejectionReason={merchant.rejection_reason}
        />
      </div>

      <div className="space-y-6">
        {/* Status */}
        <div className="bg-white rounded-xl border border-gray-200 p-6">
          <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-3">Status</h2>
          <span className={`inline-block px-3 py-1 rounded-full text-sm font-medium ${
            merchant.status === 'approved' ? 'bg-green-100 text-green-700' :
            merchant.status === 'rejected' ? 'bg-red-100 text-red-700' : 'bg-yellow-100 text-yellow-700'
          }`}>
            {merchant.status}
          </span>
          {merchant.rejection_reason && (
            <p className="mt-2 text-sm text-red-600 bg-red-50 p-3 rounded-lg">Rejection reason: {merchant.rejection_reason}</p>
          )}
        </div>

        {/* Application info */}
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
            <div><dt className="text-gray-500">Submitted at</dt><dd className="font-medium text-gray-900">{merchant.submitted_at ? new Date(merchant.submitted_at).toLocaleString() : (merchant.created_at ? new Date(merchant.created_at).toLocaleString() : '—')}</dd></div>
          </dl>
        </div>

        {/* Documents */}
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
                  <a href={doc.file_url} target="_blank" rel="noopener noreferrer" className="text-sm text-blue-600 hover:underline">
                    View / Download
                  </a>
                </li>
              ))}
            </ul>
          ) : (
            <p className="text-sm text-gray-500">No documents submitted.</p>
          )}
        </div>
      </div>
    </div>
  )
}
