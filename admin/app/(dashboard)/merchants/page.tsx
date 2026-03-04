import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import MerchantActionButtons from '@/components/merchant-action-buttons'

export default async function MerchantsPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  const { data: profile } = await supabase.from('users').select('role').eq('id', user!.id).single()

  if (profile?.role !== 'admin') redirect('/dashboard')

  const { data: merchants } = await supabase
    .from('merchants')
    .select('id, name, category, status, user_id, created_at')
    .order('created_at', { ascending: false })

  const pendingCount = merchants?.filter(m => m.status === 'pending').length ?? 0

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold text-gray-900">Merchants</h1>
        {pendingCount > 0 && (
          <span className="text-sm bg-yellow-100 text-yellow-700 px-3 py-1 rounded-full font-medium">
            {pendingCount} pending review
          </span>
        )}
      </div>

      <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
        <table className="w-full text-sm">
          <thead className="bg-gray-50 border-b border-gray-200">
            <tr>
              <th className="text-left px-4 py-3 font-medium text-gray-600">Name</th>
              <th className="text-left px-4 py-3 font-medium text-gray-600">Category</th>
              <th className="text-left px-4 py-3 font-medium text-gray-600">Status / Action</th>
              <th className="text-left px-4 py-3 font-medium text-gray-600">Applied</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100">
            {merchants?.map(m => (
              <tr key={m.id} className={`hover:bg-gray-50 ${m.status === 'pending' ? 'bg-yellow-50/50' : ''}`}>
                <td className="px-4 py-3 font-medium text-gray-900">{m.name}</td>
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
              </tr>
            ))}
          </tbody>
        </table>
        {(!merchants || merchants.length === 0) && (
          <p className="text-center text-gray-400 py-8">No merchants found</p>
        )}
      </div>
    </div>
  )
}
