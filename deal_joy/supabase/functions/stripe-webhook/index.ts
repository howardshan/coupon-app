// Stripe Webhook 处理函数
// 接收 Stripe 发送的支付事件，更新订单/优惠券/支付记录
// 使用 service role key 绕过 RLS（webhook 无用户身份）

import Stripe from 'https://esm.sh/stripe@14?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2?target=deno';

// ─── Stripe 客户端初始化 ─────────────────────────────────────────────────────
const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
  apiVersion: '2024-04-10',
  httpClient: Stripe.createFetchHttpClient(),
});

// ─── Supabase 服务端客户端（绕过 RLS）──────────────────────────────────────
const supabase = createClient(
  Deno.env.get('SUPABASE_URL') ?? '',
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
);

// ─── CORS Headers ────────────────────────────────────────────────────────────
// Stripe webhook 不需要 CORS（服务器对服务器），但保持与其他函数一致的格式
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// ─── 辅助：构建 JSON 响应 ─────────────────────────────────────────────────
function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

// ─── 事件处理：payment_intent.succeeded ─────────────────────────────────────
// 支付成功：更新订单状态，写入 payments 记录（幂等：检查 payment_intent_id 唯一约束）
async function handlePaymentSucceeded(paymentIntent: Stripe.PaymentIntent): Promise<void> {
  const paymentIntentId = paymentIntent.id;
  const chargeId = typeof paymentIntent.latest_charge === 'string'
    ? paymentIntent.latest_charge
    : paymentIntent.latest_charge?.id ?? null;

  console.log(`[payment_intent.succeeded] pi=${paymentIntentId} charge=${chargeId}`);

  // 幂等检查：payments 表的 payment_intent_id 列有 UNIQUE 约束
  // 若已存在则跳过，避免重复处理
  const { data: existing, error: checkErr } = await supabase
    .from('payments')
    .select('id')
    .eq('payment_intent_id', paymentIntentId)
    .maybeSingle();

  if (checkErr) {
    console.error('[payment_intent.succeeded] 幂等检查失败:', checkErr);
    throw new Error(`幂等检查失败: ${checkErr.message}`);
  }

  if (existing) {
    console.log(`[payment_intent.succeeded] 已处理过 pi=${paymentIntentId}，跳过`);
    return;
  }

  // 通过 payment_intent_id 找到对应订单
  const { data: order, error: orderErr } = await supabase
    .from('orders')
    .select('id, user_id, total_amount, status')
    .eq('payment_intent_id', paymentIntentId)
    .maybeSingle();

  if (orderErr) {
    console.error('[payment_intent.succeeded] 查询订单失败:', orderErr);
    throw new Error(`查询订单失败: ${orderErr.message}`);
  }

  if (!order) {
    // 订单可能由客户端在支付成功后写入，存在竞态；记录警告但不抛出
    console.warn(`[payment_intent.succeeded] 未找到对应订单 pi=${paymentIntentId}`);
    return;
  }

  // 更新订单：记录 stripe_charge_id（如果支付成功时已有 charge）
  if (chargeId) {
    const { error: updateOrderErr } = await supabase
      .from('orders')
      .update({
        stripe_charge_id: chargeId,
        updated_at: new Date().toISOString(),
      })
      .eq('id', order.id);

    if (updateOrderErr) {
      console.error('[payment_intent.succeeded] 更新订单 charge_id 失败:', updateOrderErr);
      // 非致命错误，继续写 payments 记录
    }
  }

  // 插入 payments 审计记录
  const { error: insertPaymentErr } = await supabase
    .from('payments')
    .insert({
      order_id: order.id,
      user_id: order.user_id,
      amount: order.total_amount,
      currency: paymentIntent.currency,
      payment_intent_id: paymentIntentId,
      stripe_charge_id: chargeId,
      status: 'succeeded',
    });

  if (insertPaymentErr) {
    // payment_intent_id UNIQUE 冲突代表已处理，不视为错误
    if (insertPaymentErr.code === '23505') {
      console.log(`[payment_intent.succeeded] payments 已存在（并发写入），跳过`);
      return;
    }
    console.error('[payment_intent.succeeded] 插入 payments 失败:', insertPaymentErr);
    throw new Error(`插入 payments 失败: ${insertPaymentErr.message}`);
  }

  console.log(`[payment_intent.succeeded] 完成 order=${order.id}`);
}

