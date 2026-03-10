'use server'

import { revalidatePath } from 'next/cache'
import { createClient } from '@/lib/supabase/server'
import { getServiceRoleClient } from '@/lib/supabase/service'

async function requireAdmin() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) throw new Error('Unauthorized')

  const { data: profile } = await supabase
    .from('users')
    .select('role')
    .eq('id', user.id)
    .single()

  if (profile?.role !== 'admin') throw new Error('Forbidden')
  return supabase
}

/** 管理员通过退款：调用 create-refund Edge Function 执行 Stripe 退款并更新订单/券/支付状态 */
export async function approveRefund(orderId: string) {
  await requireAdmin()

  const supabase = getServiceRoleClient()
  const { data, error } = await supabase.functions.invoke('create-refund', {
    body: { orderId },
  })

  if (error) throw new Error(error.message)

  const body = data as { error?: string } | null
  if (body?.error) throw new Error(body.error)

  revalidatePath('/orders')
  revalidatePath(`/orders/${orderId}`)
}

/** 管理员拒绝退款：订单状态改回 unused，并写入 refund_rejected_at 供详情页展示 Refund Rejected */
export async function rejectRefund(orderId: string) {
  await requireAdmin()

  const supabase = getServiceRoleClient()
  const { error } = await supabase
    .from('orders')
    .update({
      status: 'unused',
      refund_rejected_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    })
    .eq('id', orderId)

  if (error) throw new Error(error.message)
  revalidatePath('/orders')
  revalidatePath(`/orders/${orderId}`)
}
