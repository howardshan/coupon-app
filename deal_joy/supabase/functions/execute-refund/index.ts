// Edge Function: execute-refund (内部调用)
// 执行实际的 Stripe 退款操作
// 由 merchant-orders/refund-requests/:id PATCH（商家批准）和 admin-refund（管理员批准）调用
// 不对外暴露给普通用户

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
    const body = await req.json();
    const { refundRequestId, approvedBy } = body as {
      refundRequestId?: string;
      approvedBy?: 'merchant' | 'admin';
    };

    if (!refundRequestId) {
      return new Response(
        JSON.stringify({ error: 'refundRequestId is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
    const serviceClient = createClient(supabaseUrl, serviceRoleKey);

    // 查询退款申请（含关联订单）
    const { data: refundReq, error: rrError } = await serviceClient
      .from('refund_requests')
      .select('id, order_id, refund_amount, status, orders(payment_intent_id, is_captured, total_amount)')
      .eq('id', refundRequestId)
      .single();

    if (rrError || !refundReq) {
      return new Response(
        JSON.stringify({ error: 'Refund request not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // 幂等性检查：已完成则直接返回成功
    if (refundReq.status === 'completed') {
      return new Response(
        JSON.stringify({ success: true, message: 'Already completed' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const order = refundReq.orders as { payment_intent_id: string; is_captured: boolean; total_amount: number } | null;
    if (!order) {
      return new Response(
        JSON.stringify({ error: 'Order not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const now = new Date().toISOString();
    let refundId: string;
    let refundStatus: string;

    try {
      if (!order.is_captured) {
        // 预授权未扣款 → 取消授权
        const cancelled = await stripe.paymentIntents.cancel(order.payment_intent_id);
        refundId = cancelled.id;
        refundStatus = cancelled.status;
        console.log(`[execute-refund] cancelled pre-auth pi=${order.payment_intent_id}`);
      } else {
        // 已扣款 → 标准 Stripe 退款
        const refundAmountCents = Math.round(Number(refundReq.refund_amount) * 100);
        const refund = await stripe.refunds.create({
          payment_intent: order.payment_intent_id,
          amount: refundAmountCents,
          reason: 'requested_by_customer',
        });
        refundId = refund.id;
        refundStatus = refund.status;
        console.log(`[execute-refund] stripe refund created refund=${refundId}`);
      }
    } catch (stripeErr) {
      // Stripe 失败 → 标记 refund_failed（不更新 refund_requests 状态，保留在审批状态）
      const message = stripeErr instanceof Error ? stripeErr.message : 'Stripe refund failed';
      console.error('[execute-refund] stripe error:', message);
      return new Response(
        JSON.stringify({ error: message }),
        { status: 502, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // 更新退款申请 → completed
    const completedStatus = approvedBy === 'admin' ? 'approved_admin' : 'approved_merchant';
    await serviceClient
      .from('refund_requests')
      .update({
        status: 'completed',
        [`${completedStatus === 'approved_merchant' ? 'merchant' : 'admin'}_decided_at`]: now,
        updated_at: now,
      })
      .eq('id', refundRequestId);

    // 更新订单 → refunded
    await serviceClient
      .from('orders')
      .update({
        status: 'refunded',
        refunded_at: now,
        updated_at: now,
      })
      .eq('id', refundReq.order_id);

    // 更新 payments 表
    await serviceClient
      .from('payments')
      .update({
        status: 'refunded',
        refund_amount: refundReq.refund_amount,
      })
      .eq('order_id', refundReq.order_id);

    // 更新关联券状态 → refunded
    await serviceClient
      .from('coupons')
      .update({ status: 'refunded' })
      .eq('order_id', refundReq.order_id);

    return new Response(
      JSON.stringify({
        success: true,
        refundId,
        refundStatus,
        amount: Number(refundReq.refund_amount),
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  } catch (err) {
    console.error('[execute-refund] error:', err);
    return new Response(
      JSON.stringify({ error: err instanceof Error ? err.message : 'Unknown error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  }
});