// ─── 事件处理：payment_intent.payment_failed ─────────────────────────────────
// 支付失败：记录日志，将订单（若存在）的状态保持为 unused（等待重试）
// 不删除订单，让客户端重试支付
async function handlePaymentFailed(paymentIntent: Stripe.PaymentIntent): Promise<void> {
  const paymentIntentId = paymentIntent.id;
  const failureMessage = paymentIntent.last_payment_error?.message ?? 'unknown';
  const failureCode = paymentIntent.last_payment_error?.code ?? 'unknown';

  console.warn(
    `[payment_intent.payment_failed] pi=${paymentIntentId} code=${failureCode} msg=${failureMessage}`,
  );

  // 查找关联订单
  const { data: order, error: orderErr } = await supabase
    .from('orders')
    .select('id, user_id, total_amount, status')
    .eq('payment_intent_id', paymentIntentId)
    .maybeSingle();

  if (orderErr) {
    console.error('[payment_intent.payment_failed] 查询订单失败:', orderErr);
    // 不抛出，尽力完成日志记录
  }

  if (!order) {
    console.warn(`[payment_intent.payment_failed] 未找到对应订单 pi=${paymentIntentId}`);
    return;
  }

  // 写入 payments 失败记录（使用 upsert 防止重复，以 payment_intent_id 为冲突键）
  const { error: upsertErr } = await supabase
    .from('payments')
    .upsert(
      {
        order_id: order.id,
        user_id: order.user_id,
        amount: order.total_amount,
        currency: paymentIntent.currency,
        payment_intent_id: paymentIntentId,
        stripe_charge_id: null,
        status: 'failed',
      },
      { onConflict: 'payment_intent_id', ignoreDuplicates: false },
    );

  if (upsertErr) {
    console.error('[payment_intent.payment_failed] 写入 payments 失败记录失败:', upsertErr);
    // 非致命，只记录
  }

  console.log(`[payment_intent.payment_failed] 已记录失败 order=${order.id}`);
}

// ─── 事件处理：charge.refunded ────────────────────────────────────────────────
// 退款完成：更新 orders 状态为 refunded，更新 coupons 状态为 refunded，
// 更新 payments 记录的退款金额和状态
async function handleChargeRefunded(charge: Stripe.Charge): Promise<void> {
  const chargeId = charge.id;
  const paymentIntentId = typeof charge.payment_intent === 'string'
    ? charge.payment_intent
    : charge.payment_intent?.id ?? null;

  // 退款金额（Stripe 单位为 cents，转为元）
  const refundAmountCents = charge.amount_refunded ?? 0;
  const refundAmount = refundAmountCents / 100;

  console.log(
    `[charge.refunded] charge=${chargeId} pi=${paymentIntentId} refund_amount=${refundAmount}`,
  );

  if (!paymentIntentId) {
    console.warn('[charge.refunded] charge 没有关联的 payment_intent，跳过');
    return;
  }

  // 通过 payment_intent_id 找到订单
  const { data: order, error: orderErr } = await supabase
    .from('orders')
    .select('id, status')
    .eq('payment_intent_id', paymentIntentId)
    .maybeSingle();

  if (orderErr) {
    console.error('[charge.refunded] 查询订单失败:', orderErr);
    throw new Error(`查询订单失败: ${orderErr.message}`);
  }

  if (!order) {
    console.warn(`[charge.refunded] 未找到对应订单 pi=${paymentIntentId}`);
    return;
  }

  // 更新订单状态为 refunded
  const { error: updateOrderErr } = await supabase
    .from('orders')
    .update({
      status: 'refunded',
      stripe_charge_id: chargeId,
      updated_at: new Date().toISOString(),
    })
    .eq('id', order.id);

  if (updateOrderErr) {
    console.error('[charge.refunded] 更新订单状态失败:', updateOrderErr);
    throw new Error(`更新订单状态失败: ${updateOrderErr.message}`);
  }

  // 更新该订单下所有优惠券状态为 refunded
  const { error: updateCouponErr } = await supabase
    .from('coupons')
    .update({ status: 'refunded' })
    .eq('order_id', order.id);

  if (updateCouponErr) {
    console.error('[charge.refunded] 更新优惠券状态失败:', updateCouponErr);
    // 非致命，继续更新 payments
  }

  // P1 fix: 更新 payments 表退款信息时只对已存在的行做 UPDATE，不做 upsert INSERT。
  // upsert 的 INSERT 路径需要填充所有 NOT NULL 列（user_id, amount, currency），
  // 但 charge.refunded 事件不携带这些字段，若行不存在则会触发 NOT NULL 违规。
  // 正常业务流程下 payment_intent.succeeded 总先于 charge.refunded 到达；
  // 若行确实不存在，只记录警告，不影响已完成的订单/优惠券状态更新。
  const { data: existingPayment, error: checkPaymentErr } = await supabase
    .from('payments')
    .select('id')
    .eq('payment_intent_id', paymentIntentId)
    .maybeSingle();

  if (checkPaymentErr) {
    console.error('[charge.refunded] 查询 payments 行失败:', checkPaymentErr);
    // 非致命，继续
  } else if (!existingPayment) {
    console.warn(
      `[charge.refunded] payments 行不存在 pi=${paymentIntentId}，跳过更新（succeeded 事件尚未到达？）`,
    );
  } else {
    const { error: updatePaymentErr } = await supabase
      .from('payments')
      .update({
        stripe_charge_id: chargeId,
        status: 'refunded',
        refund_amount: refundAmount,
      })
      .eq('payment_intent_id', paymentIntentId);

    if (updatePaymentErr) {
      console.error('[charge.refunded] 更新 payments 退款信息失败:', updatePaymentErr);
      // 记录但不抛出，订单和优惠券已更新成功
    }
  }

  console.log(`[charge.refunded] 完成 order=${order.id} refund=${refundAmount}`);
}

