// send-geo-push Edge Function
// Admin 调用：按地理范围批量推送，记录 campaign
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { sendToUser } from "../_shared/fcm.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });

  try {
    const {
      title,
      body,
      deal_id,
      merchant_id,
      target_lat,
      target_lng,
      radius_meters = 40234,
      created_by,
    } = await req.json();

    // 校验必填参数
    if (!title || !body || !target_lat || !target_lng) {
      return new Response(
        JSON.stringify({ error: "Missing required fields: title, body, target_lat, target_lng" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // 1. 找范围内有 FCM token 的用户（调用 RPC）
    const { data: users, error: rpcError } = await supabase.rpc("find_users_for_geo_push", {
      p_lat: target_lat,
      p_lng: target_lng,
      p_radius_m: radius_meters,
    });

    if (rpcError) throw new Error(rpcError.message);

    const userIds: string[] = (users ?? []).map((r: { user_id: string }) => r.user_id);

    // 2. 批量推送（每批 50 个并发）
    const fcmData: Record<string, string> = { type: "promo" };
    if (deal_id) fcmData.deal_id = deal_id;
    if (merchant_id) fcmData.merchant_id = merchant_id;

    const BATCH = 50;
    for (let i = 0; i < userIds.length; i += BATCH) {
      await Promise.all(
        userIds.slice(i, i + BATCH).map((uid) =>
          sendToUser(supabase, uid, title, body, fcmData).catch(() => null)
        )
      );
    }

    // 3. 记录推送 campaign（写入失败不阻断成功响应，推送已完成）
    const { error: campaignError } = await supabase.from("push_campaigns").insert({
      title,
      body,
      deal_id: deal_id ?? null,
      merchant_id: merchant_id ?? null,
      radius_meters,
      target_lat,
      target_lng,
      sent_user_count: userIds.length,
      created_by: created_by ?? null,
    });
    if (campaignError) {
      console.error("[send-geo-push] campaign insert error:", campaignError.message);
    }

    return new Response(
      JSON.stringify({ success: true, sent_count: userIds.length }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err) {
    console.error("[send-geo-push] error:", err);
    return new Response(
      JSON.stringify({ error: (err as Error).message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
