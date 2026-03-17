// auto-refund-expired: 过期订单自动退款 Edge Function
// 由 Supabase Cron Job 定期触发（建议每小时一次）
// 需求 7.1.2：团购券过期后自动退款
//
// 支持三种有效期模式：
//   - short_after_purchase（预授权）：提前 1 小时触发，取消 PI 而非退款
//   - long_after_purchase / fixed_date：过期 24 小时后正常退款
//
// 使用 Stripe SDK（在 Supabase Edge 中已稳定）

import { createClient } from 'npm:@supabase/supabase-js@2';
import Stripe from 'https://esm.sh/stripe@14?target=deno';

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
  apiVersion: '2024-04-10',
  httpClient: Stripe.createFetchHttpClient(),
});

// CORS 响应头
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// 单次最多处理订单数，防止单次执行超时
const BATCH_SIZE = 50;

// Cron 调用方共享密钥（在 Supabase Dashboard > Secrets 中配置 CRON_SECRET）
const CRON_SECRET = Deno.env.get('CRON_SECRET');

Deno.serve(async (req) => {
  // 处理 CORS 预检请求
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  // -------------------------------------------------------------
  // 调用方身份验证：若配置了 CRON_SECRET 则校验请求头
  // -------------------------------------------------------------
  if (CRON_SECRET) {
    const incomingSecret = req.headers.get('x-cron-secret');
    if (incomingSecret !== CRON_SECRET) {
      return new Response(
        JSON.stringify({ error: 'Unauthorized' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }
  }

  // Service role 客户端：绕过 RLS，读写所有行
  const supabaseAdmin = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  );

  // 汇总结果，返回给调用方
  const summary = {
    processed: 0,
    succeeded: 0,
    failed: 0,
    errors: [] as Array<{ orderId: string; error: string }>,
  };

  try {
    // -------------------------------------------------------------
    // 查询一：预授权（short_after_purchase）订单
    // 条件：capture_method='manual' + status='unused' + deals.expires_at < now + 1 hour
    // 目的：提前 1 小时触发，在 Stripe 7 天预授权过期前主动 cancel
    // -------------------------------------------------------------
    const preAuthThreshold = new Date(Date.now() + 60 * 60 * 1000).toISOString();
    const { data: preAuthOrders } = await supabaseAdmin
      .from('orders')
      .select(`
        id,
        payment_intent_id,
        total_amount,
        status,
        capture_method,
        deals!inner ( expires_at )
      `)
      .eq('capture_method', 'manual')
      .in('status', ['unused', 'refund_requested'])
      .lt('deals.expires_at', preAuthThreshold)
      .limit(BATCH_SIZE);

    // -------------------------------------------------------------
    // 查询二：立即扣款（automatic）订单
    // 条件：capture_method='automatic' + status in (unused, refund_requested)
    //       + deals.expires_at < now - 24 hours
    // -------------------------------------------------------------
    const autoThreshold = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
    const { data: autoOrders } = await supabaseAdmin
      .from('orders')
      .select(`
        id,
        payment_intent_id,
        total_amount,
        status,
        capture_method,
        deals!inner ( expires_at )
      `)
      .eq('capture_method', 'automatic')
      .in('status', ['unused', 'refund_requested'])
      .lt('deals.expires_at', autoThreshold)
      .limit(BATCH_SIZE);

    // 合并并去重
    const seen = new Set<string>();
    const eligibleOrders = [
      ...(preAuthOrders ?? []),
      ...(autoOrders ?? []),
    ].filter((o) => {
      if (seen.has(o.id)) return false;
      seen.add(o.id);
      return true;
    });

    if (!eligibleOrders || eligibleOrders.length === 0) {
      return new Response(
        JSON.stringify({ ...summary, message: 'No eligible orders found' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    console.log(`auto-refund-expired: 找到 ${eligibleOrders.length} 笔待处理订单`);
    summary.processed = eligibleOrders.length;

    // -------------------------------------------------------------
    // 逐笔处理，单笔失败不中断批次
    // -------------------------------------------------------------
    for (const order of eligibleOrders) {
      const orderId = order.id;
      const isPreAuth = order.capture_method === 'manual';
      const refundSource = order.status === 'refund_requested' ? 'store_closed' : 'auto_expired';

      try {
        const now = new Date().toISOString();

        if (isPreAuth) {
          // 预授权模式：查询 PI 状态后决定是 cancel 还是仅更新 DB
          const pi = await stripe.paymentIntents.retrieve(order.payment_intent_id);

          if (pi.status === 'requires_capture') {
            // PI 仍在预授权期（7天内）→ 主动 cancel
            await stripe.paymentIntents.cancel(order.payment_intent_id);
            console.log(`auto-refund-expired: 取消预授权 PI=${order.payment_intent_id} order=${orderId}`);
          } else if (pi.status === 'canceled') {
            // PI 已被 Stripe 自动取消（超 7 天）→ 只更新 DB 状态
            console.log(`auto-refund-expired: PI 已自动取消 order=${orderId}，仅更新 DB`);
          } else {
            // 其他状态（已 captured 等）→ 跳过，不重复处理
            console.warn(`auto-refund-expired: PI=${order.payment_intent_id} 状态=${pi.status}，跳过 order=${orderId}`);
            summary.succeeded += 1;
            continue;
          }
        } else {
          // 立即扣款模式：向 Stripe 发起退款
          await stripe.refunds.create({
            payment_intent: order.payment_intent_id,
            reason: 'requested_by_customer',
            metadata: {
              source: `auto-refund-${refundSource}`,
              order_id: orderId,
            },
          });
          console.log(`auto-refund-expired: 退款成功 order=${orderId}`);
        }

        // 更新 orders 表
        await supabaseAdmin
          .from('orders')
          .update({
            status: 'refunded',
            refund_reason: refundSource,
            refund_requested_at: order.status === 'refund_requested' ? undefined : now,
            refunded_at: now,
            updated_at: now,
          })
          .eq('id', orderId);

        // 更新 coupons 表
        const { error: couponUpdateErr } = await supabaseAdmin
          .from('coupons')
          .update({ status: 'refunded' })
          .eq('order_id', orderId);

        if (couponUpdateErr) {
          console.warn(`auto-refund-expired: 订单 ${orderId} 的 coupons 状态更新失败`, couponUpdateErr);
        }

        // 更新 payments 表
        const { error: paymentUpdateErr } = await supabaseAdmin
          .from('payments')
          .update({
            status: 'refunded',
            refund_amount: order.total_amount,
          })
          .eq('order_id', orderId);

        if (paymentUpdateErr) {
          console.warn(`auto-refund-expired: 订单 ${orderId} 的 payments 状态更新失败`, paymentUpdateErr);
        }

        summary.succeeded += 1;
      } catch (err) {
        const errMsg = err instanceof Error ? err.message : String(err);
        console.error(`auto-refund-expired: 订单 ${orderId} 处理失败 —`, errMsg);
        summary.failed += 1;
        summary.errors.push({ orderId, error: errMsg });
      }
    }

    return new Response(
      JSON.stringify(summary),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  } catch (err) {
    console.error('auto-refund-expired: 未预期的错误', err);
    return new Response(
      JSON.stringify({
        error: err instanceof Error ? err.message : 'Unknown error',
        ...summary,
      }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  }
});
