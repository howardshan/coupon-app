import Stripe from 'https://esm.sh/stripe@14?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2?target=deno';

// ============================================================
// V3: 多 deal 购物车直接 charge（automatic capture）
// 入参: { items: [{dealId, unitPrice, promoCode?}], userId }
// ============================================================

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
  apiVersion: '2024-04-10',
  httpClient: Stripe.createFetchHttpClient(),
});

// 使用 service_role client 校验价格，绕过 RLS
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
// 优惠码验证与折扣计算
// 返回 null 表示优惠码无效（直接返回 error 前已校验）
// ============================================================
interface PromoResult {
  discount: number;  // 本 item 折扣金额（美元，保留两位小数）
  error?: string;    // 非空时表示校验失败
}

async function applyPromoCode(
  code: string,
  dealId: string,
  unitPrice: number,
): Promise<PromoResult> {
  const upperCode = code.toUpperCase();

  // 查询优惠码记录
  const { data: promo, error } = await supabase
    .from('promo_codes')
    .select('id, code, discount_type, discount_value, min_order_amount, max_discount, max_uses, current_uses, deal_id, expires_at, is_active')
    .eq('code', upperCode)
    .single();

  if (error || !promo) {
    return { discount: 0, error: `Promo code "${code}" not found` };
  }

  // 校验启用状态
  if (!promo.is_active) {
    return { discount: 0, error: `Promo code "${code}" is inactive` };
  }

  // 校验过期
  if (promo.expires_at && new Date(promo.expires_at) < new Date()) {
    return { discount: 0, error: `Promo code "${code}" has expired` };
  }

  // 校验使用次数
  if (promo.max_uses !== null && promo.current_uses >= promo.max_uses) {
    return { discount: 0, error: `Promo code "${code}" has reached its usage limit` };
  }

  // 校验适用 deal（null 表示全平台通用）
  if (promo.deal_id !== null && promo.deal_id !== dealId) {
    return { discount: 0, error: `Promo code "${code}" is not applicable to this deal` };
  }

  // 校验最低消费门槛（针对单 item）
  if (unitPrice < parseFloat(promo.min_order_amount)) {
    return {
      discount: 0,
      error: `Promo code "${code}" requires a minimum amount of $${promo.min_order_amount}`,
    };
  }

  // 计算折扣金额
  let discount = 0;
  if (promo.discount_type === 'percentage') {
    discount = unitPrice * (parseFloat(promo.discount_value) / 100);
    // 应用 max_discount 上限
    if (promo.max_discount !== null) {
      discount = Math.min(discount, parseFloat(promo.max_discount));
    }
  } else {
    // fixed 类型
    discount = parseFloat(promo.discount_value);
  }

  // 折扣不能超过 item 本身价格
  discount = Math.min(discount, unitPrice);
  discount = Math.round(discount * 100) / 100;

  return { discount };
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
    const body = await req.json();
    const { items, userId, paymentMethod, storeCreditUsed } = body;
    // paymentMethod: 'card' | 'google' | 'apple'
    // storeCreditUsed: Store Credit 抵扣金额（可选，默认 0）
    const creditUsed = Number(storeCreditUsed ?? 0);

    // ---------- 基础参数校验 ----------
    if (!userId) {
      return errorResponse('userId is required');
    }

    if (!Array.isArray(items) || items.length === 0) {
      return errorResponse('items must be a non-empty array');
    }

    // 校验每个 item 的必填字段
    for (let i = 0; i < items.length; i++) {
      const item = items[i];
      if (!item.dealId) {
        return errorResponse(`items[${i}].dealId is required`);
      }
      if (typeof item.unitPrice !== 'number' || item.unitPrice <= 0) {
        return errorResponse(`items[${i}].unitPrice must be a positive number`);
      }
    }

    // ---------- 获取或创建 Stripe Customer ----------
    // 查询用户信息（email、name、已有的 stripe_customer_id）
    const { data: userData, error: userError } = await supabase
      .from('users')
      .select('stripe_customer_id, email, full_name')
      .eq('id', userId)
      .single();

    if (userError) {
      console.error('查询用户信息失败:', userError);
      return errorResponse('Failed to fetch user info', 500);
    }

    let stripeCustomerId: string | null = userData?.stripe_customer_id ?? null;

    if (!stripeCustomerId) {
      // 首次支付：在 Stripe 创建 Customer 并保存到 DB
      const customer = await stripe.customers.create({
        email: userData?.email ?? undefined,
        name: userData?.full_name ?? undefined,
        metadata: { user_id: userId },
      });
      stripeCustomerId = customer.id;

      // 写回 users 表（service_role 绕过 RLS）
      const { error: updateError } = await supabase
        .from('users')
        .update({ stripe_customer_id: stripeCustomerId })
        .eq('id', userId);

      if (updateError) {
        // 写入失败不阻断支付，只记录日志
        console.error('保存 stripe_customer_id 失败:', updateError);
      }
    }

    // ---------- 从 DB 校验每个 deal 的实际价格（防篡改） ----------
    const dealIds = [...new Set(items.map((it: { dealId: string }) => it.dealId))];

    const { data: deals, error: dealsError } = await supabase
      .from('deals')
      .select('id, discount_price, is_active, expires_at, max_per_account, merchant_id')
      .in('id', dealIds);

    if (dealsError) {
      console.error('查询 deals 失败:', dealsError);
      return errorResponse('Failed to validate deals', 500);
    }

    // 构建 dealId → deal 映射（含 max_per_account、merchant_id 字段）
    const dealMap = new Map<string, { discount_price: number; is_active: boolean; expires_at: string; max_per_account: number | null; merchant_id: string }>();
    for (const deal of (deals ?? [])) {
      dealMap.set(deal.id, deal);
    }

    // 逐一校验价格
    for (let i = 0; i < items.length; i++) {
      const item = items[i];
      const deal = dealMap.get(item.dealId);

      if (!deal) {
        return errorResponse(`Deal ${item.dealId} not found`);
      }
      if (!deal.is_active) {
        return errorResponse(`Deal ${item.dealId} is no longer active`);
      }
      if (new Date(deal.expires_at) < new Date()) {
        return errorResponse(`Deal ${item.dealId} has expired`);
      }

      // 价格防篡改校验：客户端传入价格必须与 DB 一致（允许 $0.01 误差）
      const dbPrice = parseFloat(String(deal.discount_price));
      if (Math.abs(item.unitPrice - dbPrice) > 0.01) {
        return errorResponse(
          `Price mismatch for deal ${item.dealId}: expected $${dbPrice.toFixed(2)}, got $${item.unitPrice.toFixed(2)}`,
        );
      }
    }

    // ---------- 限购校验：查该用户已购买数量 ----------
    // 先获取该用户的所有 order_id（非退款完成的订单）
    const { data: userOrders, error: ordersError } = await supabase
      .from('orders')
      .select('id')
      .eq('user_id', userId);

    if (ordersError) {
      console.error('查询用户订单失败:', ordersError);
      return errorResponse('Failed to check purchase limits', 500);
    }

    const userOrderIds = (userOrders ?? []).map((o: { id: string }) => o.id);

    // 对每个 distinct deal 校验限购
    for (const dealId of dealIds) {
      const dealData = dealMap.get(dealId);
      if (!dealData) continue;

      const maxPerAccount = dealData.max_per_account ?? -1;
      // -1 或 0 表示无限制
      if (maxPerAccount <= 0) continue;

      // 查该用户针对此 deal 的已购（非退款成功）order_items 数量
      let purchasedCount = 0;
      if (userOrderIds.length > 0) {
        const { count, error: countError } = await supabase
          .from('order_items')
          .select('id', { count: 'exact', head: true })
          .eq('deal_id', dealId)
          .in('order_id', userOrderIds)
          .neq('customer_status', 'refund_success');

        if (countError) {
          console.error(`查询 deal ${dealId} 购买数量失败:`, countError);
          return errorResponse('Failed to check purchase limits', 500);
        }
        purchasedCount = count ?? 0;
      }

      // 本次请求中该 deal 的购买数量
      const requestedCount = items.filter((i: { dealId: string }) => i.dealId === dealId).length;

      if (purchasedCount + requestedCount > maxPerAccount) {
        return errorResponse(
          `Purchase limit exceeded for this deal: maximum ${maxPerAccount} per account (already purchased ${purchasedCount})`,
        );
      }
    }

    // ---------- 计算 subtotal + serviceFee ----------
    let subtotal = 0;
    for (const item of items) {
      subtotal += item.unitPrice;
    }
    subtotal = Math.round(subtotal * 100) / 100;

    // serviceFee = $0.99 × 券总数量（每张券收一次）
    const totalItemCount = items.length;
    const serviceFee = Math.round(0.99 * totalItemCount * 100) / 100;

    // ---------- 处理优惠码并计算折扣 ----------
    const resultItems: Array<{
      dealId: string;
      unitPrice: number;
      promoDiscount: number;
    }> = [];

    let totalDiscount = 0;

    for (const item of items) {
      let promoDiscount = 0;

      if (item.promoCode) {
        const promoResult = await applyPromoCode(item.promoCode, item.dealId, item.unitPrice);
        if (promoResult.error) {
          return errorResponse(promoResult.error);
        }
        promoDiscount = promoResult.discount;
      }

      totalDiscount += promoDiscount;
      resultItems.push({
        dealId: item.dealId,
        unitPrice: item.unitPrice,
        promoDiscount: Math.round(promoDiscount * 100) / 100,
      });
    }

    totalDiscount = Math.round(totalDiscount * 100) / 100;

    // ---------- 查询税率（基于 merchant 的 metro_area）----------
    // 收集所有涉及的 merchant_id（去重）
    const merchantIds = [...new Set(items.map((it: { dealId: string }) => {
      const d = dealMap.get(it.dealId);
      return d?.merchant_id;
    }).filter(Boolean))] as string[];

    // 查询 merchants 的 metro_area
    const { data: merchantsData } = await supabase
      .from('merchants')
      .select('id, metro_area')
      .in('id', merchantIds);

    // 构建 merchantId → metro_area 映射
    const merchantMetroMap = new Map<string, string>();
    for (const m of (merchantsData ?? [])) {
      if (m.metro_area) merchantMetroMap.set(m.id, m.metro_area);
    }

    // 查询 metro_tax_rates 获取税率
    const metroAreas = [...new Set(Array.from(merchantMetroMap.values()))];
    const taxRateMap = new Map<string, number>();
    if (metroAreas.length > 0) {
      const { data: taxRates } = await supabase
        .from('metro_tax_rates')
        .select('metro_area, tax_rate')
        .in('metro_area', metroAreas)
        .eq('is_active', true);
      for (const tr of (taxRates ?? [])) {
        taxRateMap.set(tr.metro_area, Number(tr.tax_rate));
      }
    }

    // 计算每个 item 的税额，汇总 totalTax
    let totalTax = 0;
    for (const item of items) {
      const deal = dealMap.get(item.dealId);
      const merchantId = deal?.merchant_id;
      const metro = merchantId ? merchantMetroMap.get(merchantId) : null;
      const rate = metro ? (taxRateMap.get(metro) ?? 0) : 0;
      const itemTax = Math.round(item.unitPrice * rate * 100) / 100;
      totalTax += itemTax;
    }
    totalTax = Math.round(totalTax * 100) / 100;

    // ---------- 计算最终收款金额 ----------
    let totalAmount = subtotal + serviceFee + totalTax - totalDiscount - creditUsed;
    totalAmount = Math.round(totalAmount * 100) / 100;

    // Store Credit 全额覆盖：不需要 Stripe 支付
    if (totalAmount <= 0) {
      return new Response(
        JSON.stringify({
          fullyCoveredByCredit: true,
          subtotal,
          serviceFee,
          totalDiscount,
          totalTax,
          storeCreditUsed: creditUsed,
          totalAmount: 0,
          items: resultItems,
          customerId: stripeCustomerId,
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // 防止金额异常（最低 $0.50，Stripe 限制）
    if (totalAmount < 0.5) {
      return errorResponse(`Total amount $${totalAmount.toFixed(2)} is too low (minimum $0.50)`);
    }

    // ---------- 创建 Stripe PaymentIntent（直接 charge） ----------
    // 根据前端选择的支付方式，限定 PaymentIntent 的支付类型
    // 'card' → 只显示信用卡输入（不显示 Link/Google Pay 等）
    // 'google'/'apple' → 使用 automatic_payment_methods（Platform Pay 需要）
    const isCardOnly = paymentMethod === 'card';
    const piParams: Record<string, unknown> = {
      amount: Math.round(totalAmount * 100),  // 转为美分
      currency: 'usd',
      capture_method: 'automatic',             // V3: 直接扣款
      customer: stripeCustomerId ?? undefined, // 关联 Stripe Customer
      metadata: {
        user_id: userId,
        deal_ids: dealIds.join(','),
        item_count: String(items.length),
        total_item_count: String(totalItemCount),
        subtotal: subtotal.toFixed(2),
        service_fee: serviceFee.toFixed(2),
        total_discount: totalDiscount.toFixed(2),
        tax_total: totalTax.toFixed(2),
        total_amount: totalAmount.toFixed(2),
      },
    };
    if (isCardOnly) {
      // 信用卡模式：只允许 card，禁用 Link
      // setup_future_usage 放在 card 级别，不触发 Link 保存选项
      piParams.payment_method_types = ['card'];
      piParams.payment_method_options = {
        card: { setup_future_usage: 'off_session' },
      };
    } else {
      // Google Pay / Apple Pay：启用所有支付方式
      piParams.automatic_payment_methods = { enabled: true };
      piParams.setup_future_usage = 'off_session';
    }
    const paymentIntent = await stripe.paymentIntents.create(piParams as any);

    // ---------- 原子递增所有已使用的优惠码计数 ----------
    // 在 PaymentIntent 创建成功后才递增，避免支付失败导致计数错误
    const usedPromoCodes = new Set<string>();
    for (const item of items) {
      if (item.promoCode && !usedPromoCodes.has(item.promoCode.toUpperCase())) {
        usedPromoCodes.add(item.promoCode.toUpperCase());
        // 调用 DB 原子递增函数（并发安全）
        await supabase.rpc('increment_promo_code_uses', { p_code: item.promoCode.toUpperCase() });
      }
    }

    // 为 PaymentSheet 生成 Ephemeral Key（用于显示已保存卡片 + "Save card" 选项）
    let ephemeralKeySecret: string | null = null;
    if (stripeCustomerId) {
      try {
        const ephemeralKey = await stripe.ephemeralKeys.create(
          { customer: stripeCustomerId },
          { apiVersion: '2023-10-16' },
        );
        ephemeralKeySecret = ephemeralKey.secret ?? null;
      } catch (ekErr) {
        console.error('生成 Ephemeral Key 失败（不阻断支付）:', ekErr);
      }
    }

    return new Response(
      JSON.stringify({
        clientSecret: paymentIntent.client_secret,
        paymentIntentId: paymentIntent.id,
        customerId: stripeCustomerId,
        ephemeralKey: ephemeralKeySecret,
        subtotal,
        serviceFee,
        totalDiscount,
        totalTax,
        storeCreditUsed: creditUsed,
        totalAmount,
        items: resultItems,
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
