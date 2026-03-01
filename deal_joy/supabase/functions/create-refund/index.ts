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

    const { orderId, reason } = await req.json();

    // Init Supabase with user's JWT to enforce RLS
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: authHeader } } },
    );

    // Fetch order + payment intent
    const { data: order, error: orderErr } = await supabase
      .from('orders')
      .select('payment_intent_id, total_amount, status')
      .eq('id', orderId)
      .single();

    if (orderErr || !order) {
      return new Response(
        JSON.stringify({ error: 'Order not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    if (order.status === 'used') {
      return new Response(
        JSON.stringify({ error: 'Cannot refund a used coupon' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // Issue Stripe refund
    const refund = await stripe.refunds.create({
      payment_intent: order.payment_intent_id,
      reason: 'requested_by_customer',
    });

    // Update order status in DB
    await supabase
      .from('orders')
      .update({ status: 'refunded', refund_reason: reason ?? 'customer_request', updated_at: new Date().toISOString() })
      .eq('id', orderId);

    await supabase
      .from('coupons')
      .update({ status: 'refunded' })
      .eq('order_id', orderId);

    return new Response(
      JSON.stringify({ refundId: refund.id, status: refund.status }),
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