// ─── 事件处理：charge.dispute.created ────────────────────────────────────────
// 争议创建：仅记录日志（生产环境可扩展为发送告警通知）
async function handleDisputeCreated(dispute: Stripe.Dispute): Promise<void> {
  const disputeId = dispute.id;
  const chargeId = typeof dispute.charge === 'string'
    ? dispute.charge
    : dispute.charge?.id ?? 'unknown';
  const amount = dispute.amount / 100;
  const reason = dispute.reason;
  const status = dispute.status;

  console.warn(
    `[charge.dispute.created] dispute=${disputeId} charge=${chargeId}` +
      ` amount=${amount} reason=${reason} status=${status}`,
  );

  // 通过 stripe_charge_id 找到订单（仅查询，不修改）
  const { data: order, error: orderErr } = await supabase
    .from('orders')
    .select('id, user_id, payment_intent_id')
    .eq('stripe_charge_id', chargeId)
    .maybeSingle();

  if (orderErr) {
    console.error('[charge.dispute.created] 查询订单失败:', orderErr);
    // 不抛出，dispute 记录不影响主流程
    return;
  }

  if (order) {
    console.warn(
      `[charge.dispute.created] 关联订单 order=${order.id} user=${order.user_id}` +
        ` pi=${order.payment_intent_id}`,
    );
    // TODO: 生产环境可在此处发送邮件/Slack 告警
  } else {
    console.warn(`[charge.dispute.created] 未找到对应订单 charge=${chargeId}`);
  }
}

// ─── 事件处理：payment_intent.amount_capturable_updated ───────────────────────
// 预授权成功：将订单状态更新为 authorized，is_captured = false
async function handleAmountCapturableUpdated(pi: Stripe.PaymentIntent): Promise<void> {
  const paymentIntentId = pi.id;
  console.log(`[amount_capturable_updated] pi=${paymentIntentId}`);

  const { data: order, error: orderErr } = await supabase
    .from('orders')
    .select('id, status')
    .eq('payment_intent_id', paymentIntentId)
    .maybeSingle();

  if (orderErr) {
    console.error('[amount_capturable_updated] 查询订单失败:', orderErr);
    throw new Error(`查询订单失败: ${orderErr.message}`);
  }

  if (!order) {
    // 订单可能由客户端在授权成功后写入，存在竞态；记录警告但不抛出
    console.warn(`[amount_capturable_updated] 未找到对应订单 pi=${paymentIntentId}`);
    return;
  }

  // 更新订单状态为 authorized，标记 is_captured = false
  const { error: updateErr } = await supabase
    .from('orders')
    .update({
      status: 'authorized',
      is_captured: false,
      updated_at: new Date().toISOString(),
    })
    .eq('id', order.id);

  if (updateErr) {
    console.error('[amount_capturable_updated] 更新订单状态失败:', updateErr);
    throw new Error(`更新订单状态失败: ${updateErr.message}`);
  }

  // 同时激活关联优惠券（状态改为 active，可供使用）
  await supabase
    .from('coupons')
    .update({ status: 'active' })
    .eq('order_id', order.id);

  console.log(`[amount_capturable_updated] 完成 order=${order.id} → authorized`);
}

