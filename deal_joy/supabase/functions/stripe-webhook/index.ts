// Stripe Webhook 处理函数
// 接收 Stripe 发送的支付事件，更新订单/优惠券/支付记录
// 使用 service role key 绕过 RLS（webhook 无用户身份）

import Stripe from 'https://esm.sh/stripe@14?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2?target=deno';
import { sendEmail } from '../_shared/email.ts';
import { buildC8Email } from '../_shared/email-templates/customer/refund-completed.ts';

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

// ─── 事件处理：payment_intent.succeeded（广告充值分支）──────────────────────
// 广告充值成功：调用 add_ad_balance RPC 原子更新余额
// 幂等性完全由 RPC 内部保证
async function handleAdRechargeSucceeded(paymentIntent: Stripe.PaymentIntent): Promise<void> {
  const paymentIntentId = paymentIntent.id;
  const merchantId = paymentIntent.metadata.merchant_id;
  const amount = paymentIntent.amount / 100;

  console.log(`[ad_recharge.succeeded] pi=${paymentIntentId} merchant=${merchantId} amount=${amount}`);

  // 调用 RPC：内部完成 recharge 状态更新 + 余额增加，同一事务
  const { data: result, error: rpcErr } = await supabase.rpc('add_ad_balance', {
    p_merchant_id: merchantId,
    p_amount: amount,
    p_payment_intent_id: paymentIntentId,
  });

  if (rpcErr) {
    console.error('[ad_recharge.succeeded] add_ad_balance RPC 失败:', rpcErr);
    throw new Error(`add_ad_balance 失败: ${rpcErr.message}`);
  }

  console.log(`[ad_recharge.succeeded] 结果: ${result}`);

  // 发送通知给商家
  if (result === 'ok') {
    try {
      const { data: merchant } = await supabase
        .from('merchants')
        .select('user_id, name')
        .eq('id', merchantId)
        .single();

      if (merchant?.user_id) {
        fetch(`${Deno.env.get('SUPABASE_URL')}/functions/v1/send-push-notification`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`,
          },
          body: JSON.stringify({
            user_id: merchant.user_id,
            type: 'transaction',
            title: 'Ad Credit Added',
            body: `$${amount.toFixed(2)} has been added to your ad account.`,
            data: { type: 'ad_recharge', merchant_id: merchantId },
          }),
        });
      }
    } catch (notifyErr) {
      console.error('[ad_recharge.succeeded] 通知发送失败:', notifyErr);
    }
  }
}

// ─── 事件处理：payment_intent.succeeded（订单支付分支）────────────────────────
// 支付成功：写入 payments 审计记录，同时更新 orders.paid_at（如为 null）
// 幂等：payments 表 payment_intent_id 有 UNIQUE 约束
async function handlePaymentSucceeded(paymentIntent: Stripe.PaymentIntent): Promise<void> {
  // 广告充值走独立逻辑
  if (paymentIntent.metadata?.type === 'ad_recharge') {
    return handleAdRechargeSucceeded(paymentIntent);
  }

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
    .select('id, user_id, total_amount, status, paid_at')
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

  // 更新订单：记录 stripe_charge_id，并在 paid_at 为 null 时补填支付时间
  const orderUpdateFields: Record<string, unknown> = {
    updated_at: new Date().toISOString(),
  };
  if (chargeId) {
    orderUpdateFields.stripe_charge_id = chargeId;
  }
  if (!order.paid_at) {
    orderUpdateFields.paid_at = new Date().toISOString();
  }

  const { error: updateOrderErr } = await supabase
    .from('orders')
    .update(orderUpdateFields)
    .eq('id', order.id);

  if (updateOrderErr) {
    console.error('[payment_intent.succeeded] 更新订单失败:', updateOrderErr);
    // 非致命错误，继续写 payments 记录
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

  console.log(`[payment_intent.succeeded] 完成 order=${order.id} paid_at=${orderUpdateFields.paid_at ?? '已有值'}`);
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

  // 广告充值失败：更新 ad_recharges 状态为 failed
  if (paymentIntent.metadata?.type === 'ad_recharge') {
    console.log(`[ad_recharge.failed] pi=${paymentIntentId}`);
    const { error: updateErr } = await supabase
      .from('ad_recharges')
      .update({ status: 'failed' })
      .eq('stripe_payment_intent_id', paymentIntentId)
      .eq('status', 'pending');  // 只更新 pending 状态的记录

    if (updateErr) {
      console.error('[ad_recharge.failed] 更新 ad_recharges 失败:', updateErr);
    }
    return;  // 广告充值失败不需要继续处理订单逻辑
  }

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
// 退款完成（Order V3 per-item 退款模式）：
//   - 有 order_item_id（来自 refund.metadata）：仅更新对应 order_item 的退款状态
//   - 无 order_item_id（旧订单兼容）：保持原有整单退款逻辑
// 同时更新 payments 表退款金额和状态
async function handleChargeRefunded(charge: Stripe.Charge): Promise<void> {
  const chargeId = charge.id;
  const paymentIntentId = typeof charge.payment_intent === 'string'
    ? charge.payment_intent
    : charge.payment_intent?.id ?? null;

  // 退款金额（Stripe 单位为 cents，转为美元）
  const refundAmountCents = charge.amount_refunded ?? 0;
  const refundAmount = refundAmountCents / 100;

  console.log(
    `[charge.refunded] charge=${chargeId} pi=${paymentIntentId} refund_amount=${refundAmount}`,
  );

  if (!paymentIntentId) {
    console.warn('[charge.refunded] charge 没有关联的 payment_intent，跳过');
    return;
  }

  // 从最新的 refund 对象的 metadata 中获取 order_item_id
  // Stripe charge.refunds 是分页列表，取第一条（最新退款）
  const latestRefund = charge.refunds?.data?.[0];
  const orderItemId = latestRefund?.metadata?.order_item_id ?? null;

  console.log(`[charge.refunded] order_item_id=${orderItemId ?? '无（旧订单兼容模式）'}`);

  // 通过 payment_intent_id 找到订单（无论哪种模式都需要）
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

  const now = new Date().toISOString();

  if (orderItemId) {
    // ── per-item 退款模式（Order V3）────────────────────────────────────────
    // 从 refund 对象获取本次退款金额（单条 refund，不是累计金额）
    const itemRefundAmountCents = latestRefund?.amount ?? 0;
    const itemRefundAmount = itemRefundAmountCents / 100;

    const { error: updateItemErr } = await supabase
      .from('order_items')
      .update({
        customer_status: 'refund_success',
        refunded_at: now,
        refund_amount: itemRefundAmount,
        updated_at: now,
      })
      .eq('id', orderItemId);

    if (updateItemErr) {
      console.error('[charge.refunded] 更新 order_item 退款状态失败:', updateItemErr);
      throw new Error(`更新 order_item 失败: ${updateItemErr.message}`);
    }

    console.log(
      `[charge.refunded] per-item 退款完成 order_item=${orderItemId} refund=${itemRefundAmount}`,
    );
  } else {
    // ── 旧订单兼容：整单退款模式 ─────────────────────────────────────────────
    // 更新订单状态为 refunded
    const { error: updateOrderErr } = await supabase
      .from('orders')
      .update({
        status: 'refunded',
        stripe_charge_id: chargeId,
        updated_at: now,
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

    console.log(`[charge.refunded] 整单退款完成 order=${order.id} refund=${refundAmount}`);
  }

  // ── 更新 payments 表退款信息（两种模式都执行）────────────────────────────
  // P1 fix: 只做 UPDATE，不做 upsert INSERT。
  // upsert 的 INSERT 路径需要填充所有 NOT NULL 列（user_id, amount, currency），
  // 但 charge.refunded 事件不携带这些字段，若行不存在则会触发 NOT NULL 违规。
  // 正常业务流程下 payment_intent.succeeded 总先于 charge.refunded 到达；
  // 若行确实不存在，只记录警告。
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
      // 记录但不抛出，主要业务逻辑已完成
    }
  }

  // 发送 C8 邮件（即发即忘，不阻断 webhook 响应）
  try {
    // 获取客户邮箱
    const { data: orderDetail } = await supabase
      .from('orders').select('user_id').eq('id', order.id).single();
    const userId = orderDetail?.user_id as string | null;

    if (userId) {
      const { data: userInfo } = await supabase
        .from('users').select('email').eq('id', userId).single();

      if (userInfo?.email) {
        // 从 Stripe charge 获取银行卡末四位
        const cardLast4 = (charge.payment_method_details as any)?.card?.last4 as string | undefined;

        // 如果是 per-item 退款，尝试获取 deal 标题
        let dealTitle: string | undefined;
        if (orderItemId) {
          const { data: itemDetail } = await supabase
            .from('order_items').select('deal_id, deals(title)').eq('id', orderItemId).single();
          dealTitle = (itemDetail as any)?.deals?.title as string | undefined;
        }

        const itemRefundAmount = orderItemId
          ? (latestRefund?.amount ?? 0) / 100
          : refundAmount;

        const { subject, html } = buildC8Email({ refundAmount: itemRefundAmount, cardLast4, dealTitle });
        await sendEmail(supabase, {
          to: userInfo.email, subject, htmlBody: html,
          emailCode: 'C8', referenceId: orderItemId ?? order.id, recipientType: 'customer', userId,
        });
      }
    }
  } catch (emailErr) {
    console.error('[charge.refunded] C8 email error:', emailErr);
  }

  console.log(`[charge.refunded] 处理完成 order=${order.id}`);
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

// ─── Connect 子账户事件处理 ───────────────────────────────────────────────────

/**
 * account.updated — 商家 Connect 账户状态变更
 * 当商家完成 Stripe Connect 入驻（或状态变更）时自动触发
 * 将 stripe_account_status 同步到 merchants 表
 */
async function handleAccountUpdated(account: Stripe.Account): Promise<void> {
  const accountId = account.id;
  const chargesEnabled = account.charges_enabled ?? false;
  const payoutsEnabled = account.payouts_enabled ?? false;
  const disabledReason = account.requirements?.disabled_reason ?? null;

  // 判断入驻完成状态
  const status = (chargesEnabled && payoutsEnabled)
    ? 'connected'
    : disabledReason
    ? 'restricted'
    : 'pending';

  console.log(`[account.updated] acct=${accountId} charges=${chargesEnabled} payouts=${payoutsEnabled} → status=${status}`);

  const { error } = await supabase
    .from('merchants')
    .update({
      stripe_account_status: status,
      stripe_account_email: account.email ?? null,
    })
    .eq('stripe_account_id', accountId);

  if (error) {
    console.error(`[account.updated] 更新 merchants 失败 acct=${accountId}:`, error);
    // 不抛出：状态同步失败不应阻断 webhook 响应（Stripe 否则会重试）
  }
}

/**
 * payout.paid — 商家 Connect 账户成功出金到银行
 * 记录日志，可选更新 withdrawals 表状态
 */
async function handlePayoutPaid(payout: Stripe.Payout, connectedAccountId: string): Promise<void> {
  const amount = payout.amount / 100;
  console.log(`[payout.paid] acct=${connectedAccountId} amount=${amount} payout=${payout.id}`);

  // 若 withdrawal 记录存储了 stripe_transfer_id，可在此更新状态为 payout_completed
  // 暂时只记录日志，后续按需扩展
}

/**
 * payout.failed — 商家 Connect 账户出金失败
 * 记录告警，TODO：可发送邮件/Slack 通知运营团队
 */
async function handlePayoutFailed(payout: Stripe.Payout, connectedAccountId: string): Promise<void> {
  const amount = payout.amount / 100;
  console.error(
    `[payout.failed] acct=${connectedAccountId} amount=${amount} payout=${payout.id}` +
    ` reason=${payout.failure_message ?? payout.failure_code ?? 'unknown'}`,
  );
  // TODO: 生产环境在此处发送运营告警（邮件/Slack）
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

  // 读取 Webhook Secrets（平台账户 + Connect 子账户各一个）
  const platformSecret = Deno.env.get('STRIPE_WEBHOOK_SECRET');
  const connectSecret = Deno.env.get('STRIPE_CONNECT_WEBHOOK_SECRET');
  if (!platformSecret) {
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

  // 验证 Stripe 签名：先尝试平台 secret，失败则尝试 Connect secret
  // 两个 webhook endpoint 指向同一 URL，通过 secret 区分来源
  let event: Stripe.Event;
  let isConnectEvent = false;
  try {
    event = await stripe.webhooks.constructEventAsync(rawBody, sigHeader, platformSecret);
  } catch (_platformErr) {
    if (!connectSecret) {
      console.warn('[stripe-webhook] 平台签名验证失败且未配置 STRIPE_CONNECT_WEBHOOK_SECRET');
      return jsonResponse({ error: 'Signature verification failed' }, 400);
    }
    try {
      event = await stripe.webhooks.constructEventAsync(rawBody, sigHeader, connectSecret);
      isConnectEvent = true;
    } catch (connectErr) {
      const msg = connectErr instanceof Error ? connectErr.message : 'Signature verification failed';
      console.warn(`[stripe-webhook] 两个 secret 均验签失败: ${msg}`);
      return jsonResponse({ error: msg }, 400);
    }
  }

  console.log(`[stripe-webhook] 收到事件 type=${event.type} id=${event.id} isConnect=${isConnectEvent}`);

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

      case 'charge.dispute.created':
        await handleDisputeCreated(event.data.object as Stripe.Dispute);
        break;

      // ── Connect 子账户事件 ────────────────────────────────────────────
      case 'account.updated':
        if (isConnectEvent) {
          await handleAccountUpdated(event.data.object as Stripe.Account);
        }
        break;

      case 'payout.paid':
        if (isConnectEvent) {
          await handlePayoutPaid(event.data.object as Stripe.Payout, event.account ?? '');
        }
        break;

      case 'payout.failed':
        if (isConnectEvent) {
          await handlePayoutFailed(event.data.object as Stripe.Payout, event.account ?? '');
        }
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
