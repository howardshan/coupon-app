import Stripe from 'https://esm.sh/stripe@14?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2?target=deno';
import { resolveAuth } from '../_shared/auth.ts';

// ============================================================
// create-ad-recharge：商家广告账户充值
// 入参: { amount: number }  — 单位：美元，范围 $20 ~ $5000
// 流程：鉴权 → 查 ad_account → 查 stripe_customer_id → 创建 PaymentIntent → 写 ad_recharges
// ============================================================

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
  apiVersion: '2024-04-10',
  httpClient: Stripe.createFetchHttpClient(),
});

// 使用 service_role client，绕过 RLS
const supabase = createClient(
  Deno.env.get('SUPABASE_URL') ?? '',
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
);

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// 统一错误响应
function errorResponse(message: string, status = 400) {
  return new Response(
    JSON.stringify({ error: message }),
    { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
  );
}

// ============================================================
// 主处理逻辑
// ============================================================
Deno.serve(async (req) => {
  // 处理 CORS 预检请求
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // ---------- 鉴权 ----------
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return errorResponse('Missing Authorization header', 401);
    }
    const token = authHeader.replace('Bearer ', '');

    const { data: { user }, error: authError } = await supabase.auth.getUser(token);
    if (authError || !user) {
      return errorResponse('Unauthorized', 401);
    }

    // 使用 resolveAuth 获取 merchantId（支持多角色：owner / staff / brand admin）
    let auth;
    try {
      auth = await resolveAuth(supabase, user.id, req.headers);
    } catch (e) {
      return errorResponse(e instanceof Error ? e.message : 'Auth failed', 403);
    }
    const merchantId = auth.merchantId;

    // ---------- 参数校验 ----------
    const body = await req.json();
    const { amount } = body;

    if (typeof amount !== 'number' || isNaN(amount)) {
      return errorResponse('amount must be a number');
    }

    // 金额限制：$20 ~ $5000
    if (amount < 20) {
      return errorResponse('Minimum recharge amount is $20');
    }
    if (amount > 5000) {
      return errorResponse('Maximum recharge amount is $5000');
    }

    // ---------- 查询 ad_account ----------
    const { data: adAccount, error: adAccountError } = await supabase
      .from('ad_accounts')
      .select('id')
      .eq('merchant_id', merchantId)
      .single();

    if (adAccountError || !adAccount) {
      console.error('查询 ad_account 失败:', adAccountError);
      return errorResponse('Ad account not found for this merchant', 404);
    }
    const adAccountId = adAccount.id;

    // ---------- 查询 merchant.user_id → users.stripe_customer_id ----------
    // 先查 merchants 表拿到 owner 的 user_id（充值绑定 owner 的 Stripe Customer）
    const { data: merchant, error: merchantError } = await supabase
      .from('merchants')
      .select('user_id')
      .eq('id', merchantId)
      .single();

    if (merchantError || !merchant) {
      console.error('查询 merchant 失败:', merchantError);
      return errorResponse('Merchant not found', 404);
    }

    // 查 owner 的 stripe_customer_id
    const { data: ownerUser, error: userError } = await supabase
      .from('users')
      .select('stripe_customer_id')
      .eq('id', merchant.user_id)
      .single();

    if (userError || !ownerUser) {
      console.error('查询 owner user 失败:', userError);
      return errorResponse('Merchant owner not found', 404);
    }

    const stripeCustomerId = ownerUser.stripe_customer_id as string | null;

    // 必须已绑定支付方式才能充值
    if (!stripeCustomerId) {
      return errorResponse(
        'No payment method found. Please add a payment method before recharging.',
        422,
      );
    }

    // ---------- 创建 Stripe PaymentIntent ----------
    const amountInCents = Math.round(amount * 100);

    const paymentIntent = await stripe.paymentIntents.create({
      amount: amountInCents,
      currency: 'usd',
      customer: stripeCustomerId,
      // 信用卡模式：只允许 card，方便 merchant 端 PaymentSheet 使用
      payment_method_types: ['card'],
      payment_method_options: {
        card: {
          // 要求重新输入 CVV，保障安全
          require_cvc_recollection: true,
        },
      },
      metadata: {
        merchant_id: merchantId,
        ad_account_id: adAccountId,
        type: 'ad_recharge',
      },
    });

    // ---------- 写入 ad_recharges 记录（status = 'pending'） ----------
    // stripe-webhook 在支付成功后调用 add_ad_balance() 更新状态并到账
    const { error: insertError } = await supabase
      .from('ad_recharges')
      .insert({
        merchant_id: merchantId,
        ad_account_id: adAccountId,
        amount,
        stripe_payment_intent_id: paymentIntent.id,
        status: 'pending',
      });

    if (insertError) {
      console.error('写入 ad_recharges 失败:', insertError);
      // 写 DB 失败后尝试取消 PaymentIntent，防止孤儿支付
      try {
        await stripe.paymentIntents.cancel(paymentIntent.id);
      } catch (cancelErr) {
        console.error('取消 PaymentIntent 失败（手动介入）:', cancelErr);
      }
      return errorResponse('Failed to create recharge record', 500);
    }

    // ---------- 返回 clientSecret ----------
    return new Response(
      JSON.stringify({
        clientSecret: paymentIntent.client_secret,
        paymentIntentId: paymentIntent.id,
        amount,
        adAccountId,
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );

  } catch (err) {
    console.error('create-ad-recharge error:', err);
    return new Response(
      JSON.stringify({ error: err instanceof Error ? err.message : 'Unknown error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  }
});