// ─── 事件处理：payment_intent.canceled ────────────────────────────────────────
// 预授权取消（用户在核销前退款）：更新订单为 refunded，coupon 为 refunded
async function handlePaymentIntentCanceled(pi: Stripe.PaymentIntent): Promise<void> {
  const paymentIntentId = pi.id;
  console.log(`[payment_intent.canceled] pi=${paymentIntentId}`);

  const { data: order, error: orderErr } = await supabase
    .from('orders')
    .select('id, status')
    .eq('payment_intent_id', paymentIntentId)
    .maybeSingle();

  if (orderErr) {
    console.error('[payment_intent.canceled] 查询订单失败:', orderErr);
    throw new Error(`查询订单失败: ${orderErr.message}`);
  }

  if (!order) {
    console.warn(`[payment_intent.canceled] 未找到对应订单 pi=${paymentIntentId}`);
    return;
  }

  // 已经是 refunded 状态则跳过（幂等）
  if (order.status === 'refunded') {
    console.log(`[payment_intent.canceled] order=${order.id} 已是 refunded，跳过`);
    return;
  }

  const now = new Date().toISOString();

  const { error: updateErr } = await supabase
    .from('orders')
    .update({
      status: 'refunded',
      refunded_at: now,
      updated_at: now,
    })
    .eq('id', order.id);

  if (updateErr) {
    console.error('[payment_intent.canceled] 更新订单状态失败:', updateErr);
    throw new Error(`更新订单状态失败: ${updateErr.message}`);
  }

  await supabase
    .from('coupons')
    .update({ status: 'refunded' })
    .eq('order_id', order.id);

  console.log(`[payment_intent.canceled] 完成 order=${order.id} → refunded`);
}

// ─── 主处理器 ────────────────────────────────────────────────────────────────
Deno.serve(async (req) => {
  // 处理 CORS preflight（Stripe 实际不会发 OPTIONS，但保持一致）
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  // 只接受 POST
  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405);
  }

  // 读取 Webhook Secret
  const webhookSecret = Deno.env.get('STRIPE_WEBHOOK_SECRET');
  if (!webhookSecret) {
    console.error('[stripe-webhook] STRIPE_WEBHOOK_SECRET 未配置');
    return jsonResponse({ error: 'Webhook secret not configured' }, 500);
  }

  // 获取 Stripe 签名 Header
  const sigHeader = req.headers.get('stripe-signature');
  if (!sigHeader) {
    console.warn('[stripe-webhook] 缺少 stripe-signature header');
    return jsonResponse({ error: 'Missing stripe-signature header' }, 400);
  }

  // 读取原始请求体（signature 验证必须使用 raw bytes）
  let rawBody: Uint8Array;
  try {
    rawBody = new Uint8Array(await req.arrayBuffer());
  } catch (err) {
    console.error('[stripe-webhook] 读取请求体失败:', err);
    return jsonResponse({ error: 'Failed to read request body' }, 400);
  }

  // 验证 Stripe 签名
  let event: Stripe.Event;
  try {
    event = await stripe.webhooks.constructEventAsync(
      rawBody,
      sigHeader,
      webhookSecret,
    );
  } catch (err) {
    const msg = err instanceof Error ? err.message : 'Signature verification failed';
    console.warn(`[stripe-webhook] 签名验证失败: ${msg}`);
    return jsonResponse({ error: msg }, 400);
  }

  console.log(`[stripe-webhook] 收到事件 type=${event.type} id=${event.id}`);

  // 路由到对应处理函数
  try {
    switch (event.type) {
      case 'payment_intent.succeeded':
        await handlePaymentSucceeded(event.data.object as Stripe.PaymentIntent);
        break;

      case 'payment_intent.payment_failed':
        await handlePaymentFailed(event.data.object as Stripe.PaymentIntent);
        break;

      case 'charge.refunded':
        await handleChargeRefunded(event.data.object as Stripe.Charge);
        break;

      case 'payment_intent.amount_capturable_updated':
        // 预授权成功：更新订单状态为 authorized，is_captured = false
        await handleAmountCapturableUpdated(event.data.object as Stripe.PaymentIntent);
        break;

      case 'payment_intent.canceled':
        // 预授权取消（未核销时用户退款）：更新订单为 refunded
        await handlePaymentIntentCanceled(event.data.object as Stripe.PaymentIntent);
        break;

      case 'charge.dispute.created':
        await handleDisputeCreated(event.data.object as Stripe.Dispute);
        break;

      default:
        // 未处理的事件类型：返回 200 告知 Stripe 已收到（避免重试）
        console.log(`[stripe-webhook] 忽略未处理事件 type=${event.type}`);
        break;
    }

    // 所有已处理事件均返回 200，Stripe 收到后不会重试
    return jsonResponse({ received: true, event_type: event.type });
  } catch (err) {
    const msg = err instanceof Error ? err.message : 'Internal handler error';
    console.error(`[stripe-webhook] 处理事件失败 type=${event.type}:`, err);
    // 返回 500 让 Stripe 按退避策略重试
    return jsonResponse({ error: msg }, 500);
  }
});
