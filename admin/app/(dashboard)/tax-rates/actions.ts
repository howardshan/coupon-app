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
}

/** 添加或更新 metro 税率 */
export async function upsertTaxRate(metroArea: string, taxRate: number) {
  await requireAdmin()
  const supabase = getServiceRoleClient()

  const { error } = await supabase
    .from('metro_tax_rates')
    .upsert(
      {
        metro_area: metroArea.trim(),
        tax_rate: taxRate,
        updated_at: new Date().toISOString(),
      },
      { onConflict: 'metro_area' }
    )

  if (error) throw new Error(error.message)
  revalidatePath('/tax-rates')
}

/** 删除 metro 税率 */
export async function deleteTaxRate(id: string) {
  await requireAdmin()
  const supabase = getServiceRoleClient()

  const { error } = await supabase
    .from('metro_tax_rates')
    .delete()
    .eq('id', id)

  if (error) throw new Error(error.message)
  revalidatePath('/tax-rates')
}

/** 更新 merchant 的 metro_area */
export async function updateMerchantMetro(merchantId: string, metroArea: string | null) {
  await requireAdmin()
  const supabase = getServiceRoleClient()

  const { error } = await supabase
    .from('merchants')
    .update({
      metro_area: metroArea || null,
      updated_at: new Date().toISOString(),
    })
    .eq('id', merchantId)

  if (error) throw new Error(error.message)
  revalidatePath('/tax-rates')
}

/** 批量更新 merchants 的 metro_area（按 city 匹配） */
export async function bulkAssignMetroByCity(city: string, metroArea: string) {
  await requireAdmin()
  const supabase = getServiceRoleClient()

  const { error } = await supabase
    .from('merchants')
    .update({
      metro_area: metroArea,
      updated_at: new Date().toISOString(),
    })
    .ilike('city', city)

  if (error) throw new Error(error.message)
  revalidatePath('/tax-rates')
}
