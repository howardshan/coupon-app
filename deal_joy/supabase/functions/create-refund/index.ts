import Stripe from 'https://esm.sh/stripe@14?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2?target=deno';

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
    const { orderId, reason } = body;

    // 输入校验：orderId 必填且为非空字符串
    if (!orderId || typeof orderId !== 'string' || orderId.trim() === '') {
      return new Response(
        JSON.stringify({ error: 'orderId is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // 防止 reason 超长（数据库 text 列无硬限制，但业务上限制 500 字符）
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

    // 用户 JWT 客户端：仅用于初始 SELECT，强制 RLS 行归属校验
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: authHeader } } },
    );

    // Service role 客户端：绕过 RLS，用于写回 orders 和 payments
    // （普通用户 JWT 的 RLS UPDATE 策略只允许将 status 改为 refund_requested，
    //  无法直接写入 refunded；退款完成后需由受信任的服务端代码写入）
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    );

    // 查询订单：通过用户 JWT 客户端确保只能查到自己的订单（RLS）
    const { data: order, error: orderErr } = await supabase
      .from('orders')
      .select('payment_intent_id, total_amount, status, refund_requested_at')
      .eq('id', orderId)
      .single();

    if (orderErr || !order) {
      return new Response(
        JSON.stringify({ error: 'Order not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // 仅处理「已提交退款申请」的订单（管理员审核通过时调用）
    if (order.status !== 'refund_requested') {
      if (order.status === 'refunded') {
        return new Response(
          JSON.stringify({ error: 'Refund already completed' }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
        );
      }
      if (order.status === 'used' || order.status === 'expired') {
        return new Response(
          JSON.stringify({ error: 'Cannot refund used or expired order' }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
        );
      }
      return new Response(
        JSON.stringify({ error: 'Order must be in refund_requested status' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const now = new Date().toISOString();

    try {
      // 向 Stripe 发起退款
      const refund = await stripe.refunds.create({
        payment_intent: order.payment_intent_id,
        reason: 'requested_by_customer',
      });

      // 使用 service role 客户端更新 orders 表
      await supabaseAdmin
        .from('orders')
        .update({
          status: 'refunded',
          refund_reason: reason ?? 'customer_request',
          refund_requested_at: order.refund_requested_at ?? now,
          refunded_at: now,
          updated_at: now,
        })
        .eq('id', orderId);

      // 更新 payments 表
      await supabaseAdmin
        .from('payments')
        .update({
          status: 'refunded',
          refund_amount: order.total_amount,
        })
        .eq('order_id', orderId);

      // 将关联优惠券标记为已退款
      await supabaseAdmin
        .from('coupons')
        .update({ status: 'refunded' })
        .eq('order_id', orderId);

      return new Response(
        JSON.stringify({
          refundId: refund.id,
          status: refund.status,
          amount: Number(order.total_amount),
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    } catch (stripeErr: unknown) {
      // Stripe 退款失败：将订单标记为 refund_failed
      await supabaseAdmin
        .from('orders')
        .update({
          status: 'refund_failed',
          updated_at: now,
        })
        .eq('id', orderId);

      const message = stripeErr instanceof Error ? stripeErr.message : 'Stripe refund failed';
      return new Response(
        JSON.stringify({ error: message }),
        { status: 502, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
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
