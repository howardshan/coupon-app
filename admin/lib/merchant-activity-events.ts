/**
 * 商户活动时间线 — DB 写入（Server Action / service_role）
 * 与 deal_joy/supabase/migrations 中 merchant_activity_events 约束保持一致。
 */

import { getServiceRoleClient } from '@/lib/supabase/service'

export type MerchantActivityEventTypeDb =
  | 'application_submitted'
  | 'admin_approved'
  | 'admin_rejected'
  | 'admin_revoked_to_pending'
  | 'store_online_merchant'
  | 'store_offline_merchant'
  | 'store_online_admin'
  | 'store_offline_admin'
  | 'store_closed_merchant'
  | 'stripe_unlink_approved'
  | 'stripe_unlink_rejected'
  | 'admin_staff_invited'
  | 'admin_staff_role_changed'
  | 'admin_staff_removed'
  | 'admin_staff_status_changed'

export type MerchantActivityActorTypeDb = 'admin' | 'merchant_owner' | 'system'

/** 写入一条事件；失败仅 console，不抛错以免阻断主业务 */
export async function logMerchantActivityServer(params: {
  merchantId: string
  eventType: MerchantActivityEventTypeDb
  actorType: MerchantActivityActorTypeDb
  actorUserId: string | null
  detail?: string | null
  createdAt?: string | null
}): Promise<void> {
  const supabase = getServiceRoleClient()
  const row: Record<string, unknown> = {
    merchant_id: params.merchantId,
    event_type: params.eventType,
    actor_type: params.actorType,
    actor_user_id: params.actorUserId,
    detail: params.detail ?? null,
  }
  if (params.createdAt) row.created_at = params.createdAt
  const { error } = await supabase.from('merchant_activity_events').insert(row)
  if (error) {
    console.error('[logMerchantActivityServer]', error.message, params)
  }
}
