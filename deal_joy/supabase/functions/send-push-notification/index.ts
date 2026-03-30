// =============================================================
// send-push-notification Edge Function
// 内部调用：写入 notifications 表 + 发送 FCM 推送
// 请求方式：POST，使用 service_role_key 鉴权
// =============================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { sendToUser } from "../_shared/fcm.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req: Request) => {
  // CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    const body = await req.json();
    const {
      user_id,
      type,
      title,
      body: notifBody,
      data,
      // 如果 skip_db 为 true，不写入 notifications 表（由触发器已写入）
      skip_db,
    } = body;

    if (!user_id || !type || !title || !notifBody) {
      return new Response(
        JSON.stringify({
          error: "Missing required fields: user_id, type, title, body",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // 验证通知类型
    const validTypes = [
      "transaction",
      "announcement",
      "friend_activity",
      "friend_request",
      "review_reply",
      "chat_message",
    ];
    if (!validTypes.includes(type)) {
      return new Response(
        JSON.stringify({ error: `Invalid type. Must be one of: ${validTypes.join(", ")}` }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // 使用 service_role 创建 Supabase 客户端（绕过 RLS）
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // 1. 写入 notifications 表（除非 skip_db）
    if (!skip_db) {
      const { error: insertError } = await supabase
        .from("notifications")
        .insert({
          user_id,
          type,
          title,
          body: notifBody,
          data: data ?? {},
        });

      if (insertError) {
        console.error("[send-push] insert notification error:", insertError);
        // 不阻断推送，继续发送
      }
    }

    // 2. 发送 FCM 推送
    // 将 data 中的所有值转为字符串（FCM data 只接受 string values）
    const fcmData: Record<string, string> = { type };
    if (data && typeof data === "object") {
      for (const [k, v] of Object.entries(data)) {
        fcmData[k] = String(v);
      }
    }

    try {
      await sendToUser(supabase, user_id, title, notifBody, fcmData);
    } catch (fcmErr) {
      // FCM 发送失败不影响接口返回（通知已入库，用户打开 App 可看到）
      console.error("[send-push] FCM error:", fcmErr);
    }

    return new Response(
      JSON.stringify({ success: true }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } catch (err) {
    console.error("[send-push] error:", err);
    return new Response(
      JSON.stringify({ error: (err as Error).message }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});
