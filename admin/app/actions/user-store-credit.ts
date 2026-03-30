'use server'

import { revalidatePath } from 'next/cache'
import { createClient } from '@/lib/supabase/server'
import { getServiceRoleClient } from '@/lib/supabase/service'

async function requireAdmin() {
  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) throw new Error('Unauthorized')

  const { data: profile } = await supabase.from('users').select('role').eq('id', user.id).single()
  if (profile?.role !== 'admin') throw new Error('Forbidden')
}

function round2(n: number): number {
  return Math.round(n * 100) / 100
}

/** 调用 DB RPC：正数增加、负数扣减，流水 type=admin_adjustment */
export async function adminAdjustStoreCredit(userId: string, delta: number, note?: string | null) {
  await requireAdmin()
  const d = round2(delta)
  if (d === 0) return

  const sb = getServiceRoleClient()
  const { error } = await sb.rpc('admin_adjust_store_credit', {
    p_user_id: userId,
    p_delta: d,
    p_note: note?.trim() || null,
  })

  if (error) throw new Error(error.message)
  revalidatePath(`/users/${userId}`)
}

/** 将余额设为目标值（通过 delta 一次 RPC） */
export async function adminSetStoreCreditBalance(userId: string, targetAmount: number, note?: string | null) {
  await requireAdmin()
  const target = round2(targetAmount)
  if (target < 0) throw new Error('Balance cannot be negative')

  const sb = getServiceRoleClient()
  const { data: row } = await sb.from('store_credits').select('amount').eq('user_id', userId).maybeSingle()
  const current = round2(Number(row?.amount ?? 0))
  const delta = round2(target - current)
  if (delta === 0) return

  const { error } = await sb.rpc('admin_adjust_store_credit', {
    p_user_id: userId,
    p_delta: delta,
    p_note: note?.trim() || `Set balance to $${target.toFixed(2)}`,
  })

  if (error) throw new Error(error.message)
  revalidatePath(`/users/${userId}`)
}
