// auto-refund-expired: 过期订单自动退款 Edge Function
// 由 Supabase Cron Job 定期触发（建议每小时一次）
// 需求 7.1.2：团购券过期 24 小时后自动退全额

import Stripe from 'https://esm.sh/stripe@11.2.0?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2?target=deno';

// Stripe 客户端初始化（与 create-refund 保持一致）
const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
  apiVersion: '2024-04-10',
  httpClient: Stripe.createFetchHttpClient(),
});

// CORS 响应头（与其他 Edge Functions 保持一致）
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// 单次最多处理的订单数，防止单次执行超时
const BATCH_SIZE = 50;

// 可选：Cron 调用方通过自定义请求头传入共享密钥，防止公开 URL 被滥用
// 在 Supabase Dashboard > Edge Functions > Secrets 中配置 CRON_SECRET
const CRON_SECRET = Deno.env.get('CRON_SECRET');

Deno.serve(async (req) => {
  // 处理 CORS 预检请求
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  // -------------------------------------------------------------
  // 调用方身份验证
  // 策略：若配置了 CRON_SECRET，则要求请求头 x-cron-secret 匹配；
  //       若未配置，则仅允许来自 Supabase 内部的调用
  //       （通过网络层限制，不对公网开放）。
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

  // Service role 客户端：绕过 RLS，供定时任务读写所有行
  const supabaseAdmin = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  );

  // 汇总结果，最终返回给调用方
  const summary = {
    processed: 0,
    succeeded: 0,
    failed: 0,
    errors: [] as Array<{ orderId: string; error: string }>,
  };

  try {
    // -------------------------------------------------------------
    // 查询符合自动退款条件的订单：
    //   - orders.status = 'unused'（尚未核销、尚未退款）
    //   - 关联 deals.expires_at < now() - interval '24 hours'
    //     （团购券已过期超过 24 小时，满足需求 7.1.2）
    // 通过 join deals 表在数据库层完成过滤，减少网络传输量
    // -------------------------------------------------------------
    const { data: eligibleOrders, error: queryErr } = await supabaseAdmin
      .from('orders')
      .select(`
        id,
        payment_intent_id,
        total_amount,
        status,
        deal_id,
        deals!inner (
          expires_at
        )
      `)
      .eq('status', 'unused')
      .lt('deals.expires_at', new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString())
      .limit(BATCH_SIZE);

    if (queryErr) {
      console.error('auto-refund-expired: 查询过期订单失败', queryErr);
      return new Response(
        JSON.stringify({ error: 'Failed to query eligible orders', detail: queryErr.message }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    if (!eligibleOrders || eligibleOrders.length === 0) {
      // 无需处理的订单，正常返回
      return new Response(
        JSON.stringify({ ...summary, message: 'No eligible orders found' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    console.log(`auto-refund-expired: 找到 ${eligibleOrders.length} 笔待退款订单`);
    summary.processed = eligibleOrders.length;

    // -------------------------------------------------------------
    // 逐笔处理退款
    // 单笔失败不中断批次，保证其他订单正常退款
    // -------------------------------------------------------------
    for (const order of eligibleOrders) {
      const orderId = order.id;

      try {
        // 1. 向 Stripe 发起退款
        //    reason: 'expired_uncaptured_charge' 是 Stripe 内置枚举中最接近的值；
        //    实际为"团购券过期"场景，通过 metadata 额外说明。
        const refund = await stripe.refunds.create({
          payment_intent: order.payment_intent_id,
          reason: 'requested_by_customer', // Stripe 允许的枚举：duplicate | fraudulent | requested_by_customer
          metadata: {
            source: 'auto-refund-expired',
            order_id: orderId,
          },
        });

        const now = new Date().toISOString();

        // 2. 更新 orders 表：状态置为 refunded，记录退款原因和时间戳
        const { error: orderUpdateErr } = await supabaseAdmin
          .from('orders')
          .update({
            status: 'refunded',
            refund_reason: 'auto_expired',   // 区分于用户主动退款的标识
            refund_requested_at: now,         // 自动退款无预申请环节，与 refunded_at 相同
            refunded_at: now,
            updated_at: now,
          })
          .eq('id', orderId);

        if (orderUpdateErr) {
          throw new Error(`更新 orders 失败: ${orderUpdateErr.message}`);
        }

        // 3. 更新 coupons 表：将关联券状态置为 refunded
        const { error: couponUpdateErr } = await supabaseAdmin
          .from('coupons')
          .update({
            status: 'refunded',
          })
          .eq('order_id', orderId);

        if (couponUpdateErr) {
          // 优惠券更新失败不中断流程，但记录警告
          // 订单已成功退款是核心，券状态可后续修复
          console.warn(`auto-refund-expired: 订单 ${orderId} 的优惠券状态更新失败`, couponUpdateErr);
        }

        // 4. 更新 payments 表：记录退款状态和金额
        const { error: paymentUpdateErr } = await supabaseAdmin
          .from('payments')
          .update({
            status: 'refunded',
            refund_amount: order.total_amount,
          })
          .eq('order_id', orderId);

        if (paymentUpdateErr) {
          // payments 表更新失败同样仅警告，不回滚已成功的 Stripe 退款
          console.warn(`auto-refund-expired: 订单 ${orderId} 的 payments 状态更新失败`, paymentUpdateErr);
        }

        console.log(`auto-refund-expired: 订单 ${orderId} 退款成功，refund_id=${refund.id}`);
        summary.succeeded += 1;
      } catch (refundErr) {
        // 单笔退款失败：记录错误并继续处理下一笔
        const errMsg = refundErr instanceof Error ? refundErr.message : String(refundErr);
        console.error(`auto-refund-expired: 订单 ${orderId} 退款失败 —`, errMsg);
        summary.failed += 1;
        summary.errors.push({ orderId, error: errMsg });
      }
    }

    // 返回本次批次的汇总结果，供 cron 监控日志使用
    return new Response(
      JSON.stringify(summary),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  } catch (err) {
    // 顶层兜底错误处理（如网络异常、客户端初始化失败等）
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
