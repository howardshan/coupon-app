// 与 merchant-store POST /close 等价逻辑，供 account-delete 等服务端编排复用
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { logMerchantActivity } from "./merchant_activity_log.ts";

export interface CloseMerchantStoreResult {
  pending_refund_count: number;
}

/**
 * 闭店：status=closed、下架 deal、未核销订单标记 refund_requested（与 cron 衔接）
 */
export async function closeMerchantStore(
  supabaseAdmin: SupabaseClient,
  merchantId: string,
  actorUserId: string,
): Promise<CloseMerchantStoreResult> {
  const { error: closeErr } = await supabaseAdmin
    .from("merchants")
    .update({
      status: "closed",
      is_online: false,
    })
    .eq("id", merchantId);

  if (closeErr) {
    throw new Error(`Failed to close store: ${closeErr.message}`);
  }

  await logMerchantActivity(supabaseAdmin, {
    merchant_id: merchantId,
    event_type: "store_closed_merchant",
    actor_type: "merchant_owner",
    actor_user_id: actorUserId,
  });

  await supabaseAdmin
    .from("deals")
    .update({
      is_active: false,
      deal_status: "inactive",
    })
    .eq("merchant_id", merchantId)
    .eq("is_active", true);

  const { data: dealRows } = await supabaseAdmin
    .from("deals")
    .select("id")
    .eq("merchant_id", merchantId);

  const dealIds = (dealRows ?? []).map((d: { id: string }) => d.id);

  let pendingCount = 0;
  if (dealIds.length > 0) {
    const { data: unusedOrders } = await supabaseAdmin
      .from("orders")
      .select("id")
      .in("deal_id", dealIds)
      .eq("status", "unused");

    pendingCount = unusedOrders?.length ?? 0;

    if (pendingCount > 0) {
      const now = new Date().toISOString();
      const orderIds = unusedOrders!.map((o: { id: string }) => o.id);
      await supabaseAdmin
        .from("orders")
        .update({
          status: "refund_requested",
          refund_reason: "store_closed",
          refund_requested_at: now,
          updated_at: now,
        })
        .in("id", orderIds);

      await supabaseAdmin
        .from("coupons")
        .update({ status: "refund_requested" })
        .in("order_id", orderIds);
    }
  }

  const { data: multiDeals } = await supabaseAdmin
    .from("deals")
    .select("id, applicable_merchant_ids")
    .contains("applicable_merchant_ids", [merchantId]);

  if (multiDeals && multiDeals.length > 0) {
    for (const deal of multiDeals) {
      const updated = (deal.applicable_merchant_ids as string[]).filter(
        (id: string) => id !== merchantId,
      );
      await supabaseAdmin
        .from("deals")
        .update({ applicable_merchant_ids: updated })
        .eq("id", deal.id);
    }
  }

  return { pending_refund_count: pendingCount };
}
