import Stripe from 'https://esm.sh/stripe@14?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2?target=deno';
import { sendEmail } from '../_shared/email.ts';
import { buildC7Email } from '../_shared/email-templates/customer/refund-requested.ts';
import { buildC6Email } from '../_shared/email-templates/customer/store-credit-added.ts';

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
  apiVersion: '2024-04-10',
  httpClient: Stripe.createFetchHttpClient(),
});

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'Unauthorized' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const body = await req.json();
    const { orderItemId, refundMethod, reason } = body;

    // 参数校验：orderItemId 必填
    if (!orderItemId || typeof orderItemId !== 'string' || orderItemId.trim() === '') {
      return new Response(
        JSON.stringify({ error: 'orderItemId is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // 参数校验：refundMethod 必填，只允许两种值
    if (refundMethod !== 'store_credit' && refundMethod !== 'original_payment') {
      return new Response(
        JSON.stringify({ error: 'refundMethod must be store_credit or original_payment' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // 防止 reason 超长（业务上限制 500 字符）
    if (reason !== undefined && reason !== null) {
      if (typeof reason !== 'string') {
        return new Response(
          JSON.stringify({ error: 'reason must be a string' }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
        );
      }
      if (reason.length > 500) {
        return new Response(
          JSON.stringify({ error: 'reason must not exceed 500 characters' }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
        );
      }
    }

    // 用户 JWT 客户端：用于查询 order_item，强制 RLS 行归属校验（确保只能退自己的券）
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: authHeader } } },
    );

    // Service role 客户端：绕过 RLS，用于写回 order_items / coupons 以及调用 RPC
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    );

    // 查询 order_item 以及关联 order 的信息
    // 通过用户 JWT 客户端查询，RLS 保证只能查到自己订单下的 item
    const { data: item, error: itemErr } = await supabase
      .from('order_items')
      .select(`
        id,
        deal_id,
        unit_price,
        service_fee,
        customer_status,
        orders!inner (
          id,
          user_id,
          stripe_charge_id
        )
      `)
      .eq('id', orderItemId)
      .single();

    if (itemErr || !item) {
      return new Response(
        JSON.stringify({ error: 'Order item not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const order = item.orders as { id: string; user_id: string; stripe_charge_id: string };
    const customerStatus: string = item.customer_status ?? '';

    // 退款资格校验
    // - unused: 允许两种退款方式
    // - used: 核销后仅允许 store_credit（售后走线下）
    // - 其他状态（refund_success / refund_pending / expired 等）：拒绝
    if (customerStatus === 'used' && refundMethod === 'original_payment') {
      return new Response(
        JSON.stringify({ error: 'Used coupons can only be refunded via store credit' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    if (customerStatus !== 'unused' && customerStatus !== 'used') {
      return new Response(
        JSON.stringify({ error: `Cannot refund item with status: ${customerStatus}` }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const unitPrice = Number(item.unit_price ?? 0);
    const serviceFee = Number(item.service_fee ?? 0);
    const now = new Date().toISOString();

    if (refundMethod === 'store_credit') {
      // ── store_credit 退款流程 ──────────────────────────────────────────────
      // 退款金额包含 service fee（平台承担手续费补偿用户）
      const refundAmount = unitPrice + serviceFee;

      // 调用 RPC 增加用户 store credit 余额
      const { error: rpcErr } = await supabaseAdmin.rpc('add_store_credit', {
        p_user_id: order.user_id,
        p_amount: refundAmount,
        p_order_item_id: orderItemId,
        p_description: reason ?? 'Refund for order item',
      });

      if (rpcErr) {
        console.error('add_store_credit rpc error:', rpcErr);
        return new Response(
          JSON.stringify({ error: 'Failed to add store credit' }),
          { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
        );
      }

      // 更新 order_items
      await supabaseAdmin
        .from('order_items')
        .update({
          customer_status: 'refund_success',
          refunded_at: now,
          refund_amount: refundAmount,
          refund_method: 'store_credit',
          refund_reason: reason ?? null,
          updated_at: now,
        })
        .eq('id', orderItemId);

      // 将关联优惠券标记为已退款
      await supabaseAdmin
        .from('coupons')
        .update({ status: 'refunded', updated_at: now })
        .eq('order_item_id', orderItemId);

      // 发送邮件（即发即忘，不阻断核心流程）
      try {
        const { data: userInfo } = await supabaseAdmin
          .from('users').select('email').eq('id', order.user_id).single();
        const { data: dealInfo } = await supabaseAdmin
          .from('deals').select('title').eq('id', (item as any).deal_id).single();
        const dealTitle = (dealInfo?.title as string | undefined);

        if (userInfo?.email) {
          // C6：Store credit 余额到账
          const { subject: c6Subject, html: c6Html } = buildC6Email({ creditAmount: refundAmount, dealTitle });
          await sendEmail(supabaseAdmin, {
            to: userInfo.email, subject: c6Subject, htmlBody: c6Html,
            emailCode: 'C6', referenceId: orderItemId, recipientType: 'customer', userId: order.user_id,
          });

          // C7：退款申请已受理
          const { subject: c7Subject, html: c7Html } = buildC7Email({ refundAmount, refundMethod: 'store_credit', dealTitle });
          await sendEmail(supabaseAdmin, {
            to: userInfo.email, subject: c7Subject, htmlBody: c7Html,
            emailCode: 'C7', referenceId: orderItemId, recipientType: 'customer', userId: order.user_id,
          });
        }
      } catch (emailErr) {
        console.error('create-refund: email error (store_credit):', emailErr);
      }

      return new Response(
        JSON.stringify({
          success: true,
          refundMethod: 'store_credit',
          refundAmount,
          status: 'refund_success',
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );

    } else {
      // ── original_payment 退款流程 ─────────────────────────────────────────
      // 退款金额不含 service fee（Stripe 手续费无法追回）
      const refundAmount = unitPrice;

      if (!order.stripe_charge_id) {
        return new Response(
          JSON.stringify({ error: 'No Stripe charge found for this order' }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
        );
      }

      let stripeRefundId: string;
      try {
        // 向 Stripe 发起单券金额退款
        const refund = await stripe.refunds.create({
          charge: order.stripe_charge_id,
          amount: Math.round(refundAmount * 100), // 转换为分（cents）
          metadata: { order_item_id: orderItemId },
        });
        stripeRefundId = refund.id;
      } catch (stripeErr: unknown) {
        const message = stripeErr instanceof Error ? stripeErr.message : 'Stripe refund failed';
        console.error('Stripe refund error:', stripeErr);
        return new Response(
          JSON.stringify({ error: message }),
          { status: 502, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
        );
      }

      // Stripe 退款发起成功，先标记为 refund_pending
      // 等待 stripe-webhook 处理 charge.refunded 事件后再更新为 refund_success
      await supabaseAdmin
        .from('order_items')
        .update({
          customer_status: 'refund_pending',
          refund_amount: refundAmount,
          refund_method: 'original_payment',
          refund_reason: reason ?? null,
          updated_at: now,
        })
        .eq('id', orderItemId);

      // 将关联优惠券标记为已退款
      await supabaseAdmin
        .from('coupons')
        .update({ status: 'refunded', updated_at: now })
        .eq('order_item_id', orderItemId);

      // 发送邮件（即发即忘，不阻断核心流程）
      try {
        const { data: userInfo } = await supabaseAdmin
          .from('users').select('email').eq('id', order.user_id).single();
        const { data: dealInfo } = await supabaseAdmin
          .from('deals').select('title').eq('id', (item as any).deal_id).single();
        const dealTitle = (dealInfo?.title as string | undefined);

        if (userInfo?.email) {
          // C7：退款申请已受理（原支付方式，3-5 个工作日）
          const { subject: c7Subject, html: c7Html } = buildC7Email({ refundAmount, refundMethod: 'original_payment', dealTitle });
          await sendEmail(supabaseAdmin, {
            to: userInfo.email, subject: c7Subject, htmlBody: c7Html,
            emailCode: 'C7', referenceId: orderItemId, recipientType: 'customer', userId: order.user_id,
          });
        }
      } catch (emailErr) {
        console.error('create-refund: email error (original_payment):', emailErr);
      }

      return new Response(
        JSON.stringify({
          success: true,
          refundMethod: 'original_payment',
          refundAmount,
          stripeRefundId,
          status: 'refund_pending',
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

  } catch (err) {
    console.error('create-refund error:', err);
    return new Response(
      JSON.stringify({ error: err instanceof Error ? err.message : 'Unknown error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  }
});
