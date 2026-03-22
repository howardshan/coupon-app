// =============================================================
// notify-expiring-deals: Deal 即将过期提醒 Cron Job
// 触发：每日 UTC 14:00（美国中部时间 09:00）
// 查找 7 天内过期的活跃 deals，按商家分组发 M6 邮件
// =============================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2?target=deno";
import { sendEmail } from "../_shared/email.ts";
import { buildM6Email } from "../_shared/email-templates/merchant/deal-expiring-reminder.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const CRON_SECRET = Deno.env.get("CRON_SECRET");
const EXPIRY_WINDOW_DAYS = 7;
const BATCH_SIZE = 100;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

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
  const todayStr = now.toISOString().slice(0, 10);

  // 查询即将过期的活跃 deals（关联商家 + 商家用户邮箱）
  const { data: deals, error } = await supabase
    .from("deals")
    .select("id, title, expires_at, total_sold, stock_limit, merchant_id, merchants(name, user_id, users(email))")
    .eq("is_active", true)
    .gt("expires_at", now.toISOString())
    .lte("expires_at", windowEnd.toISOString())
    .limit(BATCH_SIZE);

  if (error) {
    console.error("[notify-expiring-deals] query error", error.message);
    return new Response(JSON.stringify({ error: "db_error", message: error.message }), {
      status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  if (!deals || deals.length === 0) {
    return new Response(JSON.stringify({ processed: 0 }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  // 按 merchant_id 分组
  const byMerchant = new Map<string, { name: string; email: string; deals: typeof deals }>();
  for (const deal of deals) {
    const merchant = deal.merchants as any;
    const email = merchant?.users?.email as string | undefined;
    if (!email) continue;
    if (!byMerchant.has(deal.merchant_id)) {
      byMerchant.set(deal.merchant_id, { name: merchant?.name ?? "", email, deals: [] });
    }
    byMerchant.get(deal.merchant_id)!.deals.push(deal);
  }

  let sentCount = 0;
  for (const [merchantId, { name, email, deals: merchantDeals }] of byMerchant) {
    try {
      const dealData = merchantDeals.map((d) => {
        const daysLeft = Math.ceil(
          (new Date(d.expires_at).getTime() - now.getTime()) / (1000 * 60 * 60 * 24)
        );
        return {
          dealTitle: d.title,
          expiresAt: d.expires_at,
          daysLeft: Math.max(daysLeft, 1),
          totalSold: d.total_sold ?? 0,
          stockLimit: d.stock_limit ?? 0,
        };
      });

      const { subject, html } = buildM6Email({ merchantName: name, deals: dealData });
      await sendEmail(supabase, {
        to: email,
        subject,
        htmlBody: html,
        emailCode: "M6",
        referenceId: `${merchantId}_${todayStr}`,
        recipientType: "merchant",
        merchantId,
      });
      sentCount++;
    } catch (err) {
      console.warn(`[notify-expiring-deals] failed for merchant ${merchantId}`, err);
    }
  }

  console.log(`[notify-expiring-deals] sent ${sentCount} emails, processed ${deals.length} deals`);
  return new Response(JSON.stringify({ processed: deals.length, sent: sentCount }), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
});
