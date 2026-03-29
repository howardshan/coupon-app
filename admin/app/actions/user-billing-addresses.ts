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

/** 同一用户仅允许一个默认地址（部分唯一索引 idx_billing_addresses_user_default） */
async function clearDefaultForUser(userId: string) {
  const sb = getServiceRoleClient()
  const { error } = await sb.from('billing_addresses').update({ is_default: false }).eq('user_id', userId)
  if (error) throw new Error(error.message)
}

export type BillingAddressFormValues = {
  label: string
  address_line1: string
  address_line2: string
  city: string
  state: string
  postal_code: string
  country: string
  is_default: boolean
}

function normalizeForm(v: BillingAddressFormValues) {
  return {
    label: v.label.trim(),
    address_line1: v.address_line1.trim(),
    address_line2: v.address_line2.trim(),
    city: v.city.trim(),
    state: v.state.trim(),
    postal_code: v.postal_code.trim(),
    country: v.country.trim() || 'US',
    is_default: !!v.is_default,
  }
}

export async function createUserBillingAddress(userId: string, form: BillingAddressFormValues) {
  await requireAdmin()
  const row = normalizeForm(form)
  if (!row.address_line1) throw new Error('Address line 1 is required')

  const sb = getServiceRoleClient()
  if (row.is_default) await clearDefaultForUser(userId)

  const { error } = await sb.from('billing_addresses').insert({
    user_id: userId,
    label: row.label,
    address_line1: row.address_line1,
    address_line2: row.address_line2,
    city: row.city,
    state: row.state,
    postal_code: row.postal_code,
    country: row.country,
    is_default: row.is_default,
  })

  if (error) throw new Error(error.message)
  revalidatePath(`/users/${userId}`)
}

export async function updateUserBillingAddress(
  userId: string,
  addressId: string,
  form: BillingAddressFormValues
) {
  await requireAdmin()
  const row = normalizeForm(form)
  if (!row.address_line1) throw new Error('Address line 1 is required')

  const sb = getServiceRoleClient()
  const { data: existing, error: fetchErr } = await sb
    .from('billing_addresses')
    .select('id')
    .eq('id', addressId)
    .eq('user_id', userId)
    .maybeSingle()

  if (fetchErr) throw new Error(fetchErr.message)
  if (!existing) throw new Error('Address not found')

  if (row.is_default) await clearDefaultForUser(userId)

  const { error } = await sb
    .from('billing_addresses')
    .update({
      label: row.label,
      address_line1: row.address_line1,
      address_line2: row.address_line2,
      city: row.city,
      state: row.state,
      postal_code: row.postal_code,
      country: row.country,
      is_default: row.is_default,
      updated_at: new Date().toISOString(),
    })
    .eq('id', addressId)
    .eq('user_id', userId)

  if (error) throw new Error(error.message)
  revalidatePath(`/users/${userId}`)
}

export async function deleteUserBillingAddress(userId: string, addressId: string) {
  await requireAdmin()
  const sb = getServiceRoleClient()
  const { error } = await sb.from('billing_addresses').delete().eq('id', addressId).eq('user_id', userId)
  if (error) throw new Error(error.message)
  revalidatePath(`/users/${userId}`)
}

export async function setDefaultUserBillingAddress(userId: string, addressId: string) {
  await requireAdmin()
  const sb = getServiceRoleClient()
  const { data: existing, error: fetchErr } = await sb
    .from('billing_addresses')
    .select('id')
    .eq('id', addressId)
    .eq('user_id', userId)
    .maybeSingle()

  if (fetchErr) throw new Error(fetchErr.message)
  if (!existing) throw new Error('Address not found')

  await clearDefaultForUser(userId)
  const { error } = await sb
    .from('billing_addresses')
    .update({ is_default: true, updated_at: new Date().toISOString() })
    .eq('id', addressId)
    .eq('user_id', userId)

  if (error) throw new Error(error.message)
  revalidatePath(`/users/${userId}`)
}
