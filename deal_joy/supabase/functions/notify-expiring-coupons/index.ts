// =============================================================
// notify-expiring-coupons: 券即将过期提醒 Cron Job
// 触发：每日 UTC 14:00（美国中部时间 09:00）
// 查找 3 天内过期的 unused 券，按用户分组发 C4 邮件
// =============================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2?target=deno";
import { sendEmail } from "../_shared/email.ts";
import { buildC4Email } from "../_shared/email-templates/customer/coupon-expiring-reminder.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const CRON_SECRET = Deno.env.get("CRON_SECRET");
const EXPIRY_WINDOW_DAYS = 3;
const BATCH_SIZE = 100;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // 验证 Cron Secret
  if (CRON_SECRET) {
    const incoming = req.headers.get("x-cron-secret");
    if (incoming !== CRON_SECRET) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
  );

  const now = new Date();
  const windowEnd = new Date(now.getTime() + EXPIRY_WINDOW_DAYS * 24 * 60 * 60 * 1000);
  const todayStr = now.toISOString().slice(0, 10); // YYYY-MM-DD，用于幂等 referenceId

  // 查询即将过期的未使用券（关联 deals + merchants + users）
  const { data: coupons, error } = await supabase
    .from("coupons")
    .select("id, user_id, expires_at, deal_id, deals(title, merchant_id, merchants(name)), users(email)")
    .eq("status", "unused")
    .gt("expires_at", now.toISOString())
    .lte("expires_at", windowEnd.toISOString())
    .limit(BATCH_SIZE);

  if (error) {
    console.error("[notify-expiring-coupons] query error", error.message);
    return new Response(JSON.stringify({ error: "db_error", message: error.message }), {
      status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  if (!coupons || coupons.length === 0) {
    return new Response(JSON.stringify({ processed: 0 }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  // 按 user_id 分组
  const byUser = new Map<string, { email: string; coupons: typeof coupons }>();
  for (const coupon of coupons) {
    const email = (coupon.users as any)?.email as string | undefined;
    if (!email) continue;
    if (!byUser.has(coupon.user_id)) {
      byUser.set(coupon.user_id, { email, coupons: [] });
    }
    byUser.get(coupon.user_id)!.coupons.push(coupon);
  }

  let sentCount = 0;
  for (const [userId, { email, coupons: userCoupons }] of byUser) {
    try {
      const couponData = userCoupons.map((c) => {
        const expiresAt = c.expires_at;
        const daysLeft = Math.ceil(
          (new Date(expiresAt).getTime() - now.getTime()) / (1000 * 60 * 60 * 24)
        );
        const deal = c.deals as any;
        return {
          dealTitle: deal?.title ?? "Deal",
          merchantName: deal?.merchants?.name ?? "",
          expiresAt,
          daysLeft: Math.max(daysLeft, 1),
        };
      });

      const { subject, html } = buildC4Email({ coupons: couponData });
      await sendEmail(supabase, {
        to: email,
        subject,
        htmlBody: html,
        emailCode: "C4",
        referenceId: `${userId}_${todayStr}`,
        recipientType: "customer",
        userId,
      });
      sentCount++;
    } catch (err) {
      console.warn(`[notify-expiring-coupons] failed for user ${userId}`, err);
    }
  }

  console.log(`[notify-expiring-coupons] sent ${sentCount} emails, processed ${coupons.length} coupons`);
  return new Response(JSON.stringify({ processed: coupons.length, sent: sentCount }), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
});
