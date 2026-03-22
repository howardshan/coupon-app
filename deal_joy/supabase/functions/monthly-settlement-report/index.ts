// =============================================================
// monthly-settlement-report: 月度结算报告 Cron Job
// 触发：每月 1 日 UTC 02:00
// 为所有活跃商家生成上月结算报告，发 M13 邮件
// =============================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2?target=deno";
import { sendEmail } from "../_shared/email.ts";
import { buildM13Email } from "../_shared/email-templates/merchant/monthly-settlement.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const CRON_SECRET = Deno.env.get("CRON_SECRET");
const BATCH_SIZE = 50;

// 格式化月份名（如 "2026-02" → "February 2026"）
function formatMonthName(yearMonth: string): string {
  const [year, month] = yearMonth.split("-");
  const date = new Date(Number(year), Number(month) - 1, 1);
  return date.toLocaleDateString("en-US", { month: "long", year: "numeric" });
}

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

  // 上个月的 YYYY-MM-DD 起始日期
  const now = new Date();
  const prevMonthDate = new Date(now.getFullYear(), now.getMonth() - 1, 1);
  const prevMonthStart = `${prevMonthDate.getFullYear()}-${String(prevMonthDate.getMonth() + 1).padStart(2, "0")}-01`;
  const prevMonthStr = prevMonthStart.slice(0, 7); // YYYY-MM
  const monthLabel = formatMonthName(prevMonthStr);

  // 查询所有已通过的活跃商家（含邮箱）
  const { data: merchants, error: merchantsError } = await supabase
    .from("merchants")
    .select("id, name, user_id, users(email)")
    .eq("status", "approved")
    .limit(BATCH_SIZE);

  if (merchantsError) {
    console.error("[monthly-settlement-report] merchants query error", merchantsError.message);
    return new Response(JSON.stringify({ error: merchantsError.message }), {
      status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  if (!merchants || merchants.length === 0) {
    return new Response(JSON.stringify({ processed: 0 }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  let sentCount = 0;
  for (const merchant of merchants) {
    const email = (merchant.users as any)?.email as string | undefined;
    if (!email) continue;

    try {
      // 调用 RPC 查询上月收益汇总
      const { data: summary, error: rpcError } = await supabase.rpc("get_merchant_earnings_summary", {
        p_merchant_id: merchant.id,
        p_month_start: prevMonthStart,
      });

      if (rpcError || !summary || summary.length === 0) {
        console.warn(`[monthly-settlement-report] no earnings data for merchant ${merchant.id}`, rpcError?.message);
        continue;
      }

      const row = summary[0];
      const totalRevenue = Number(row.total_revenue ?? 0);
      const pendingSettlement = Number(row.pending_settlement ?? 0);
      const settledAmount = Number(row.settled_amount ?? 0);
      const refundedAmount = Number(row.refunded_amount ?? 0);

      // 如果当月没有任何收入，跳过
      if (totalRevenue === 0 && refundedAmount === 0) continue;

      // 粗略估算 fee（从 totalRevenue 和 settled 倒推）
      const netAmount = settledAmount + pendingSettlement;
      const platformFee = Math.max(totalRevenue - netAmount - refundedAmount, 0);
      const stripeFee = 0; // RPC 不单独返回 stripe fee，此处留 0

      const { subject, html } = buildM13Email({
        merchantName: merchant.name,
        month: monthLabel,
        totalRevenue,
        platformFee,
        stripeFee,
        netAmount,
        refundedAmount,
        pendingSettlement,
      });

      await sendEmail(supabase, {
        to: email,
        subject,
        htmlBody: html,
        emailCode: "M13",
        referenceId: `${merchant.id}_${prevMonthStr}`,
        recipientType: "merchant",
        merchantId: merchant.id,
      });
      sentCount++;
    } catch (err) {
      console.warn(`[monthly-settlement-report] failed for merchant ${merchant.id}`, err);
    }
  }

  console.log(`[monthly-settlement-report] sent ${sentCount} reports for ${monthLabel}`);
  return new Response(JSON.stringify({ processed: merchants.length, sent: sentCount, month: monthLabel }), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
});
