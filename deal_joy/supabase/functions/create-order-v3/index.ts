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
        'Stripe-Version': '2025-08-27.preview',
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

    // 查询 merchants → city + metro_area + commission_rate
    const merchantIdList = [...new Set(Array.from(dealMerchantMap.values()))];
    const { data: merchantRows } = await serviceClient
      .from('merchants')
      .select('id, city, metro_area, commission_rate')
      .in('id', merchantIdList);
    const merchantCityMap = new Map<string, string | null>(
      (merchantRows ?? []).map((m: { id: string; city: string | null }) => [m.id, m.city]),
    );
    const merchantMetroMap = new Map<string, string | null>(
      (merchantRows ?? []).map((m: { id: string; metro_area: string | null }) => [m.id, m.metro_area]),
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

    // 查询 city_metro_map → city → metro
    const cityList = [...new Set(
      Array.from(merchantCityMap.values())
        .filter((v): v is string => !!v)
        .map(c => c.toLowerCase()),
    )];
    const cityToMetro = new Map<string, string>();
    if (cityList.length > 0) {
      const { data: cityMapRows } = await serviceClient
        .from('city_metro_map')
        .select('city, metro_area');
      for (const row of (cityMapRows ?? []) as Array<{ city: string; metro_area: string }>) {
        if (row.city && row.metro_area) {
          cityToMetro.set(row.city.toLowerCase(), row.metro_area);
        }
      }
    }

    // 每个 merchant 解析出最终的 metro_area（优先 city→metro，fallback 到 merchant.metro_area）
    const merchantResolvedMetro = new Map<string, string | null>();
    for (const mId of merchantIdList) {
      const city = merchantCityMap.get(mId);
      const fromMap = city ? cityToMetro.get(city.toLowerCase()) : undefined;
      const fallback = merchantMetroMap.get(mId) ?? null;
      merchantResolvedMetro.set(mId, fromMap ?? fallback);
    }

    // 查询 metro_tax_rates → rate
    const metroAreaList = [...new Set(
      Array.from(merchantResolvedMetro.values()).filter((v): v is string => !!v),
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
      const metroArea = merchantId ? merchantResolvedMetro.get(merchantId) ?? null : null;
      const taxRate = metroArea ? metroRateMap.get(metroArea) ?? 0 : 0;
      // 税基 = unit_price + service_fee（与前端 + create-payment-intent 一致）
      const taxableAmount = item.unitPrice + SERVICE_FEE_PER_COUPON;
      const itemTaxAmount = Math.round(taxableAmount * taxRate * 100) / 100;

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
        promo_discount: Number(item.promoDiscount ?? 0),  // 快照促销折扣，用于退款时精确计算 merchant_net
        purchased_merchant_id: item.purchasedMerchantId ?? null,
        selected_options: item.selectedOptions ?? null,
        customer_status: 'unused',
        merchant_status: 'unused',
      };
    });

    const { data: insertedItems, error: itemsError } = await serviceClient
      .from('order_items')
      .insert(orderItemsPayload)
      .select('id, unit_price, commission_amount, promo_discount, purchased_merchant_id');

    if (itemsError) {
      console.error('Insert order_items error:', itemsError);
      // 回滚：删除刚创建的 order（触发级联删除 order_items）
      await serviceClient.from('orders').delete().eq('id', orderId);
      return jsonResponse({ error: `Failed to create order items: ${itemsError.message}` }, 500);
    }

    // ----------------------------------------------------------------
    // 6.5. Stripe Connect 分账 + ReserveHold
    //   A. 多商家订单：通过 Transfer API 手动将 merchant_net 路由到各商家 Connect 账户
    //      （单商家时 PI 已含 transfer_data，无需重复操作）
    //   B. ReserveHold：冻结 merchant_net，防止核销前提现
    //      STRIPE_RESERVES_ENABLED=false 时跳过（降级到软性检查）
    //      失败时回滚订单并退款（硬性保障）
    // ----------------------------------------------------------------
    const stripeKey = Deno.env.get('STRIPE_SECRET_KEY') ?? '';
    const reservesEnabled = Deno.env.get('STRIPE_RESERVES_ENABLED') !== 'false';

    if (insertedItems && insertedItems.length > 0 && stripeKey) {
      // 查询各商家的 Stripe Connect 账户信息
      const merchantIdsForReserve = [
        ...new Set(
          (insertedItems as any[])
            .map((i: any) => i.purchased_merchant_id as string | null)
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
          (merchantConnectRows ?? []).map((m: any) => [
            m.id,
            m.stripe_account_status === 'connected' ? (m.stripe_account_id ?? null) : null,
          ]),
        );
      }

      // ── A. 多商家手动分账（PI 无 transfer_data，需 Transfer API 路由资金）──
      // successfulTransfers: connectId → transferId（用于回滚时 reversal）
      const successfulTransfers = new Map<string, string>();
      // transferFailedConnectIds: 分账失败的商家（Hold 将跳过，避免触发不必要的回滚）
      const transferFailedConnectIds = new Set<string>();

      if (merchantIdsForReserve.length > 1 && !skipStripeVerification) {
        const chargeId = typeof (paymentIntent as any).latest_charge === 'string'
          ? (paymentIntent as any).latest_charge as string
          : null;

        if (chargeId) {
          // 按 Connect 账户汇总 merchant_net
          const merchantNetMap = new Map<string, number>();
          for (const dbItem of (insertedItems as any[])) {
            const mid = dbItem.purchased_merchant_id as string | null;
            const connectId = mid ? reserveMerchantConnectMap.get(mid) : null;
            if (!mid || !connectId) continue;
            const net = Math.round(
              (dbItem.unit_price - (dbItem.promo_discount ?? 0) - dbItem.commission_amount) * 100,
            );
            if (net > 0) merchantNetMap.set(connectId, (merchantNetMap.get(connectId) ?? 0) + net);
          }

          // 从 merchant net 里按比例扣除 Stripe 手续费（2.9% + $0.30/笔）
          // 确保平台净收 = service_fee + commission + tax 不被 Stripe 吃掉
          const totalAmountCents = Math.round((totalAmount ?? 0) * 100);
          const stripeFeeCents = Math.round(totalAmountCents * 0.029 + 30);
          const totalNetCents = Array.from(merchantNetMap.values()).reduce((s, v) => s + v, 0);
          if (totalNetCents > 0 && stripeFeeCents > 0) {
            for (const [cid, netCents] of merchantNetMap) {
              // 按 merchant_net 占比分摊 Stripe 费
              const share = Math.round(stripeFeeCents * (netCents / totalNetCents));
              merchantNetMap.set(cid, Math.max(0, netCents - share));
            }
          }

          for (const [connectId, amountCents] of merchantNetMap) {
            try {
              const transferRes = await fetch('https://api.stripe.com/v1/transfers', {
                method: 'POST',
                headers: {
                  Authorization: `Bearer ${stripeKey}`,
                  'Content-Type': 'application/x-www-form-urlencoded',
                },
                body: new URLSearchParams({
                  amount: String(amountCents),
                  currency: 'usd',
                  destination: connectId,
                  source_transaction: chargeId,
                  transfer_group: orderId,
                }).toString(),
              });
              if (!transferRes.ok) {
                console.error(`[Transfer] 分账失败 dest=${connectId} amount=${amountCents}:`, await transferRes.text());
                transferFailedConnectIds.add(connectId); // 标记失败，后续跳过 Hold
              } else {
                const transferData = await transferRes.json();
                successfulTransfers.set(connectId, (transferData as any).id);
                console.log(`[Transfer] 分账成功 dest=${connectId} transfer=${(transferData as any).id}`);
              }
            } catch (err) {
              console.error(`[Transfer] 网络异常 dest=${connectId}:`, err);
              transferFailedConnectIds.add(connectId);
            }
          }

          if (transferFailedConnectIds.size > 0) {
            console.error(`[Transfer] 以下商家分账失败，需人工补 Transfer: ${[...transferFailedConnectIds].join(',')}`);
          }
        } else {
          console.warn('[Transfer] 多商家订单无法获取 chargeId，跳过分账（需人工处理）');
        }
      }

      // ── B. ReserveHold（STRIPE_RESERVES_ENABLED=true 时强制，失败则回滚）──
      if (reservesEnabled) {
        const holdFailures: string[] = [];
        // createdHolds：已成功创建的 Hold，回滚时需要释放（Fix 2）
        const createdHolds: Array<{ connectId: string; holdId: string }> = [];

        await Promise.allSettled(
          (insertedItems as any[]).map(async (dbItem: any) => {
            const connectId = dbItem.purchased_merchant_id
              ? reserveMerchantConnectMap.get(dbItem.purchased_merchant_id)
              : null;
            if (!connectId) return; // 商家无 Connect 账户，跳过（非失败）

            // Fix 5：Transfer 失败的商家跳过 Hold（资金未在 Connect 账户）
            if (transferFailedConnectIds.has(connectId)) {
              console.warn(`[ReserveHold] 跳过 item=${dbItem.id}（Transfer 失败，资金未到 Connect）`);
              return;
            }

            const merchantNetCents = Math.round(
              (dbItem.unit_price - (dbItem.promo_discount ?? 0) - dbItem.commission_amount) * 100,
            );
            if (merchantNetCents <= 0) return;

            const holdId = await createReserveHold(connectId, merchantNetCents, stripeKey);
            if (!holdId) {
              holdFailures.push(dbItem.id);
              return;
            }

            // Fix 2：先记录已创建的 Hold，再写库；无论写库是否成功都能在回滚时清理
            createdHolds.push({ connectId, holdId });

            const { error: holdUpdateErr } = await serviceClient
              .from('order_items')
              .update({ stripe_reserve_hold_id: holdId })
              .eq('id', dbItem.id);
            if (holdUpdateErr) {
              // Fix 3：DB 写库失败也进 holdFailures，触发回滚
              console.error(`[ReserveHold] 写入失败 item=${dbItem.id}:`, holdUpdateErr);
              holdFailures.push(dbItem.id);
            } else {
              console.log(`[ReserveHold] 创建成功 item=${dbItem.id} hold=${holdId}`);
            }
          }),
        );

        if (holdFailures.length > 0) {
          console.error(`[ReserveHold] Hold 失败，回滚订单 items=${holdFailures.join(',')}`);

          // Fix 2：释放所有已成功创建的 Hold
          for (const { connectId, holdId } of createdHolds) {
            try {
              await fetch('https://api.stripe.com/v1/reserve/releases', {
                method: 'POST',
                headers: {
                  Authorization: `Bearer ${stripeKey}`,
                  'Stripe-Version': '2025-08-27.preview',
                  'Stripe-Account': connectId,
                  'Content-Type': 'application/x-www-form-urlencoded',
                },
                body: new URLSearchParams({ reserve_hold: holdId }).toString(),
              });
            } catch (err) {
              console.error(`[ReserveHold] 回滚释放失败 hold=${holdId}，需人工处理:`, err);
            }
          }

          // Fix 1：Reverse 所有已成功的 Transfer（确保资金回到平台再退款）
          for (const [, transferId] of successfulTransfers) {
            try {
              const revRes = await fetch(`https://api.stripe.com/v1/transfers/${transferId}/reversals`, {
                method: 'POST',
                headers: {
                  Authorization: `Bearer ${stripeKey}`,
                  'Content-Type': 'application/x-www-form-urlencoded',
                },
              });
              if (!revRes.ok) {
                console.error(`[Transfer] Reversal 失败 transfer=${transferId}，需人工处理:`, await revRes.text());
              } else {
                console.log(`[Transfer] Reversal 成功 transfer=${transferId}`);
              }
            } catch (err) {
              console.error(`[Transfer] Reversal 网络异常 transfer=${transferId}，需人工处理:`, err);
            }
          }

          // 退款（Store Credit 全额覆盖时无 Stripe PI，跳过）
          if (!skipStripeVerification) {
            try {
              const refundRes = await fetch('https://api.stripe.com/v1/refunds', {
                method: 'POST',
                headers: {
                  Authorization: `Bearer ${stripeKey}`,
                  'Content-Type': 'application/x-www-form-urlencoded',
                },
                body: new URLSearchParams({ payment_intent: paymentIntentId }).toString(),
              });
              if (!refundRes.ok) {
                console.error('[ReserveHold] 退款调用失败，需人工处理:', await refundRes.text());
              } else {
                console.log('[ReserveHold] 退款成功 pi=', paymentIntentId);
              }
            } catch (err) {
              console.error('[ReserveHold] 退款网络异常，需人工处理:', err);
            }
          }

          // 删除订单（级联删除 order_items）
          await serviceClient.from('orders').delete().eq('id', orderId);
          return jsonResponse({ error: 'ReserveHold 创建失败，订单已取消，支付已退款' }, 500);
        }
      }
    }

    // ----------------------------------------------------------------
    // 6.6. 记录每张 order_item 的实际 stripe_transfer_amount（退款精确逆向用）
    //   多商家：merchantNetMap 已含 stripe_fee 摊薄，按 item 比例分配
    //   单商家：PI application_fee_amount 反推实际 transfer，按 item 比例分配
    // ----------------------------------------------------------------
    if (insertedItems && insertedItems.length > 0 && !skipStripeVerification) {
      try {
        const itemTransferUpdates: Array<{ id: string; stripe_transfer_amount: number }> = [];

        if (merchantIdsForReserve.length > 1) {
          // ── 多商家：使用已计算好的 merchantNetMap（含 stripe_fee 摊薄）──
          // 先汇总每个商家下所有 items 的 merchant_net 总量，用于按比例分配
          const merchantItemNetTotals = new Map<string, number>(); // merchantId → total merchant_net(cents)
          for (const dbItem of (insertedItems as any[])) {
            const mid = dbItem.purchased_merchant_id as string | null;
            if (!mid) continue;
            const net = Math.max(0,
              Math.round((Number(dbItem.unit_price) - Number(dbItem.commission_amount ?? 0) - Number(dbItem.promo_discount ?? 0)) * 100),
            );
            merchantItemNetTotals.set(mid, (merchantItemNetTotals.get(mid) ?? 0) + net);
          }

          for (const dbItem of (insertedItems as any[])) {
            const mid = dbItem.purchased_merchant_id as string | null;
            if (!mid) continue;
            const connectId = reserveMerchantConnectMap.get(mid);
            if (!connectId || !successfulTransfers.has(connectId)) continue; // 分账失败的跳过

            const actualMerchantTransferCents = merchantNetMap.get(connectId) ?? 0;
            const merchantTotalNetCents = merchantItemNetTotals.get(mid) ?? 0;
            const itemNetCents = Math.max(0,
              Math.round((Number(dbItem.unit_price) - Number(dbItem.commission_amount ?? 0) - Number(dbItem.promo_discount ?? 0)) * 100),
            );

            if (merchantTotalNetCents > 0 && actualMerchantTransferCents > 0) {
              const itemTransferCents = Math.round(actualMerchantTransferCents * (itemNetCents / merchantTotalNetCents));
              if (itemTransferCents > 0) {
                itemTransferUpdates.push({ id: dbItem.id, stripe_transfer_amount: itemTransferCents / 100 });
              }
            }
          }
        } else {
          // ── 单商家：PI 自动 transfer，从 application_fee_amount 反推 ──
          const appFeeCents = Number((paymentIntent as any).application_fee_amount ?? 0);
          const totalAmountCents = Math.round((totalAmount ?? 0) * 100);
          const actualTransferCents = Math.max(0, totalAmountCents - appFeeCents);

          if (actualTransferCents > 0) {
            const totalNetCents = (insertedItems as any[]).reduce((sum: number, it: any) => {
              return sum + Math.max(0,
                Math.round((Number(it.unit_price) - Number(it.commission_amount ?? 0) - Number(it.promo_discount ?? 0)) * 100),
              );
            }, 0);

            for (const dbItem of (insertedItems as any[])) {
              const itemNetCents = Math.max(0,
                Math.round((Number(dbItem.unit_price) - Number(dbItem.commission_amount ?? 0) - Number(dbItem.promo_discount ?? 0)) * 100),
              );
              if (totalNetCents > 0) {
                const itemTransferCents = Math.round(actualTransferCents * (itemNetCents / totalNetCents));
                if (itemTransferCents > 0) {
                  itemTransferUpdates.push({ id: dbItem.id, stripe_transfer_amount: itemTransferCents / 100 });
                }
              }
            }
          }
        }

        if (itemTransferUpdates.length > 0) {
          await Promise.allSettled(
            itemTransferUpdates.map(({ id, stripe_transfer_amount }) =>
              serviceClient.from('order_items').update({ stripe_transfer_amount }).eq('id', id),
            ),
          );
          console.log(`[TransferAmount] 已写入 ${itemTransferUpdates.length} 张 item 的 stripe_transfer_amount`);
        }
      } catch (taErr) {
        // 写入失败不阻断订单，退款时会降级到比例计算
        console.error('[TransferAmount] 写入失败（不阻断，退款时降级）:', taErr);
      }
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
