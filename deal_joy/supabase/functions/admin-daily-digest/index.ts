// =============================================================
// admin-daily-digest: 管理员日报 Cron Job
// 触发：每日 UTC 08:00
// 汇总昨天的平台数据，发 A3 邮件给管理员收件人
// =============================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2?target=deno";
import { sendEmail, getAdminRecipients } from "../_shared/email.ts";
import { buildA3Email } from "../_shared/email-templates/admin/daily-digest.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const CRON_SECRET = Deno.env.get("CRON_SECRET");

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

  // 昨天的时间范围（UTC）
  const now = new Date();
  const yesterdayStart = new Date(now);
  yesterdayStart.setUTCDate(yesterdayStart.getUTCDate() - 1);
  yesterdayStart.setUTCHours(0, 0, 0, 0);
  const yesterdayEnd = new Date(yesterdayStart);
  yesterdayEnd.setUTCHours(23, 59, 59, 999);

  const startIso = yesterdayStart.toISOString();
  const endIso = yesterdayEnd.toISOString();
  const dateStr = yesterdayStart.toISOString().slice(0, 10); // YYYY-MM-DD

  try {
    // 并行查询昨天的统计数据
    const [ordersRes, usersRes, merchantsRes, afterSalesOpenRes, afterSalesClosedRes, refundsRes] =
      await Promise.all([
        // 新订单 + 总收入
        supabase
          .from("orders")
          .select("total_amount")
          .gte("created_at", startIso)
          .lte("created_at", endIso),

        // 新用户
        supabase
          .from("users")
          .select("id", { count: "exact", head: true })
          .gte("created_at", startIso)
          .lte("created_at", endIso),

        // 新商家（申请中或已通过）
        supabase
          .from("merchants")
          .select("id", { count: "exact", head: true })
          .gte("created_at", startIso)
          .lte("created_at", endIso),

        // 当前待处理售后案件
        supabase
          .from("after_sales_requests")
          .select("id", { count: "exact", head: true })
          .in("status", ["pending", "awaiting_platform"]),

        // 昨天已关闭的售后案件
        supabase
          .from("after_sales_requests")
          .select("id", { count: "exact", head: true })
          .in("status", ["refunded", "platform_rejected"])
          .gte("updated_at", startIso)
          .lte("updated_at", endIso),

        // 昨天的退款
        supabase
          .from("payments")
          .select("refund_amount")
          .not("refund_amount", "is", null)
          .gte("updated_at", startIso)
          .lte("updated_at", endIso),
      ]);

    const orders = ordersRes.data ?? [];
    const newOrders = orders.length;
    const totalRevenue = orders.reduce((sum, o) => sum + Number(o.total_amount ?? 0), 0);

    const refunds = refundsRes.data ?? [];
    const refundCount = refunds.length;
    const refundAmount = refunds.reduce((sum, p) => sum + Number(p.refund_amount ?? 0), 0);

    // 查管理员收件人
    const adminEmails = await getAdminRecipients(supabase, "A3");
    if (adminEmails.length === 0) {
      return new Response(JSON.stringify({ skipped: "no admin recipients configured" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { subject, html } = buildA3Email({
      date: dateStr,
      newOrders,
      totalRevenue,
      refundCount,
      refundAmount,
      newUsers: usersRes.count ?? 0,
      newMerchants: merchantsRes.count ?? 0,
      openAfterSales: afterSalesOpenRes.count ?? 0,
      closedAfterSalesYesterday: afterSalesClosedRes.count ?? 0,
    });

    await sendEmail(supabase, {
      to: adminEmails,
      subject,
      htmlBody: html,
      emailCode: "A3",
      referenceId: `admin_digest_${dateStr}`,
      recipientType: "admin",
    });

    console.log(`[admin-daily-digest] sent digest for ${dateStr} to ${adminEmails.length} recipient(s)`);
    return new Response(JSON.stringify({ sent: true, date: dateStr }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("[admin-daily-digest] error", err);
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
