import Stripe from 'https://esm.sh/stripe@14?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// Stripe 客户端（验证 PaymentIntent 状态）
const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
  apiVersion: '2024-04-10',
  httpClient: Stripe.createFetchHttpClient(),
});

// CORS 请求头
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// 每张券的固定服务费
const SERVICE_FEE_PER_COUPON = 0.99;

// 有效的 PaymentIntent 状态（预授权或已扣款均视为成功）
const VALID_PI_STATUSES = new Set([
  'succeeded',
  'requires_capture',  // manual capture 预授权状态
]);

// 统一 JSON 响应工具
function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req) => {
  // 处理 CORS 预检请求
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // ----------------------------------------------------------------
    // 1. 验证 Authorization header，获取当前登录用户
    // ----------------------------------------------------------------
    const authHeader = req.headers.get('Authorization');
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return jsonResponse({ error: 'Missing or invalid Authorization header' }, 401);
    }
    const jwt = authHeader.replace('Bearer ', '');

    // 用 anon key + JWT 验证用户身份
    const anonClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: `Bearer ${jwt}` } } },
    );

    const { data: { user }, error: authError } = await anonClient.auth.getUser();
    if (authError || !user) {
      return jsonResponse({ error: 'Unauthorized: invalid JWT' }, 401);
    }

    // ----------------------------------------------------------------
    // 2. 解析并校验请求体
    // ----------------------------------------------------------------
    const body = await req.json();
    const {
      paymentIntentId,
      userId,
      items,
      serviceFeeTotal,
      subtotal,
      totalDiscount,
      totalAmount,
      cartItemIds,
    } = body;

    if (!paymentIntentId) {
      return jsonResponse({ error: 'paymentIntentId is required' }, 400);
    }
    if (!userId) {
      return jsonResponse({ error: 'userId is required' }, 400);
    }
    if (!Array.isArray(items) || items.length === 0) {
      return jsonResponse({ error: 'items must be a non-empty array' }, 400);
    }
    if (typeof totalAmount !== 'number' || totalAmount <= 0) {
      return jsonResponse({ error: 'totalAmount must be a positive number' }, 400);
    }

    // 防止越权：JWT 用户必须与传入 userId 一致
    if (user.id !== userId) {
      return jsonResponse({ error: 'Forbidden: userId mismatch' }, 403);
    }

    // ----------------------------------------------------------------
    // 3. 验证 PaymentIntent 状态（通过 Stripe API 查询）
    // ----------------------------------------------------------------
    let paymentIntent;
    try {
      paymentIntent = await stripe.paymentIntents.retrieve(paymentIntentId);
    } catch (stripeErr) {
      console.error('Stripe retrieve error:', stripeErr);
      return jsonResponse({ error: 'Failed to retrieve PaymentIntent from Stripe' }, 502);
    }

    if (!VALID_PI_STATUSES.has(paymentIntent.status)) {
      return jsonResponse(
        { error: `PaymentIntent status is "${paymentIntent.status}", expected succeeded or requires_capture` },
        400,
      );
    }

    // 额外校验：PaymentIntent 金额需与请求体一致（单位：分）
    const expectedAmountCents = Math.round(totalAmount * 100);
    if (paymentIntent.amount !== expectedAmountCents) {
      console.warn(
        `Amount mismatch: PI=${paymentIntent.amount} cents, request=${expectedAmountCents} cents`,
      );
      // 仅告警，不阻断（汇率/舍入误差允许 1 分偏差）
      if (Math.abs(paymentIntent.amount - expectedAmountCents) > 1) {
        return jsonResponse({ error: 'PaymentIntent amount does not match totalAmount' }, 400);
      }
    }

    // ----------------------------------------------------------------
    // 4. 使用 service_role client 执行写操作（绕过 RLS）
    // ----------------------------------------------------------------
    const serviceClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    );

    // 幂等检查：同一个 PaymentIntent 是否已创建过订单
    const { data: existingOrder } = await serviceClient
      .from('orders')
      .select('id, order_number')
      .eq('payment_intent_id', paymentIntentId)
      .maybeSingle();

    if (existingOrder) {
      // 已存在则直接返回（幂等）
      const { count: itemCount } = await serviceClient
        .from('order_items')
        .select('id', { count: 'exact', head: true })
        .eq('order_id', existingOrder.id);

      return jsonResponse({
        orderId: existingOrder.id,
        orderNumber: existingOrder.order_number,
        itemCount: itemCount ?? items.length,
      });
    }

    // ----------------------------------------------------------------
    // 5. INSERT orders（单条）
    // ----------------------------------------------------------------
    const { data: orderRow, error: orderError } = await serviceClient
      .from('orders')
      .insert({
        user_id: userId,
        payment_intent_id: paymentIntentId,
        items_amount: subtotal ?? null,
        service_fee_total: serviceFeeTotal ?? 0,
        total_amount: totalAmount,
        paid_at: new Date().toISOString(),
        // V3 orders 不再依赖旧字段，兼容性设置
        deal_id: items[0].dealId,      // 取第一个 deal 作为 legacy 兼容
        unit_price: items[0].unitPrice,
        quantity: items.length,
        status: 'unused',
      })
      .select('id')
      .single();

    if (orderError) {
      console.error('Insert order error:', orderError);
      return jsonResponse({ error: `Failed to create order: ${orderError.message}` }, 500);
    }

    const orderId: string = orderRow.id;

    // 生成订单号：'CP-' + id 前 8 位大写
    const orderNumber = `CP-${orderId.replace(/-/g, '').substring(0, 8).toUpperCase()}`;
    await serviceClient
      .from('orders')
      .update({ order_number: orderNumber })
      .eq('id', orderId);

    // ----------------------------------------------------------------
    // 6. INSERT order_items（每个 item 一行）
    //    每张券固定收取 $0.99 service fee
    // ----------------------------------------------------------------

    const orderItemsPayload = items.map((item: {
      dealId: string;
      unitPrice: number;
      selectedOptions: unknown;
      purchasedMerchantId: string;
    }) => {
      return {
        order_id: orderId,
        deal_id: item.dealId,
        unit_price: item.unitPrice,
        service_fee: SERVICE_FEE_PER_COUPON,
        purchased_merchant_id: item.purchasedMerchantId ?? null,
        selected_options: item.selectedOptions ?? null,
        customer_status: 'unused',
        merchant_status: 'unused',
      };
    });

    const { error: itemsError } = await serviceClient
      .from('order_items')
      .insert(orderItemsPayload);

    if (itemsError) {
      console.error('Insert order_items error:', itemsError);
      // 回滚：删除刚创建的 order（触发级联删除 order_items）
      await serviceClient.from('orders').delete().eq('id', orderId);
      return jsonResponse({ error: `Failed to create order items: ${itemsError.message}` }, 500);
    }

    // ----------------------------------------------------------------
    // 7. DELETE cart_items（清空购物车中已结账的项）
    // ----------------------------------------------------------------
    if (Array.isArray(cartItemIds) && cartItemIds.length > 0) {
      const { error: cartError } = await serviceClient
        .from('cart_items')
        .delete()
        .in('id', cartItemIds);

      if (cartError) {
        // 购物车清理失败不影响订单，仅记录警告
        console.warn('Delete cart_items warning:', cartError.message);
      }
    }

    // ----------------------------------------------------------------
    // 8. 返回结果
    // ----------------------------------------------------------------
    return jsonResponse({
      orderId,
      orderNumber,
      itemCount: items.length,
    });

  } catch (err) {
    console.error('create-order-v3 unexpected error:', err);
    return jsonResponse(
      { error: err instanceof Error ? err.message : 'Unknown error' },
      500,
    );
  }
});
