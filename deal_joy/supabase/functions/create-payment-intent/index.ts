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
    const { items, userId, paymentMethod, storeCreditUsed, saveCard } = body;
    // paymentMethod: 'card' | 'google' | 'apple'
    // storeCreditUsed: Store Credit 抵扣金额（可选，默认 0）
    // saveCard: 是否保存卡片供下次使用（可选，默认 false）
    const creditUsed = Number(storeCreditUsed ?? 0);
    const shouldSaveCard = saveCard === true;

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

    // 校验 DB 里存的 customer 是否在当前 Stripe 账户下真实存在
    // 切换 Stripe 账户后旧的 cus_xxx 在新账户查不到，会抛 resource_missing，此时自动重建
    if (stripeCustomerId) {
      try {
        const existing = await stripe.customers.retrieve(stripeCustomerId);
        // retrieve 被删除的 customer 时返回 { deleted: true }，也视作无效
        if ((existing as { deleted?: boolean }).deleted) {
          stripeCustomerId = null;
        }
      } catch (err) {
        const code = (err as { code?: string }).code;
        if (code === 'resource_missing') {
          console.log(`Stripe customer ${stripeCustomerId} 在当前账户不存在，重新创建`);
          stripeCustomerId = null;
        } else {
          // 其他错误（网络、权限等）直接抛出
          throw err;
        }
      }
    }

    if (!stripeCustomerId) {
      // 首次支付 / 旧 customer 失效：在 Stripe 创建 Customer 并保存到 DB
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
      .select('id, discount_price, is_active, expires_at, max_per_account, stock_limit, total_sold, merchant_id')
      .in('id', dealIds);

    if (dealsError) {
      console.error('查询 deals 失败:', dealsError);
      return errorResponse('Failed to validate deals', 500);
    }

    // 构建 dealId → deal 映射（含 max_per_account、stock_limit、total_sold、merchant_id 字段）
    const dealMap = new Map<string, { discount_price: number; is_active: boolean; expires_at: string; max_per_account: number | null; stock_limit: number | null; total_sold: number | null; merchant_id: string }>();
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

    // ---------- 总库存校验：COUNT order_items 统计已售份数 ----------
    for (const dealId of dealIds) {
      const dealData = dealMap.get(dealId);
      if (!dealData) continue;

      const stockLimit = dealData.stock_limit ?? -1;
      // -1 或 0 表示不限库存
      if (stockLimit <= 0) continue;

      // 统计已售出且未退款的 order_items（每行 = 1 份 deal，与 RPC get_deal_remaining_stock 逻辑一致）
      // 后端用 service role，无 RLS 限制，可直接 COUNT 全局数据
      const { count: soldCount, error: soldError } = await supabase
        .from('order_items')
        .select('id', { count: 'exact', head: true })
        .eq('deal_id', dealId)
        .not('customer_status', 'eq', 'refund_success');

      if (soldError) {
        console.error(`查询 deal ${dealId} 库存数量失败:`, soldError);
        return errorResponse('Failed to check stock availability', 500);
      }

      const sold = soldCount ?? 0;
      // 本次请求中该 deal 的购买数量
      const requestedCount = items.filter((i: { dealId: string }) => i.dealId === dealId).length;

      if (sold + requestedCount > stockLimit) {
        return errorResponse(
          `Not enough stock for this deal: only ${stockLimit - sold} remaining`,
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

    // 查询 merchants 的 city、metro_area、stripe_account_id、commission_rate
    // city 是税率查询的主字段（通过 city_metro_map 映射到 metro），metro_area 作为 fallback
    const { data: merchantsData } = await supabase
      .from('merchants')
      .select('id, city, metro_area, stripe_account_id, stripe_account_status, commission_rate')
      .in('id', merchantIds);

    // 查询全局 commission_rate（兜底，默认 15%）
    const { data: globalConfig } = await supabase
      .from('platform_commission_config')
      .select('commission_rate')
      .limit(1)
      .single();
    const globalCommissionRate = Number(globalConfig?.commission_rate ?? 0.15);

    // 构建 merchantId → 各字段映射
    const merchantCityMap = new Map<string, string>();                 // 商家所在城市（优先）
    const merchantMetroMap = new Map<string, string>();                // 商家所在 metro（fallback）
    const merchantConnectMap = new Map<string, string | null>();       // stripe_account_id
    const merchantCommissionRateMap = new Map<string, number>();       // 有效 commission_rate
    for (const m of (merchantsData ?? [])) {
      if (m.city) merchantCityMap.set(m.id, m.city);
      if (m.metro_area) merchantMetroMap.set(m.id, m.metro_area);
      merchantConnectMap.set(m.id, m.stripe_account_id ?? null);
      // 商家专属费率优先；NULL 则用全局默认
      merchantCommissionRateMap.set(
        m.id,
        m.commission_rate != null ? Number(m.commission_rate) : globalCommissionRate,
      );
    }

    // 税率查询：city → metro → rate，保持与前端一致
    // 1. 收集所有涉及的 city（去重，lowercase）
    const cities = [...new Set(Array.from(merchantCityMap.values()).map(c => c.toLowerCase()))];
    // 2. 查 city_metro_map 得到 city → metro_area
    const cityToMetro = new Map<string, string>();
    if (cities.length > 0) {
      const { data: cityMap } = await supabase
        .from('city_metro_map')
        .select('city, metro_area');
      for (const row of (cityMap ?? [])) {
        if (row.city && row.metro_area) {
          cityToMetro.set((row.city as string).toLowerCase(), row.metro_area as string);
        }
      }
    }
    // 3. 把没在映射表里命中的 merchant 用它自己的 metro_area 兜底
    for (const [mId, metro] of merchantMetroMap) {
      const c = merchantCityMap.get(mId);
      if (c && !cityToMetro.has(c.toLowerCase())) {
        cityToMetro.set(c.toLowerCase(), metro);
      }
    }
    // 4. 查所有涉及到的 metro 的税率
    const allMetros = [...new Set(Array.from(cityToMetro.values()))];
    for (const mId of merchantIds) {
      const metro = merchantMetroMap.get(mId);
      if (metro && !allMetros.includes(metro)) allMetros.push(metro);
    }
    const taxRateMap = new Map<string, number>();
    if (allMetros.length > 0) {
      const { data: taxRates } = await supabase
        .from('metro_tax_rates')
        .select('metro_area, tax_rate')
        .in('metro_area', allMetros)
        .eq('is_active', true);
      for (const tr of (taxRates ?? [])) {
        taxRateMap.set(tr.metro_area, Number(tr.tax_rate));
      }
    }

    // 计算每个 item 的税额（税基 = unit_price + 分摊的 service fee $0.99，与前端一致）
    // service fee 也要交税，所以每张券的税基 = unit_price + 0.99
    const SERVICE_FEE_PER_ITEM = 0.99;
    let totalTax = 0;
    for (const item of items) {
      const deal = dealMap.get(item.dealId);
      const merchantId = deal?.merchant_id;
      if (!merchantId) continue;
      // 先用 city → metro 查，没有则回落 merchant 自己的 metro_area
      const city = merchantCityMap.get(merchantId);
      const metro = (city ? cityToMetro.get(city.toLowerCase()) : null)
        ?? merchantMetroMap.get(merchantId)
        ?? null;
      const rate = metro ? (taxRateMap.get(metro) ?? 0) : 0;
      const taxableAmount = item.unitPrice + SERVICE_FEE_PER_ITEM;
      const itemTax = Math.round(taxableAmount * rate * 100) / 100;
      totalTax += itemTax;
    }
    totalTax = Math.round(totalTax * 100) / 100;

    // ---------- 计算佣金（commission）----------
    // commission 仅在成功核销时最终归平台；退款/过期时需退还 commission 给商家
    // 计算基数：(unit_price - promoDiscount) × commission_rate（promo 折扣由商家承担）
    let totalCommission = 0;
    for (let i = 0; i < items.length; i++) {
      const d = dealMap.get(items[i].dealId);
      const mId = d?.merchant_id ?? '';
      const rate = merchantCommissionRateMap.get(mId) ?? globalCommissionRate;
      const effectivePrice = items[i].unitPrice - (resultItems[i]?.promoDiscount ?? 0);
      totalCommission += Math.round(effectivePrice * rate * 100) / 100;
    }
    totalCommission = Math.round(totalCommission * 100) / 100;

    // merchant net = 商家最终应收金额（unit_price 合计 - promo 折扣 - commission）
    const merchantNet = Math.round((subtotal - totalDiscount - totalCommission) * 100) / 100;

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

    // ---------- Stripe Connect：分账参数（Agent 定位核心）----------
    // 单商家且已完成 Connect onboarding → merchant net 立即路由到商家 Connect 账户
    // application_fee_amount = service_fee + commission + tax（平台保留）
    // 多商家或商家缺少 Connect 账户 → 降级：资金路由到平台账户，记录警告
    const isSingleMerchant = merchantIds.length === 1;
    const soloMerchantId = isSingleMerchant ? merchantIds[0] : null;
    const soloConnectId = soloMerchantId ? (merchantConnectMap.get(soloMerchantId) ?? null) : null;

    // Stripe 手续费估算（Destination Charges 模式下从 application_fee_amount 扣）
    // 标准费率：2.9% + $0.30/笔（美国卡）
    // 包含到 application_fee_amount 里，让 Stripe 手续费由商家净额吸收，
    // 确保平台实际到手 = service_fee + commission + tax 不打折
    const stripeFeeEstimate = Math.round((totalAmount * 0.029 + 0.30) * 100) / 100;

    // application_fee_amount（美分）= 平台保留金额 + Stripe 手续费
    const platformFeeTotal = serviceFee + totalCommission + totalTax + stripeFeeEstimate;
    const applicationFeeAmountCents = Math.min(
      Math.round(platformFeeTotal * 100),
      Math.round(totalAmount * 100),
    );

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
        commission_total: totalCommission.toFixed(2),
        merchant_net: merchantNet.toFixed(2),
        has_connect_routing: String(isSingleMerchant && !!soloConnectId),
      },
    };

    // 添加 Stripe Connect 分账参数（Agent 定位）
    // 混合支付（Store Credit + 刷卡）时不用 Destination Charges：
    //   application_fee 基于全单算，可能 > Stripe 实际收款 → 商家 transfer = 0
    //   改为：Stripe 收款全部进平台，下单后由 create-order-v3 手动 Transfer 给商家
    const hasMixedPayment = creditUsed > 0 && totalAmount > 0;
    if (isSingleMerchant && soloConnectId && !hasMixedPayment) {
      // 纯刷卡：标准 Destination Charges 路径
      piParams.application_fee_amount = applicationFeeAmountCents;
      piParams.transfer_data = { destination: soloConnectId };
    } else if (isSingleMerchant && soloConnectId && hasMixedPayment) {
      // 混合支付：不设 application_fee，资金先进平台，create-order-v3 手动 Transfer
      console.log(`[混合支付] credit=$${creditUsed} card=$${totalAmount} → 跳过 Destination Charges，由 create-order-v3 手动 Transfer`);
    } else if (!isSingleMerchant) {
      // 多商家购物车暂不支持单次 Connect 分账，需要前端拆单
      // TODO: 后续实现拆单支付（每商家一笔 PaymentIntent）以维持 Agent 定位
      console.warn(`多商家购物车 (${merchantIds.join(',')})：暂时路由到平台账户，建议前端拆单`);
    } else {
      // 商家缺少 Connect 账户：提示完成注册（上架 deal 前应已完成）
      console.warn(`商家 ${soloMerchantId} 缺少 Stripe Connect 账户，资金暂时路由到平台账户`);
    }
    if (isCardOnly) {
      // 信用卡模式：只允许 card，禁用 Link
      piParams.payment_method_types = ['card'];
      // 使用已保存卡时要求重新输入 CVV（安全校验）
      // 同时支持保存卡片供下次使用
      piParams.payment_method_options = {
        card: {
          require_cvc_recollection: true,
          ...(shouldSaveCard ? { setup_future_usage: 'off_session' } : {}),
        },
      };
    } else {
      // Google Pay / Apple Pay：启用所有支付方式
      piParams.automatic_payment_methods = { enabled: true };
      if (shouldSaveCard) {
        piParams.setup_future_usage = 'off_session';
      }
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
        commissionTotal: totalCommission,
        merchantNet,
        hasConnectRouting: isSingleMerchant && !!soloConnectId,
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
