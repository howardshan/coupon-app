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

// 强制禁用员工账号
export async function toggleStaffActive(staffId: string, isActive: boolean) {
  await requireAdmin()
  const supabase = getServiceRoleClient()

  const { error } = await supabase
    .from('merchant_staff')
    .update({ is_active: isActive })
    .eq('id', staffId)

  if (error) throw new Error(error.message)
  revalidatePath('/merchants')
}
