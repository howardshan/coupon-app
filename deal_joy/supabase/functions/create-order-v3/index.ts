import Stripe from 'https://esm.sh/stripe@14?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { sendEmail } from '../_shared/email.ts';
import { buildC2Email } from '../_shared/email-templates/customer/order-confirmation.ts';
import { buildM5Email } from '../_shared/email-templates/merchant/new-order.ts';

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

// ─── Stripe Reserves API 辅助函数 ────────────────────────────────────────────

/**
 * 在 connected account 上创建 ReserveHold
 * 冻结 merchant_net，防止商家在核销前提现
 * release_after = 180 天（兜底；实际在核销/退款时提前释放）
 */
async function createReserveHold(
  connectedAccountId: string,
  amountCents: number,
  stripeKey: string,
): Promise<string | null> {
  const releaseAfter = Math.floor(Date.now() / 1000) + 180 * 24 * 3600;
  const body = new URLSearchParams({
    amount: String(amountCents),
    currency: 'usd',
    'release_schedule[release_after]': String(releaseAfter),
  });
  try {
    const res = await fetch('https://api.stripe.com/v1/reserve/holds', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${stripeKey}`,
        'Stripe-Version': '2025-12-15.preview',
        'Stripe-Account': connectedAccountId,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: body.toString(),
    });
    if (!res.ok) {
      const errText = await res.text();
      console.error(`[ReserveHold] 创建失败 acct=${connectedAccountId} amount=${amountCents}:`, errText);
      return null;
    }
    const data = await res.json();
    return (data as { id?: string }).id ?? null;
  } catch (err) {
    console.error(`[ReserveHold] 网络异常 acct=${connectedAccountId}:`, err);
    return null;
  }
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
      totalTax,        // 新增：整单税费合计
      cartItemIds,
      storeCreditUsed,
      skipStripeVerification,
    } = body;
    const creditUsed = Number(storeCreditUsed ?? 0);

    if (!paymentIntentId) {
      return jsonResponse({ error: 'paymentIntentId is required' }, 400);
    }
    if (!userId) {
      return jsonResponse({ error: 'userId is required' }, 400);
    }
    if (!Array.isArray(items) || items.length === 0) {
      return jsonResponse({ error: 'items must be a non-empty array' }, 400);
    }
    // Store Credit 全额覆盖时 totalAmount 可以为 0
    if (typeof totalAmount !== 'number' || totalAmount < 0) {
      return jsonResponse({ error: 'totalAmount must not be negative' }, 400);
    }

    // 防止越权：JWT 用户必须与传入 userId 一致
    if (user.id !== userId) {
      return jsonResponse({ error: 'Forbidden: userId mismatch' }, 403);
    }

    // ----------------------------------------------------------------
    // 3. 验证 PaymentIntent 状态（Store Credit 全额覆盖时跳过）
    // ----------------------------------------------------------------
    let paymentIntent;
    if (skipStripeVerification) {
      // Store Credit 全额覆盖，无 Stripe 支付
      console.log(`[create-order-v3] Store Credit 全额覆盖, creditUsed=${creditUsed}, 跳过 Stripe 验证`);
      paymentIntent = { amount: 0, status: 'store_credit' };
    } else {
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
    }

    // 额外校验：PaymentIntent 金额需与请求体一致（跳过 Store Credit 全额覆盖的情况）
    const expectedAmountCents = Math.round(totalAmount * 100);
    if (!skipStripeVerification && paymentIntent.amount !== expectedAmountCents) {
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
        // total_amount 存原始总金额（未扣 Store Credit），方便对账
        total_amount: (subtotal ?? 0) + (serviceFeeTotal ?? 0) + (totalTax ?? 0) - (totalDiscount ?? 0),
        tax_amount: totalTax ?? 0,     // 整单税费
        // 全额 Store Credit 时：creditUsed 可能为 0（前端 bug），用 total_amount 补填
        store_credit_used: creditUsed > 0
          ? creditUsed
          : (skipStripeVerification ? (subtotal ?? 0) + (serviceFeeTotal ?? 0) + (totalTax ?? 0) - (totalDiscount ?? 0) : 0),
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
    //    税费由服务端根据 deal → merchant.metro_area 重算并快照到 order_items
    //    （防止前端伪造，也保证 tax_metro_area 与 tax_amount 一致）
    // ----------------------------------------------------------------

    // 查询 deals → merchant_id
    const dealIdList = [...new Set(items.map((it: { dealId: string }) => it.dealId))] as string[];
    const { data: dealRows } = await serviceClient
      .from('deals')
      .select('id, merchant_id')
      .in('id', dealIdList);
    const dealMerchantMap = new Map<string, string>(
      (dealRows ?? []).map((d: { id: string; merchant_id: string }) => [d.id, d.merchant_id]),
    );

    // 查询 merchants → metro_area + commission_rate
    const merchantIdList = [...new Set(Array.from(dealMerchantMap.values()))];
    const { data: merchantRows } = await serviceClient
      .from('merchants')
      .select('id, metro_area, commission_rate')
      .in('id', merchantIdList);
    const merchantMetroMap = new Map<string, string | null>(
      (merchantRows ?? []).map((m: { id: string; metro_area: string | null; commission_rate: number | null }) => [m.id, m.metro_area]),
    );

    // 查询全局 commission_rate（兜底，默认 15%）
    const { data: globalCfg } = await serviceClient
      .from('platform_commission_config')
      .select('commission_rate')
      .limit(1)
      .single();
    const globalCommRate = Number(globalCfg?.commission_rate ?? 0.15);

    // 构建 merchantId → commission_rate 映射（商家专属优先，NULL 时用全局默认）
    const merchantCommRateMap = new Map<string, number>(
      (merchantRows ?? []).map((m: { id: string; commission_rate: number | null }) => [
        m.id,
        m.commission_rate != null ? Number(m.commission_rate) : globalCommRate,
      ]),
    );

    // 查询 metro_tax_rates → rate
    const metroAreaList = [...new Set(
      Array.from(merchantMetroMap.values()).filter((v): v is string => !!v),
    )];
    const metroRateMap = new Map<string, number>();
    if (metroAreaList.length > 0) {
      const { data: taxRows } = await serviceClient
        .from('metro_tax_rates')
        .select('metro_area, tax_rate')
        .in('metro_area', metroAreaList)
        .eq('is_active', true);
      for (const row of (taxRows ?? []) as Array<{ metro_area: string; tax_rate: number }>) {
        metroRateMap.set(row.metro_area, Number(row.tax_rate));
      }
    }

    const orderItemsPayload = items.map((item: {
      dealId: string;
      unitPrice: number;
      promoDiscount?: number;
      selectedOptions: unknown;
      purchasedMerchantId: string;
    }) => {
      const merchantId = dealMerchantMap.get(item.dealId) ?? null;
      const metroArea = merchantId ? merchantMetroMap.get(merchantId) ?? null : null;
      const taxRate = metroArea ? metroRateMap.get(metroArea) ?? 0 : 0;
      const itemTaxAmount = Math.round(item.unitPrice * taxRate * 100) / 100;

      // 快照 commission_amount：基于 (unit_price - promoDiscount) × commission_rate
      // 仅成功核销后最终归平台；退款/过期时退还
      const commRate = merchantId ? (merchantCommRateMap.get(merchantId) ?? globalCommRate) : globalCommRate;
      const effectivePrice = item.unitPrice - (Number(item.promoDiscount ?? 0));
      const commissionAmount = Math.round(effectivePrice * commRate * 100) / 100;

      return {
        order_id: orderId,
        deal_id: item.dealId,
        unit_price: item.unitPrice,
        service_fee: SERVICE_FEE_PER_COUPON,
        tax_amount: itemTaxAmount,
        tax_rate: taxRate,
        tax_metro_area: metroArea,       // 快照下单时的税归属地，防止 merchant.metro_area 后续变更
        commission_amount: commissionAmount, // 快照佣金金额，用于退款精确计算
        purchased_merchant_id: item.purchasedMerchantId ?? null,
        selected_options: item.selectedOptions ?? null,
        customer_status: 'unused',
        merchant_status: 'unused',
      };
    });

    const { data: insertedItems, error: itemsError } = await serviceClient
      .from('order_items')
      .insert(orderItemsPayload)
      .select('id, unit_price, commission_amount, purchased_merchant_id');

    if (itemsError) {
      console.error('Insert order_items error:', itemsError);
      // 回滚：删除刚创建的 order（触发级联删除 order_items）
      await serviceClient.from('orders').delete().eq('id', orderId);
      return jsonResponse({ error: `Failed to create order items: ${itemsError.message}` }, 500);
    }

    // ----------------------------------------------------------------
    // 6.5. 为每个 order_item 在 merchant Connect 账户创建 ReserveHold
    //      冻结 merchant_net（Path A 硬性 Reserve）
    //      失败不阻断订单流程（支付已成功），仅记录错误日志
    // ----------------------------------------------------------------
    const stripeKeyForReserve = Deno.env.get('STRIPE_SECRET_KEY') ?? '';
    if (insertedItems && insertedItems.length > 0 && stripeKeyForReserve) {
      // 批量查询各商家的 stripe_account_id
      const merchantIdsForReserve = [
        ...new Set(
          (insertedItems as any[])
            .map((i: { purchased_merchant_id?: string | null }) => i.purchased_merchant_id)
            .filter((id): id is string => !!id),
        ),
      ];

      let reserveMerchantConnectMap = new Map<string, string | null>();
      if (merchantIdsForReserve.length > 0) {
        const { data: merchantConnectRows } = await serviceClient
          .from('merchants')
          .select('id, stripe_account_id, stripe_account_status')
          .in('id', merchantIdsForReserve);

        reserveMerchantConnectMap = new Map(
          (merchantConnectRows ?? []).map((m: { id: string; stripe_account_id?: string | null; stripe_account_status?: string | null }) => [
            m.id,
            m.stripe_account_status === 'connected' ? (m.stripe_account_id ?? null) : null,
          ]),
        );
      }

      // 为每个 item 创建 ReserveHold（并行，不阻断主流程）
      const reserveResults = await Promise.allSettled(
        (insertedItems as any[]).map(async (dbItem: { id: string; unit_price: number; commission_amount: number; purchased_merchant_id?: string | null }, idx: number) => {
          const connectId = dbItem.purchased_merchant_id
            ? reserveMerchantConnectMap.get(dbItem.purchased_merchant_id)
            : null;
          if (!connectId) return; // 商家无 Connect 账户，跳过

          // merchant_net = unit_price - promoDiscount - commission_amount
          const originalItem = items[idx] as { promoDiscount?: number };
          const merchantNetCents = Math.round(
            (dbItem.unit_price - (Number(originalItem?.promoDiscount ?? 0)) - dbItem.commission_amount) * 100,
          );
          if (merchantNetCents <= 0) return;

          const holdId = await createReserveHold(connectId, merchantNetCents, stripeKeyForReserve);
          if (holdId) {
            const { error: holdUpdateErr } = await serviceClient
              .from('order_items')
              .update({ stripe_reserve_hold_id: holdId })
              .eq('id', dbItem.id);
            if (holdUpdateErr) {
              console.error(`[ReserveHold] 写入 order_items 失败 item=${dbItem.id}:`, holdUpdateErr);
            } else {
              console.log(`[ReserveHold] 创建成功 item=${dbItem.id} hold=${holdId} net=${merchantNetCents / 100}`);
            }
          }
        }),
      );

      // 记录失败情况（不阻断）
      reserveResults.forEach((r, i) => {
        if (r.status === 'rejected') {
          console.error(`[ReserveHold] item[${i}] 异常:`, r.reason);
        }
      });
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
    // 7.5. 扣减 Store Credit（如果使用了）
    // ----------------------------------------------------------------
    console.log(`[create-order-v3] creditUsed=${creditUsed}, storeCreditUsed=${storeCreditUsed}`);
    if (creditUsed > 0) {
      const { error: creditErr } = await serviceClient.rpc('add_store_credit', {
        p_user_id: userId,
        p_amount: -creditUsed,  // 负数 = 扣减
        p_order_item_id: null,
        p_description: `Purchase deduction for order ${orderNumber}`,
      });
      if (creditErr) {
        console.error('扣减 Store Credit 失败（不阻断订单）:', creditErr.message);
      }
    }

    // ----------------------------------------------------------------
    // 8. 发送订单确认邮件（即发即忘，不阻断核心流程）
    // C2 → 客户；M5 → 每个涉及的商家各一封
    // ----------------------------------------------------------------
    // 邮件发送（真正的即发即忘，不 await，不阻断下单响应）
    (async () => {
      try {
        const { data: userInfo } = await serviceClient
          .from('users')
          .select('email')
          .eq('id', userId)
          .single();

        const dealIds = [...new Set(items.map((i: { dealId: string }) => i.dealId))];
        const { data: dealRows } = await serviceClient
          .from('deals')
          .select('id, title, merchant_id')
          .in('id', dealIds);
        const dealMap = new Map((dealRows ?? []).map((d: { id: string; title: string; merchant_id: string }) => [d.id, d]));

        const emailPromises: Promise<void>[] = [];

        // C2：订单确认邮件 → 发给客户
        if (userInfo?.email) {
          // 按 dealId + unitPrice 分组合并，相同 deal 显示为一行（含数量）
          const c2GroupMap = new Map<string, { dealTitle: string; unitPrice: number; quantity: number }>();
          for (const item of items as Array<{ dealId: string; unitPrice: number }>) {
            const key = `${item.dealId}__${item.unitPrice}`;
            const title = (dealMap.get(item.dealId) as { title: string } | undefined)?.title ?? 'Deal';
            if (c2GroupMap.has(key)) {
              c2GroupMap.get(key)!.quantity += 1;
            } else {
              c2GroupMap.set(key, { dealTitle: title, unitPrice: item.unitPrice, quantity: 1 });
            }
          }
          const c2Items = Array.from(c2GroupMap.values());
          const c2ServiceFee = SERVICE_FEE_PER_COUPON * items.length;
          const c2OrderTotal = (subtotal ?? 0) + c2ServiceFee;
          const { subject: c2Subject, html: c2Html } = buildC2Email({
            customerEmail:   userInfo.email,
            orderNumber,
            items:           c2Items,
            subtotal:        subtotal ?? 0,
            serviceFee:      c2ServiceFee,
            totalAmount,                    // Stripe 实际扣款（可能为 0）
            storeCreditUsed: creditUsed > 0 ? creditUsed : undefined,
            orderTotal:      c2OrderTotal,  // 展示用总额
            fullyPaidByCredit: totalAmount <= 0, // 只有真正全额覆盖才显示该文案
          });
          emailPromises.push(sendEmail(serviceClient, {
            to:            userInfo.email,
            subject:       c2Subject,
            htmlBody:      c2Html,
            emailCode:     'C2',
            referenceId:   orderId,
            recipientType: 'customer',
            userId,
          }));
        }

        // M5：新订单通知 → 按 purchasedMerchantId 分组，每家各发一封
        // 同一商家内再按 dealId + unitPrice 合并，相同 deal 显示为一行
        const merchantItemsMap = new Map<string, Map<string, { dealTitle: string; quantity: number; unitPrice: number }>>();
        for (const item of items as Array<{ dealId: string; unitPrice: number; purchasedMerchantId?: string }>) {
          const deal = dealMap.get(item.dealId) as { merchant_id: string; title: string } | undefined;
          const mid  = item.purchasedMerchantId ?? deal?.merchant_id;
          if (!mid) continue;
          if (!merchantItemsMap.has(mid)) merchantItemsMap.set(mid, new Map());
          const dealKey = `${item.dealId}__${item.unitPrice}`;
          const merchantDeals = merchantItemsMap.get(mid)!;
          if (merchantDeals.has(dealKey)) {
            merchantDeals.get(dealKey)!.quantity += 1;
          } else {
            merchantDeals.set(dealKey, {
              dealTitle: deal?.title ?? 'Deal',
              quantity:  1,
              unitPrice: item.unitPrice,
            });
          }
        }

        for (const [merchantId, merchantDealsMap] of merchantItemsMap.entries()) {
          const { data: merchantRow } = await serviceClient
            .from('merchants')
            .select('name, user_id')
            .eq('id', merchantId)
            .single();
          if (!merchantRow?.user_id) continue;

          const { data: merchantUser } = await serviceClient
            .from('users')
            .select('email')
            .eq('id', merchantRow.user_id)
            .single();
          if (!merchantUser?.email) continue;

          const merchantItems = Array.from(merchantDealsMap.values());
          const merchantTotal = merchantItems.reduce((sum, i) => sum + i.unitPrice * i.quantity, 0);
          const { subject: m5Subject, html: m5Html } = buildM5Email({
            merchantName: merchantRow.name,
            orderNumber,
            items:        merchantItems,
            totalAmount:  merchantTotal,
          });
          emailPromises.push(sendEmail(serviceClient, {
            to:            merchantUser.email,
            subject:       m5Subject,
            htmlBody:      m5Html,
            emailCode:     'M5',
            referenceId:   orderId,
            recipientType: 'merchant',
            merchantId,
          }));
        }

        await Promise.allSettled(emailPromises);
      } catch (emailErr) {
        console.error('[create-order-v3] email error:', emailErr);
      }
    })();

    // ----------------------------------------------------------------
    // 9. 返回结果
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
