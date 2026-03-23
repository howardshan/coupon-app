import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import Link from 'next/link'

export default async function ClosuresPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  const { data: profile } = await supabase.from('users').select('role').eq('id', user!.id).single()

  if (profile?.role !== 'admin') redirect('/dashboard')

  const { data: closedMerchants } = await supabase
    .from('merchants')
    .select('id, name, status, updated_at, brand_id, brands(id, name)')
    .eq('status', 'closed')
    .order('updated_at', { ascending: false })

  const { data: rejectedMerchants } = await supabase
    .from('merchants')
    .select('id, name, status, rejection_reason, updated_at, brand_id, brands(id, name)')
    .eq('status', 'rejected')
    .order('updated_at', { ascending: false })
    .limit(50)

  const { data: cancelledInvitations } = await supabase
    .from('brand_invitations')
    .select('id, invited_email, role, status, brand_id, merchant_id, created_at, brands(name), merchants(name)')
    .in('status', ['cancelled', 'expired'])
    .order('created_at', { ascending: false })
    .limit(50)

  const { data: refundedOrders } = await supabase
    .from('orders')
    .select('id, total_amount, merchant_id, status, updated_at, merchants(name)')
    .eq('status', 'refunded')
    .order('updated_at', { ascending: false })
    .limit(50)

  const closedMerchantIds = new Set(closedMerchants?.map(m => m.id) ?? [])
  const closureRefunds = refundedOrders?.filter((o: any) => closedMerchantIds.has(o.merchant_id)) ?? []
  const totalRefundAmount = closureRefunds.reduce((sum: number, o: any) => sum + Number(o.total_amount), 0)

  return (
    <div>
      <h1 className="text-2xl font-bold text-gray-900 mb-6">Closures & Disassociations</h1>

      <div className="space-y-6">
        <div className="bg-white rounded-xl border border-gray-200 p-6">
          <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-4">
            Closed Stores ({closedMerchants?.length ?? 0})
            {totalRefundAmount > 0 && (
              <span className="ml-2 text-red-600 normal-case font-normal">
                Total refunds: ${totalRefundAmount.toFixed(2)}
              </span>
            )}
          </h2>
          {closedMerchants && closedMerchants.length > 0 ? (
            <table className="w-full text-sm">
              <thead className="border-b border-gray-100">
                <tr>
                  <th className="text-left py-2 font-medium text-gray-500">Store</th>
                  <th className="text-left py-2 font-medium text-gray-500">Brand</th>
                  <th className="text-left py-2 font-medium text-gray-500">Closed At</th>
                  <th className="text-left py-2 font-medium text-gray-500">Refunded</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-50">
                {closedMerchants.map((m: any) => {
                  const merchantRefunds = closureRefunds.filter((o: any) => o.merchant_id === m.id)
                  const refundSum = merchantRefunds.reduce((s: number, o: any) => s + Number(o.total_amount), 0)
                  return (
                    <tr key={m.id}>
                      <td className="py-2">
                        <Link href={`/merchants/${m.id}`} className="text-blue-600 hover:underline font-medium">{m.name}</Link>
                      </td>
                      <td className="py-2 text-gray-600 text-xs">
                        {m.brands ? (
                          <Link href={`/brands/${m.brands.id}`} className="text-purple-600 hover:underline">{m.brands.name}</Link>
                        ) : '—'}
                      </td>
                      <td className="py-2 text-gray-500 text-xs">{new Date(m.updated_at).toLocaleString()}</td>
                      <td className="py-2 text-red-600 font-medium">{refundSum > 0 ? `$${refundSum.toFixed(2)}` : '—'}</td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          ) : (
            <p className="text-sm text-gray-500">No closed stores.</p>
          )}
        </div>

        <div className="bg-white rounded-xl border border-gray-200 p-6">
          <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-4">Brand Disassociations</h2>
          {cancelledInvitations && cancelledInvitations.length > 0 ? (
            <table className="w-full text-sm">
              <thead className="border-b border-gray-100">
                <tr>
                  <th className="text-left py-2 font-medium text-gray-500">Brand</th>
                  <th className="text-left py-2 font-medium text-gray-500">Store/Email</th>
                  <th className="text-left py-2 font-medium text-gray-500">Role</th>
                  <th className="text-left py-2 font-medium text-gray-500">Status</th>
                  <th className="text-left py-2 font-medium text-gray-500">Date</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-50">
                {cancelledInvitations.map((inv: any) => (
                  <tr key={inv.id}>
                    <td className="py-2 text-gray-900">{inv.brands?.name ?? '—'}</td>
                    <td className="py-2 text-gray-600 text-xs">{inv.merchants?.name ?? inv.invited_email}</td>
                    <td className="py-2 text-gray-600">{inv.role}</td>
                    <td className="py-2">
                      <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${inv.status === 'cancelled' ? 'bg-red-100 text-red-700' : 'bg-gray-100 text-gray-600'}`}>
                        {inv.status}
                      </span>
                    </td>
                    <td className="py-2 text-gray-500 text-xs">{new Date(inv.created_at).toLocaleDateString('en-US')}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          ) : (
            <p className="text-sm text-gray-500">No disassociation records.</p>
          )}
        </div>

        <div className="bg-white rounded-xl border border-gray-200 p-6">
          <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-4">Rejected Merchants ({rejectedMerchants?.length ?? 0})</h2>
          {rejectedMerchants && rejectedMerchants.length > 0 ? (
            <table className="w-full text-sm">
              <thead className="border-b border-gray-100">
                <tr>
                  <th className="text-left py-2 font-medium text-gray-500">Store</th>
                  <th className="text-left py-2 font-medium text-gray-500">Reason</th>
                  <th className="text-left py-2 font-medium text-gray-500">Date</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-50">
                {rejectedMerchants.map((m: any) => (
                  <tr key={m.id}>
                    <td className="py-2">
                      <Link href={`/merchants/${m.id}`} className="text-blue-600 hover:underline font-medium">{m.name}</Link>
                    </td>
                    <td className="py-2 text-gray-600 text-xs">{m.rejection_reason || '—'}</td>
                    <td className="py-2 text-gray-500 text-xs">{new Date(m.updated_at).toLocaleString()}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          ) : (
            <p className="text-sm text-gray-500">No rejected merchants.</p>
          )}
        </div>
      </div>
    </div>
  )
}
