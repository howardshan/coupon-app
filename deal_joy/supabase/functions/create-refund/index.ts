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

    // 防重复退款：已申请或已完成退款的订单不可再次提交
    if (order.status === 'refunded' || order.status === 'refund_requested') {
      return new Response(
        JSON.stringify({ error: 'Refund already requested or completed' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // 已过期订单由自动退款任务（auto-refund-expired）处理，不接受手动退款
    if (order.status === 'expired') {
      return new Response(
        JSON.stringify({ error: 'Cannot manually refund an expired order' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // 已核销的优惠券不可退款
    if (order.status === 'used') {
      return new Response(
        JSON.stringify({ error: 'Cannot refund a used coupon' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // 向 Stripe 发起退款请求
    const refund = await stripe.refunds.create({
      payment_intent: order.payment_intent_id,
      reason: 'requested_by_customer',
    });

    const now = new Date().toISOString();

    // 使用 service role 客户端更新 orders 表
    // refund_requested_at：若之前已设置（预申请流程）则保留原值，否则记录为当前时间
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

    // 更新 payments 表，记录退款状态和金额
    await supabaseAdmin
      .from('payments')
      .update({
        status: 'refunded',
        refund_amount: order.total_amount,
      })
      .eq('order_id', orderId);

    // 使用 service role 客户端将关联优惠券标记为已退款
    await supabaseAdmin
      .from('coupons')
      .update({ status: 'refunded' })
      .eq('order_id', orderId);

    return new Response(
      JSON.stringify({
        refundId: refund.id,
        status: refund.status,
        // 前端用于显示退款金额（单位：美元）
        amount: Number(order.total_amount),
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  } catch (err) {
    console.error('create-refund error:', err);
    return new Response(
      JSON.stringify({ error: err instanceof Error ? err.message : 'Unknown error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  }
});
