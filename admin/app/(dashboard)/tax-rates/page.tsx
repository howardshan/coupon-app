import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getServiceRoleClient } from '@/lib/supabase/service'
import TaxRatesClient from './tax-rates-client'

export const dynamic = 'force-dynamic'

export default async function TaxRatesPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  const { data: profile } = await supabase
    .from('users')
    .select('role')
    .eq('id', user!.id)
    .single()

  if (profile?.role !== 'admin') redirect('/dashboard')

  const adminSupabase = getServiceRoleClient()

  // 获取所有税率
  const { data: taxRates } = await adminSupabase
    .from('metro_tax_rates')
    .select('*')
    .order('metro_area')

  // 获取所有 merchants 的 metro_area（用于显示关联数量）
  const { data: merchants } = await adminSupabase
    .from('merchants')
    .select('id, name, city, metro_area')
    .order('name')

  return (
    <TaxRatesClient
      initialTaxRates={taxRates ?? []}
      merchants={merchants ?? []}
    />
  )
}
