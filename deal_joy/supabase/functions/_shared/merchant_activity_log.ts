// 写入 merchant_activity_events（失败仅打日志，不阻断主流程）
import { type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

export type MerchantActivityEventType =
  | "application_submitted"
  | "admin_approved"
  | "admin_rejected"
  | "admin_revoked_to_pending"
  | "store_online_merchant"
  | "store_offline_merchant"
  | "store_online_admin"
  | "store_offline_admin"
  | "store_closed_merchant";

export type MerchantActivityActorType = "admin" | "merchant_owner" | "system";

export async function logMerchantActivity(
  adminClient: SupabaseClient,
  row: {
    merchant_id: string;
    event_type: MerchantActivityEventType;
    actor_type: MerchantActivityActorType;
    actor_user_id?: string | null;
    detail?: string | null;
    /** 业务发生时刻；不传则用 DB default now() */
    created_at?: string | null;
  },
): Promise<void> {
  const payload: Record<string, unknown> = {
    merchant_id: row.merchant_id,
    event_type: row.event_type,
    actor_type: row.actor_type,
    actor_user_id: row.actor_user_id ?? null,
    detail: row.detail ?? null,
  };
  if (row.created_at) {
    payload.created_at = row.created_at;
  }
  const { error } = await adminClient.from("merchant_activity_events").insert(payload);
  if (error) {
    console.error("[merchant_activity_events] insert failed:", error.message, row);
  }
}
