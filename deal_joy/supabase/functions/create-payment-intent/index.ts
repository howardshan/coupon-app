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
  // 处理 CORS 预检请求
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const { amount, currency = 'usd', dealId, userId } = await req.json();

    if (!amount || amount <= 0) {
      return new Response(
        JSON.stringify({ error: 'Invalid amount' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // dealId 必填：用于服务端查询 validity_type 决定支付模式
    if (!dealId) {
      return new Response(
        JSON.stringify({ error: 'dealId is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // 服务端查询 deal 的 validity_type，不信任客户端传入
    // short_after_purchase → 预授权（manual capture），核销时才实收
    // 其他类型 → 立即扣款（automatic capture）
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    );

    const { data: deal } = await supabaseAdmin
      .from('deals')
      .select('validity_type')
      .eq('id', dealId)
      .single();

    // deal 查不到时降级为自动扣款，不阻断支付流程
    const isPreAuth = deal?.validity_type === 'short_after_purchase';
    const captureMethod = isPreAuth ? 'manual' : 'automatic';

    // 创建 PaymentIntent（金额单位：分）
    const paymentIntent = await stripe.paymentIntents.create({
      amount: Math.round(amount * 100),
      currency,
      capture_method: captureMethod,
      automatic_payment_methods: { enabled: true },
      metadata: {
        deal_id: dealId ?? '',
        user_id: userId ?? '',
      },
    });

    return new Response(
      JSON.stringify({
        clientSecret: paymentIntent.client_secret,
        paymentIntentId: paymentIntent.id,
        // 返回 captureMethod 供客户端写入 orders.capture_method
        captureMethod,
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  } catch (err) {
    console.error('create-payment-intent error:', err);
    return new Response(
      JSON.stringify({ error: err instanceof Error ? err.message : 'Unknown error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  }
});
