'use server'

import { createClient } from '@/lib/supabase/server'
import { getServiceRoleClient } from '@/lib/supabase/service'

async function requireAdmin() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) throw new Error('Unauthorized')
  const { data: profile } = await supabase
    .from('users').select('role').eq('id', user.id).single()
  if (profile?.role !== 'admin') throw new Error('Forbidden')
  return user
}

export async function getDealsAndMerchants() {
  await requireAdmin()
  const db = getServiceRoleClient()
  const [{ data: deals }, { data: merchants }] = await Promise.all([
    db.from('deals')
      .select('id, title, merchant_id, merchants(lat, lng, name)')
      .eq('is_active', true)
      .order('created_at', { ascending: false })
      .limit(200),
    db.from('merchants')
      .select('id, name, lat, lng')
      .eq('status', 'active')
      .order('name')
      .limit(200),
  ])
  return { deals: deals ?? [], merchants: merchants ?? [] }
}

export async function previewGeoNotification(
  lat: number,
  lng: number,
  radiusMeters: number
): Promise<{ count: number; error?: string }> {
  try {
    await requireAdmin()
    if (isNaN(lat) || isNaN(lng) || lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      return { count: 0, error: 'Invalid coordinates' }
    }
    const db = getServiceRoleClient()
    const { data, error } = await db.rpc('find_users_for_geo_push', {
      p_lat: lat,
      p_lng: lng,
      p_radius_m: radiusMeters,
    })
    if (error) return { count: 0, error: error.message }
    return { count: (data ?? []).length }
  } catch (e) {
    return { count: 0, error: (e as Error).message }
  }
}

export async function sendGeoNotification(payload: {
  title: string
  body: string
  dealId?: string
  merchantId?: string
  targetLat: number
  targetLng: number
  radiusMeters: number
}): Promise<{ success: boolean; sentCount?: number; error?: string }> {
  try {
    if (payload.title.length > 65 || payload.body.length > 178) {
      return { success: false, error: 'Title or body exceeds max length' }
    }
    if (
      isNaN(payload.targetLat) || isNaN(payload.targetLng) ||
      payload.targetLat < -90 || payload.targetLat > 90 ||
      payload.targetLng < -180 || payload.targetLng > 180
    ) {
      return { success: false, error: 'Invalid coordinates' }
    }
    const user = await requireAdmin()
    const resp = await fetch(
      `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/send-geo-push`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY}`,
        },
        body: JSON.stringify({
          title: payload.title,
          body: payload.body,
          deal_id: payload.dealId,
          merchant_id: payload.merchantId,
          target_lat: payload.targetLat,
          target_lng: payload.targetLng,
          radius_meters: payload.radiusMeters,
          created_by: user.id,
        }),
      }
    )
    if (!resp.ok) {
      const errText = await resp.text().catch(() => 'Unknown error')
      return { success: false, error: errText }
    }
    const result = await resp.json()
    return { success: true, sentCount: result.sent_count }
  } catch (e) {
    return { success: false, error: (e as Error).message }
  }
}

export async function getPushCampaigns() {
  await requireAdmin()
  const db = getServiceRoleClient()
  const { data } = await db
    .from('push_campaigns')
    .select('id, title, body, radius_meters, sent_user_count, created_at, deals(id, title), merchants(id, name)')
    .order('created_at', { ascending: false })
    .limit(50)
  return data ?? []
}
