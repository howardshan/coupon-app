// =============================================================
// Edge Function: capture-payment
// 在 coupon 核销时对预授权订单执行 Stripe payment capture（扣款）
// 由 merchant-scan/redeem 核销成功后内部调用
// 仅处理 is_captured = false 的订单（幂等：已扣款则跳过）
// =============================================================

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
    const { orderId } = await req.json();

    if (!orderId) {
      return new Response(
        JSON.stringify({ error: 'orderId is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    );

    // 查询订单
    const { data: order, error: orderErr } = await supabase
      .from('orders')
      .select('id, payment_intent_id, total_amount, is_captured, status')
      .eq('id', orderId)
      .single();

    if (orderErr || !order) {
      return new Response(
        JSON.stringify({ error: 'Order not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // 幂等：已扣款则直接返回
    if (order.is_captured) {
      console.log(`[capture-payment] order=${orderId} already captured, skip`);
      return new Response(
        JSON.stringify({ captured: false, reason: 'already_captured' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // 调用 Stripe capture，完成扣款
    const capturedIntent = await stripe.paymentIntents.capture(order.payment_intent_id);
    const chargeId = typeof capturedIntent.latest_charge === 'string'
      ? capturedIntent.latest_charge
      : (capturedIntent.latest_charge as { id: string } | null)?.id ?? null;

    const now = new Date().toISOString();

    // 更新订单 is_captured = true，记录 stripe_charge_id
    await supabase
      .from('orders')
      .update({
        is_captured: true,
        stripe_charge_id: chargeId,
        updated_at: now,
      })
      .eq('id', orderId);

    // 插入 payments 审计记录（幂等：payment_intent_id 有唯一约束）
    const { error: insertPaymentErr } = await supabase
      .from('payments')
      .insert({
        order_id: order.id,
        amount: order.total_amount,
        currency: 'usd',
        payment_intent_id: order.payment_intent_id,
        stripe_charge_id: chargeId,
        status: 'succeeded',
      });

    if (insertPaymentErr && insertPaymentErr.code !== '23505') {
      // 23505 = unique_violation（重复插入），视为正常，其他错误记录日志
      console.error('[capture-payment] insert payments failed:', insertPaymentErr);
    }

    console.log(`[capture-payment] captured order=${orderId} pi=${order.payment_intent_id} charge=${chargeId}`);

    return new Response(
      JSON.stringify({ captured: true, chargeId }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  } catch (err) {
    console.error('capture-payment error:', err);
    return new Response(
      JSON.stringify({ error: err instanceof Error ? err.message : 'Unknown error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  }
});
