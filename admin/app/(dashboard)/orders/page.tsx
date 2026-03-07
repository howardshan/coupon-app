import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import Link from 'next/link'
import OrderRefundButtons from '@/components/order-refund-buttons'
import OrderSearchForm from '@/components/order-search-form'

export default async function OrdersPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string }>
}) {
  const { q } = await searchParams
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  const { data: profile } = await supabase
    .from('users')
    .select('role')
    .eq('id', user!.id)
    .single()

  if (profile?.role !== 'admin') redirect('/dashboard')

  let orders: any[] | null

  if (q != null && q.trim() !== '') {
    const { data } = await supabase.rpc('get_admin_orders_search', { search_q: q.trim() })
    orders = data ?? null
  } else {
    const { data } = await supabase
      .from('orders')
      .select(`
        id,
        order_number,
        total_amount,
        quantity,
        status,
        refund_reason,
        created_at,
        users ( email ),
        deals ( title, merchants ( name ) )
      `)
      .order('created_at', { ascending: false })
      .limit(100)
    orders = data
  }

  const refundCount = orders?.filter((o: { status: string }) => o.status === 'refund_requested').length ?? 0

  return (
    <div>
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4 mb-6">
        <div className="flex items-center gap-3 flex-wrap">
          <h1 className="text-2xl font-bold text-gray-900">Orders</h1>
          {refundCount > 0 && (
            <span className="text-sm bg-orange-100 text-orange-700 px-3 py-1 rounded-full font-medium">
              {refundCount} refund {refundCount === 1 ? 'request' : 'requests'}
            </span>
          )}
        </div>
        <OrderSearchForm initialValue={q ?? ''} />
      </div>

      <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
        <table className="w-full text-sm">
          <thead className="bg-gray-50 border-b border-gray-200">
            <tr>
              <th className="text-left px-4 py-3 font-medium text-gray-600">Order #</th>
              <th className="text-left px-4 py-3 font-medium text-gray-600">Deal</th>
              <th className="text-left px-4 py-3 font-medium text-gray-600">Merchant</th>
              <th className="text-left px-4 py-3 font-medium text-gray-600">Customer</th>
              <th className="text-left px-4 py-3 font-medium text-gray-600">Amount</th>
              <th className="text-left px-4 py-3 font-medium text-gray-600">Status</th>
              <th className="text-left px-4 py-3 font-medium text-gray-600">Date</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100">
            {(orders as any[])?.map((o: any) => (
              <tr
                key={o.id}
                className={o.status === 'refund_requested' ? 'bg-orange-50/60' : 'hover:bg-gray-50'}
              >
                <td className="px-4 py-3 font-mono text-gray-700">
                  <Link href={`/orders/${o.id}`} className="text-blue-600 hover:underline">
                    {o.order_number ?? `DJ-${String(o.id).slice(0, 8).toUpperCase()}`}
                  </Link>
                </td>
                <td className="px-4 py-3 font-medium text-gray-900">
                  <Link href={`/orders/${o.id}`} className="text-blue-600 hover:underline">
                    {o.deals?.title ?? '—'}
                  </Link>
                </td>
                <td className="px-4 py-3 text-gray-600">{o.deals?.merchants?.name ?? '—'}</td>
                <td className="px-4 py-3 text-gray-600">{o.users?.email ?? '—'}</td>
                <td className="px-4 py-3 text-gray-900">
                  ${o.total_amount}
                  {o.quantity > 1 && (
                    <span className="text-gray-400 text-xs ml-1">×{o.quantity}</span>
                  )}
                </td>
                <td className="px-4 py-3">
                  <OrderRefundButtons orderId={o.id} initialStatus={o.status} />
                </td>
                <td className="px-4 py-3 text-gray-500">
                  {new Date(o.created_at).toLocaleDateString()}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        {(!orders || orders.length === 0) && (
          <p className="text-center text-gray-400 py-8">
            {q != null && q.trim() !== '' ? 'No orders match your search.' : 'No orders yet'}
          </p>
        )}
      </div>
    </div>
  )
}
