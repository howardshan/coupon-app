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

// 预授权有效期阈值：deal 到期时间在 7 天内则使用预授权
const PREAUTH_THRESHOLD_DAYS = 7;

Deno.serve(async (req) => {
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

    // 根据 deal 有效期决定扣款模式
    // manual = 预授权（只冻结资金，核销时才扣款）
    // automatic = 即时扣款
    let captureMethod: 'automatic' | 'manual' = 'automatic';

    if (dealId) {
      const supabase = createClient(
        Deno.env.get('SUPABASE_URL') ?? '',
        Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      );
      const { data: deal } = await supabase
        .from('deals')
        .select('expires_at')
        .eq('id', dealId)
        .maybeSingle();

      if (deal?.expires_at) {
        const expiresAt = new Date(deal.expires_at);
        const thresholdDate = new Date();
        thresholdDate.setDate(thresholdDate.getDate() + PREAUTH_THRESHOLD_DAYS);
        // 到期时间在 7 天内 → 使用预授权
        if (expiresAt <= thresholdDate) {
          captureMethod = 'manual';
        }
      }
    }

    const paymentIntent = await stripe.paymentIntents.create({
      amount: Math.round(amount * 100),
      currency,
      capture_method: captureMethod,
      automatic_payment_methods: { enabled: true },
      metadata: {
        deal_id: dealId ?? '',
        user_id: userId ?? '',
        capture_method: captureMethod,
      },
    });

    return new Response(
      JSON.stringify({
        clientSecret: paymentIntent.client_secret,
        paymentIntentId: paymentIntent.id,
        captureMethod, // 告知客户端是预授权还是即时扣款，用于 UI 提示
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
