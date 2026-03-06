'use server'

import { revalidatePath } from 'next/cache'
import { createClient } from '@/lib/supabase/server'

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

export async function approveRefund(orderId: string) {
  const supabase = await requireAdmin()

  const { error } = await supabase
    .from('orders')
    .update({ status: 'refunded' })
    .eq('id', orderId)

  if (error) throw new Error(error.message)
  revalidatePath('/orders')
}

export async function rejectRefund(orderId: string) {
  const supabase = await requireAdmin()

  const { error } = await supabase
    .from('orders')
    .update({ status: 'used' })
    .eq('id', orderId)

  if (error) throw new Error(error.message)
  revalidatePath('/orders')
}
