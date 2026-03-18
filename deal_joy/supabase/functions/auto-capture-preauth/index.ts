// =============================================================
// Edge Function: auto-capture-preauth
// 定时任务：对购买超过 6 天仍未核销的预授权订单执行自动 capture
//
// 触发方式：由 Supabase Cron Job 每天定时调用
//   配置路径：Supabase Dashboard → Edge Functions → auto-capture-preauth → Schedule
//   推荐频率：每天 02:00 UTC（'0 2 * * *'）
//
// 鉴权：x-cron-secret 请求头（与 auto-refund-expired 保持一致）
//   - 配置 CRON_SECRET 环境变量（Supabase Dashboard → Edge Functions → Secrets）
//   - Cron 调用时在请求头携带 x-cron-secret: <CRON_SECRET>
//
// 处理逻辑：
//   1. 查询 is_captured=false + created_at <= 6 天前 的订单
//   2. 对每笔订单调用 Stripe capture
//   3. 更新 orders.is_captured = true，status = 'unused'（已扣款待核销）
//   4. 单笔失败不阻断其他订单，全部处理后返回汇总
// =============================================================

import Stripe from 'https://esm.sh/stripe@14?target=deno';
import { createClient } from 'npm:@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-cron-secret',
};

const STRIPE_SECRET_KEY = Deno.env.get('STRIPE_SECRET_KEY') ?? '';
const CRON_SECRET = Deno.env.get('CRON_SECRET') ?? '';

// 预授权自动 capture 阈值（天）：购买后超过此天数仍未核销则自动扣款
const PREAUTH_CAPTURE_AFTER_DAYS = 6;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  // 鉴权：若配置了 CRON_SECRET 则校验请求头（与 auto-refund-expired 保持一致）
  if (CRON_SECRET) {
    const incomingSecret = req.headers.get('x-cron-secret');
    if (incomingSecret !== CRON_SECRET) {
      return new Response(
        JSON.stringify({ error: 'Unauthorized' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }
  }

  const supabaseAdmin = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  );

  const stripe = new Stripe(STRIPE_SECRET_KEY, {
    apiVersion: '2024-04-10',
    httpClient: Stripe.createFetchHttpClient(),
  });

  // 计算截止时间（6 天前）
  const cutoffDate = new Date();
  cutoffDate.setDate(cutoffDate.getDate() - PREAUTH_CAPTURE_AFTER_DAYS);
  const cutoffIso = cutoffDate.toISOString();

  console.log(`[auto-capture-preauth] 开始检查，截止时间：${cutoffIso}`);

  // 查询需要自动 capture 的预授权订单
  // 条件：未 capture + 状态为预授权中或未使用 + 超过 6 天
  const { data: orders, error: queryError } = await supabaseAdmin
    .from('orders')
    .select('id, payment_intent_id, status, created_at')
    .eq('is_captured', false)
    .in('status', ['authorized', 'unused'])
    .lte('created_at', cutoffIso);

  if (queryError) {
    console.error('[auto-capture-preauth] 查询订单失败:', queryError.message);
    return new Response(
      JSON.stringify({ error: 'query_failed', message: queryError.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  }

  const total = orders?.length ?? 0;
  console.log(`[auto-capture-preauth] 找到 ${total} 笔需要自动 capture 的订单`);

  const summary = { processed: 0, succeeded: 0, failed: 0, skipped: 0 };
  const failures: Array<{ orderId: string; reason: string }> = [];

  for (const order of orders ?? []) {
    summary.processed++;
    try {
      const pi = await stripe.paymentIntents.retrieve(order.payment_intent_id);

      // PI 已取消（用户退款时 cancel 了），同步订单状态
      if (pi.status === 'canceled') {
        await supabaseAdmin
          .from('orders')
          .update({ status: 'refunded', updated_at: new Date().toISOString() })
          .eq('id', order.id);
        console.log(`[auto-capture-preauth] 订单 ${order.id} PI 已取消，同步状态为 refunded`);
        summary.skipped++;
        continue;
      }

      // 仅处理 requires_capture 状态（预授权已就绪）
      if (pi.status !== 'requires_capture') {
        console.log(`[auto-capture-preauth] 订单 ${order.id} PI 状态为 ${pi.status}，跳过`);
        summary.skipped++;
        continue;
      }

      // 执行 Stripe capture
      await stripe.paymentIntents.capture(order.payment_intent_id);

      // 更新订单：is_captured = true，status = 'unused'（已扣款但待核销）
      const { error: updateError } = await supabaseAdmin
        .from('orders')
        .update({
          is_captured: true,
          status: 'unused',
          updated_at: new Date().toISOString(),
        })
        .eq('id', order.id);

      if (updateError) {
        throw new Error(`DB 更新失败: ${updateError.message}`);
      }

      console.log(`[auto-capture-preauth] 订单 ${order.id} 自动 capture 成功`);
      summary.succeeded++;
    } catch (err) {
      const reason = err instanceof Error ? err.message : String(err);
      console.error(`[auto-capture-preauth] 订单 ${order.id} 处理失败:`, reason);
      failures.push({ orderId: order.id, reason });
      summary.failed++;
    }
  }

  console.log(
    `[auto-capture-preauth] 完成：共 ${summary.processed} 笔，` +
    `成功 ${summary.succeeded}，跳过 ${summary.skipped}，失败 ${summary.failed}`,
  );

  return new Response(
    JSON.stringify({
      ...summary,
      ...(failures.length > 0 ? { failures } : {}),
    }),
    { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
  );
});
