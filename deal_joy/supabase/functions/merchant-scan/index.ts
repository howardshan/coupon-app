// =============================================================
// Edge Function: merchant-scan
// 功能: 团购券核销相关 API — 验证/核销/撤销/历史记录
// 路由:
//   POST /merchant-scan/verify  — 验证券码（只查询，不核销）
//   POST /merchant-scan/redeem  — 执行核销
//   POST /merchant-scan/revert  — 撤销核销（10分钟内）
//   GET  /merchant-scan/history — 分页获取核销历史
// =============================================================

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { type AuthResult, resolveAuth, requirePermission } from "../_shared/auth.ts";
import { sendEmail } from '../_shared/email.ts';
import { buildC3Email } from '../_shared/email-templates/customer/coupon-redeemed.ts';
import { buildM7Email } from '../_shared/email-templates/merchant/coupon-redeemed.ts';

// Stripe Secret Key（用于 manual capture 时调用 Stripe API）
const STRIPE_SECRET_KEY = Deno.env.get('STRIPE_SECRET_KEY') ?? '';

// CORS 响应头（允许商家端 App 调用）
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-merchant-id',
  'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
};

// 统一 JSON 响应工具函数
function jsonResponse(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

// 错误响应工具函数
function errorResponse(error: string, message: string, detail?: string, status = 400) {
  return jsonResponse({ error, message, detail }, status);
}

// 对用户名进行脱敏处理，例如 "John Smith" → "J*** Smith"
function maskUserName(fullName: string | null): string {
  if (!fullName) return 'Unknown User';
  const parts = fullName.trim().split(' ');
  if (parts.length === 0) return 'Unknown User';
  // 保留首字母，其余用 *** 替代
  const first = parts[0];
  const rest = parts.slice(1).join(' ');
  const masked = first.charAt(0) + '***';
  return rest ? `${masked} ${rest}` : masked;
}

// ─── Stripe Reserves API 辅助函数 ────────────────────────────────────────────

/**
 * 在 connected account 上创建 ReserveHold（冻结资金）
 * 撤销核销后需重建 Hold，防止商家在 revert 后仍能提现
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
      console.error(`[ReserveHold] 创建失败 acct=${connectedAccountId}:`, errText);
      return null;
    }
    const json = await res.json();
    console.log(`[ReserveHold] 创建成功 hold=${json.id} acct=${connectedAccountId}`);
    return (json.id as string) ?? null;
  } catch (err) {
    console.error(`[ReserveHold] 网络异常 acct=${connectedAccountId}:`, err);
    return null;
  }
}

/**
 * 释放 connected account 上的 ReserveHold
 * 核销后商家 merchant_net 解冻，可进入提现流程
 */
async function releaseReserveHold(
  connectedAccountId: string,
  holdId: string,
  stripeKey: string,
): Promise<void> {
  const body = new URLSearchParams({ reserve_hold: holdId });
  try {
    const res = await fetch('https://api.stripe.com/v1/reserve/releases', {
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
      // 释放失败不阻断核销流程，记录告警供人工处理
      console.error(`[ReserveRelease] 释放失败 hold=${holdId} acct=${connectedAccountId}:`, errText);
    } else {
      console.log(`[ReserveRelease] 释放成功 hold=${holdId} acct=${connectedAccountId}`);
    }
  } catch (err) {
    console.error(`[ReserveRelease] 网络异常 hold=${holdId}:`, err);
  }
}

// =============================================================
// 主路由处理器
// =============================================================
serve(async (req: Request) => {
  // 处理 CORS 预检请求
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  const url = new URL(req.url);
  const pathname = url.pathname;

  // 从请求头提取 JWT，用于身份验证
  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    return errorResponse('unauthorized', 'Missing authorization header', undefined, 401);
  }

  // 创建 Supabase 客户端（service_role 用于 BYPASS RLS 执行核销写操作）
  const supabaseAdmin = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  );

  // 创建用户级别客户端（用于验证 JWT 和获取当前用户信息）
  const supabaseUser = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_ANON_KEY') ?? '',
    { global: { headers: { Authorization: authHeader } } },
  );

  // 验证 JWT 并获取当前登录用户
  const { data: { user }, error: authError } = await supabaseUser.auth.getUser();
  if (authError || !user) {
    return errorResponse('unauthorized', 'Invalid or expired token', undefined, 401);
  }

  // 统一鉴权
  let auth;
  try {
    auth = await resolveAuth(supabaseAdmin, user.id, req.headers);
  } catch (e) {
    return errorResponse('unauthorized', (e as Error).message, undefined, 403);
  }
  requirePermission(auth, 'scan');

  // 获取商家名称（核销记录需要）
  const { data: merchant } = await supabaseAdmin
    .from('merchants')
    .select('id, name, status')
    .eq('id', auth.merchantId)
    .single();

  if (!merchant) {
    return errorResponse('forbidden', 'No merchant account found for this user', undefined, 403);
  }

  const merchantId = merchant.id;

  // 路由分发
  if (req.method === 'POST' && pathname.endsWith('/verify')) {
    return handleVerify(req, supabaseAdmin, merchantId);
  }

  if (req.method === 'POST' && pathname.endsWith('/redeem')) {
    return handleRedeem(req, supabaseAdmin, merchantId, user.id, auth);
  }

  if (req.method === 'POST' && pathname.endsWith('/revert')) {
    return handleRevert(req, supabaseAdmin, merchantId, user.id);
  }

  if (req.method === 'GET' && pathname.endsWith('/history')) {
    return handleHistory(url, supabaseAdmin, merchantId);
  }

  return errorResponse('not_found', 'Route not found', undefined, 404);
});

// =============================================================
// POST /merchant-scan/verify — 验证券码（不核销）
// 请求体: { code: string }
// 返回: CouponInfo 或 错误信息
// =============================================================
async function handleVerify(
  req: Request,
  supabase: ReturnType<typeof createClient>,
  merchantId: string,
) {
  let body: { code?: string };
  try {
    body = await req.json();
  } catch {
    return errorResponse('invalid_request', 'Request body must be valid JSON');
  }

  const rawCode = body.code?.trim();
  const normalizedCode = rawCode.replaceAll('-', '').replaceAll(' ', '');
  if (!normalizedCode) {
    return errorResponse('invalid_code', 'Please enter a valid voucher code');
  }

  // 查询券码，JOIN deals 获取标题，JOIN users 获取用户名，JOIN orders 获取门店快照
  const { data: coupon, error } = await supabase
    .from('coupons')
    .select(`
      id,
      qr_code,
      status,
      expires_at,
      redeemed_at,
      reverted_at,
      merchant_id,
      deal_id,
      order_id,
      order_item_id,
      order_items!coupons_order_item_id_fkey (
        applicable_store_ids
      ),
      deals!inner (
        title
      ),
      users!coupons_user_id_fkey (
        full_name
      )
    `)
    .or(`qr_code.eq.${normalizedCode},coupon_code.eq.${normalizedCode.toUpperCase()}`)
    .maybeSingle();

  if (error) {
    console.error('verify query error:', error);
    return errorResponse('server_error', 'Failed to query coupon', undefined, 500);
  }

  if (!coupon) {
    return errorResponse('not_found', 'Invalid voucher code');
  }

  // 检查门店是否有权核销此券（优先用购买时门店快照）
  // deno-lint-ignore no-explicit-any
  const itemData = (coupon as any).order_items;
  const snapshotStoreIds: string[] | null = itemData?.applicable_store_ids ?? null;
  const storeCheckResult = await checkStoreRedemptionEligibility(
    supabase, coupon.deal_id, merchantId, snapshotStoreIds
  );
  if (!storeCheckResult.allowed) {
    return errorResponse('wrong_merchant', storeCheckResult.message ?? 'This voucher is not valid at this location.');
  }

  // 检查各种状态异常
  if (coupon.status === 'used' && !coupon.reverted_at) {
    const redeemedDate = coupon.redeemed_at
      ? new Date(coupon.redeemed_at).toLocaleDateString('en-US', {
        month: 'short', day: 'numeric', year: 'numeric',
      })
      : 'unknown date';
    return errorResponse(
      'already_used',
      `This voucher has already been redeemed on ${redeemedDate}`,
      coupon.redeemed_at,
    );
  }

  if (coupon.status === 'refunded') {
    return errorResponse(
      'already_refunded',
      'This voucher has been refunded and is no longer valid',
    );
  }

  if (coupon.status === 'voided') {
    return errorResponse(
      'voided',
      'This voucher is no longer valid — the merchant updated this offer',
    );
  }

  if (coupon.status === 'expired') {
    const expiredDate = new Date(coupon.expires_at).toLocaleDateString('en-US', {
      month: 'short', day: 'numeric', year: 'numeric',
    });
    return errorResponse(
      'expired',
      `This voucher expired on ${expiredDate}`,
      coupon.expires_at,
    );
  }

  // 额外检查：即使数据库状态是 active，也要检查到期时间
  if (new Date(coupon.expires_at) < new Date()) {
    const expiredDate = new Date(coupon.expires_at).toLocaleDateString('en-US', {
      month: 'short', day: 'numeric', year: 'numeric',
    });
    return errorResponse(
      'expired',
      `This voucher expired on ${expiredDate}`,
      coupon.expires_at,
    );
  }

  // 获取用户名并脱敏
  // deno-lint-ignore no-explicit-any
  const userData = (coupon as any).users;
  const rawName = userData?.full_name ?? null;
  const maskedName = maskUserName(rawName);

  // deno-lint-ignore no-explicit-any
  const dealData = (coupon as any).deals;
  const dealTitle = dealData?.title ?? 'Unknown Deal';

  return jsonResponse({
    id: coupon.id,
    code: coupon.qr_code,
    deal_title: dealTitle,
    user_name: maskedName,
    valid_until: coupon.expires_at,
    status: coupon.status,
    redeemed_at: coupon.redeemed_at,
    error: null,
  });
}

// =============================================================
// POST /merchant-scan/redeem — 执行核销
// 请求体: { coupon_id: string }
// =============================================================
async function handleRedeem(
  req: Request,
  supabase: ReturnType<typeof createClient>,
  merchantId: string,
  actorUserId: string,
  auth: AuthResult,
) {
  let body: { coupon_id?: string };
  try {
    body = await req.json();
  } catch {
    return errorResponse('invalid_request', 'Request body must be valid JSON');
  }

  const couponId = body.coupon_id?.trim();
  if (!couponId) {
    return errorResponse('invalid_request', 'coupon_id is required');
  }

  if (auth.role === 'trainee') {
    return errorResponse(
      'forbidden',
      'Trainee accounts cannot redeem vouchers',
      undefined,
      403,
    );
  }

  // 查询券的当前状态，JOIN order_items 获取门店快照
  const { data: coupon, error: queryError } = await supabase
    .from('coupons')
    .select('id, status, merchant_id, expires_at, redeemed_at, deal_id, order_id, order_item_id, user_id, order_items!coupons_order_item_id_fkey(applicable_store_ids)')
    .eq('id', couponId)
    .single();

  if (queryError || !coupon) {
    return errorResponse('not_found', 'Voucher not found', undefined, 404);
  }

  // 安全检查：用购买时门店快照验证门店权限
  // deno-lint-ignore no-explicit-any
  const redeemItemData = (coupon as any).order_items;
  const redeemSnapshotIds: string[] | null = redeemItemData?.applicable_store_ids ?? null;
  const storeCheckResult = await checkStoreRedemptionEligibility(
    supabase, coupon.deal_id, merchantId, redeemSnapshotIds
  );
  if (!storeCheckResult.allowed) {
    return errorResponse('wrong_merchant', storeCheckResult.message ?? 'This voucher is not valid for your store', undefined, 403);
  }

  // 状态检查
  if (coupon.status === 'used') {
    // 防重复提交：如果10秒内已核销，视为幂等请求，返回成功
    if (coupon.redeemed_at) {
      const secondsAgo = (Date.now() - new Date(coupon.redeemed_at).getTime()) / 1000;
      if (secondsAgo <= 10) {
        return jsonResponse({ redeemed_at: coupon.redeemed_at, coupon_id: couponId });
      }
    }
    return errorResponse('already_used', 'This voucher has already been redeemed');
  }

  if (coupon.status === 'refunded') {
    return errorResponse('already_refunded', 'This voucher has been refunded');
  }

  if (coupon.status === 'voided') {
    return errorResponse('voided', 'This voucher is no longer valid — the merchant updated this offer');
  }

  if (coupon.status === 'expired' || new Date(coupon.expires_at) < new Date()) {
    return errorResponse('expired', 'This voucher has expired');
  }

  // V3: 不再需要预授权检查（已改为直接 charge）

  const now = new Date().toISOString();

  // 更新 coupons 表：标记为已使用，记录实际核销门店
  const { error: updateError } = await supabase
    .from('coupons')
    .update({
      status: 'used',
      redeemed_at: now,
      redeemed_by_merchant_id: merchantId,
      redeemed_at_merchant_id: merchantId, // 实际核销门店，用于按店结算
      used_at: now,
    })
    .eq('id', couponId);

  if (updateError) {
    console.error('redeem update error:', updateError);
    return errorResponse('server_error', 'Failed to redeem voucher', undefined, 500);
  }

  // V3: 更新 order_items 双状态
  // Phase 2C（软性 Reserve 释放）：
  //   redeemed_at 设置后，merchant-withdrawal 的余额计算才会将此笔金额纳入可提现范围
  //   这是 Path B 软性 Reserve 的"释放"时刻（无 Stripe Reserves API 时的替代机制）
  if (coupon.order_item_id) {
    const { error: itemUpdateError } = await supabase
      .from('order_items')
      .update({
        customer_status: 'used',
        merchant_status: 'unpaid',  // unpaid = 已核销但尚未结算打款（T+7 后可提现）
        redeemed_merchant_id: merchantId,
        redeemed_at: now,           // 软性 Reserve 释放时间戳
        redeemed_by: actorUserId,
      })
      .eq('id', coupon.order_item_id);

    if (itemUpdateError) {
      console.error('order_items update error:', itemUpdateError);
    }

    // ── 跨店核销资金转移 + ReserveHold 释放 ──────────────────────────
    // 查询 order_item 的购买商家、金额、reserve hold
    const { data: itemData } = await supabase
      .from('order_items')
      .select('stripe_reserve_hold_id, purchased_merchant_id, unit_price, commission_amount, promo_discount')
      .eq('id', coupon.order_item_id)
      .maybeSingle();

    const holdId = (itemData as any)?.stripe_reserve_hold_id as string | null;
    const purchasedMerchantId = (itemData as any)?.purchased_merchant_id as string | null;
    const stripeKey = Deno.env.get('STRIPE_SECRET_KEY') ?? '';
    const reservesEnabled = Deno.env.get('STRIPE_RESERVES_ENABLED') !== 'false';

    // 跨店核销：redeemed_merchant (当前商家) ≠ purchased_merchant → 资金从 A 转到 B
    // 流程：reverse_transfer(A) → transfer(B)，确保核销商家拿到 merchant_net
    if (purchasedMerchantId && purchasedMerchantId !== merchantId && stripeKey) {
      const unitPrice = Number((itemData as any)?.unit_price ?? 0);
      const commissionAmount = Number((itemData as any)?.commission_amount ?? 0);
      const promoDiscount = Number((itemData as any)?.promo_discount ?? 0);
      const merchantNetCents = Math.round((unitPrice - promoDiscount - commissionAmount) * 100);

      if (merchantNetCents > 0) {
        // 查询两个商家的 Stripe Connect 信息
        const { data: bothMerchants } = await supabase
          .from('merchants')
          .select('id, stripe_account_id, stripe_account_status')
          .in('id', [purchasedMerchantId, merchantId]);

        const purchasedConnect = (bothMerchants ?? []).find((m: any) => m.id === purchasedMerchantId);
        const redeemedConnect = (bothMerchants ?? []).find((m: any) => m.id === merchantId);

        // 不依赖 stripe_account_status，只要有 stripe_account_id 即可尝试
        // purchasedConnect 的逆向通过 PI transfer 判断（有 transfer 才逆），不需要状态校验
        // redeemedConnect 的转账由 Stripe 侧校验账户可用性
        const purchasedConnectId = purchasedConnect?.stripe_account_id ?? null;
        const redeemedConnectId = redeemedConnect?.stripe_account_id ?? null;

        if (purchasedConnectId && redeemedConnectId) {
          try {
            // Step 1: 从购买商家 A 回撤 merchant_net（platform 拿回资金）
            // 找到原始 Transfer ID（从 order 的 payment_intent 追溯）
            const { data: orderData } = await supabase
              .from('orders')
              .select('payment_intent_id')
              .eq('id', coupon.order_id)
              .maybeSingle();

            const piId = (orderData as any)?.payment_intent_id as string | null;
            if (piId && !piId.startsWith('store_credit_')) {
              // 通过 Stripe API 获取 PI → latest_charge → transfer
              const piRes = await fetch(`https://api.stripe.com/v1/payment_intents/${piId}?expand[]=latest_charge.transfer`, {
                headers: { Authorization: `Bearer ${stripeKey}` },
              });
              const piJson = await piRes.json();
              const transferObj = (piJson as any)?.latest_charge?.transfer;
              const transferId = typeof transferObj === 'string' ? transferObj : transferObj?.id;

              if (transferId) {
                // Reverse transfer 从 A 回到平台
                const revRes = await fetch(`https://api.stripe.com/v1/transfers/${transferId}/reversals`, {
                  method: 'POST',
                  headers: {
                    Authorization: `Bearer ${stripeKey}`,
                    'Content-Type': 'application/x-www-form-urlencoded',
                  },
                  body: new URLSearchParams({
                    amount: String(merchantNetCents),
                    metadata: JSON.stringify({
                      reason: 'cross_store_redeem',
                      from_merchant: purchasedMerchantId,
                      to_merchant: merchantId,
                      order_item_id: coupon.order_item_id,
                    }),
                  }).toString(),
                });

                if (!revRes.ok) {
                  console.error('[CrossRedeem] reverse_transfer 失败:', await revRes.text());
                } else {
                  console.log(`[CrossRedeem] reverse_transfer 成功 from=${purchasedMerchantId}`);

                  // Step 2: Transfer merchant_net 到核销商家 B
                  const xferRes = await fetch('https://api.stripe.com/v1/transfers', {
                    method: 'POST',
                    headers: {
                      Authorization: `Bearer ${stripeKey}`,
                      'Content-Type': 'application/x-www-form-urlencoded',
                    },
                    body: new URLSearchParams({
                      amount: String(merchantNetCents),
                      currency: 'usd',
                      destination: redeemedConnectId,
                      metadata: JSON.stringify({
                        reason: 'cross_store_redeem',
                        from_merchant: purchasedMerchantId,
                        order_item_id: coupon.order_item_id,
                      }),
                    }).toString(),
                  });

                  if (!xferRes.ok) {
                    console.error('[CrossRedeem] transfer to redeemer 失败:', await xferRes.text());
                  } else {
                    console.log(`[CrossRedeem] transfer 成功 to=${merchantId} amount=${merchantNetCents}c`);
                  }
                }
              } else {
                console.warn('[CrossRedeem] 无法获取原始 Transfer ID，跳过跨店结算');
              }
            }
          } catch (crossErr) {
            // 跨店结算失败不阻断核销流程，记录告警供人工处理
            console.error('[CrossRedeem] 跨店结算异常（需人工处理）:', crossErr);
          }
        } else {
          console.warn(`[CrossRedeem] 商家 Connect 未就绪: purchased=${purchasedConnectId} redeemed=${redeemedConnectId}`);
        }
      }
    }

    // ── Stripe ReserveHold 释放（Path A 硬性 Reserve 解冻）──────────────
    // redeemed_at 设置后，merchant_net 解冻，核销商家可在 T+7 后提现
    if (holdId && purchasedMerchantId) {
      const { data: merchantData } = await supabase
        .from('merchants')
        .select('stripe_account_id, stripe_account_status')
        .eq('id', purchasedMerchantId)
        .maybeSingle();

      const connectId = (merchantData as any)?.stripe_account_id as string | null ?? null;
      if (connectId && reservesEnabled) {
        releaseReserveHold(connectId, holdId, stripeKey).catch(err => {
          console.error('[ReserveRelease] 核销释放异常:', err);
        });
      }
    }
  }

  // ── Store Credit 订单核销：从平台 Stripe 余额 transfer 给商家 ──
  // Store Credit 支付不经过 Stripe，核销时需主动从平台余额给商家 Connect 转账
  console.log(`[StoreCreditRedeem] checking: order_item_id=${coupon.order_item_id ?? 'null'} order_id=${coupon.order_id ?? 'null'}`);
  if (coupon.order_item_id) {
    const { data: orderForSC, error: orderSCErr } = await supabase
      .from('orders')
      .select('payment_intent_id')
      .eq('id', coupon.order_id)
      .maybeSingle();
    console.log(`[StoreCreditRedeem] order query: pi=${(orderForSC as any)?.payment_intent_id ?? 'null'} err=${orderSCErr?.message ?? 'none'}`);
    const piIdForSC = (orderForSC as any)?.payment_intent_id as string | null;

    if (piIdForSC && piIdForSC.startsWith('store_credit_')) {
      console.log(`[StoreCreditRedeem] IS store_credit order, proceeding...`);
      // 读取快照的 merchant_net（stripe_transfer_amount）
      const { data: scItemData } = await supabase
        .from('order_items')
        .select('stripe_transfer_amount, unit_price, commission_amount, stripe_fee_amount')
        .eq('id', coupon.order_item_id)
        .maybeSingle();

      const storedTransfer = Number((scItemData as any)?.stripe_transfer_amount ?? 0);
      // fallback：没快照时手动算
      const scMerchantNet = storedTransfer > 0
        ? storedTransfer
        : Number((scItemData as any)?.unit_price ?? 0) - Number((scItemData as any)?.commission_amount ?? 0) - Number((scItemData as any)?.stripe_fee_amount ?? 0);
      const scMerchantNetCents = Math.round(scMerchantNet * 100);

      if (scMerchantNetCents > 0) {
        // 查核销商家的 Connect 账户
        const { data: scMerchantData } = await supabase
          .from('merchants')
          .select('stripe_account_id')
          .eq('id', merchantId)
          .maybeSingle();
        const scConnectId = (scMerchantData as any)?.stripe_account_id as string | null;
        const scStripeKey = Deno.env.get('STRIPE_SECRET_KEY') ?? '';

        if (scConnectId && scStripeKey) {
          try {
            // 从平台 Stripe 余额直接 transfer 给商家（不依赖 PaymentIntent）
            const xferRes = await fetch('https://api.stripe.com/v1/transfers', {
              method: 'POST',
              headers: {
                Authorization: `Bearer ${scStripeKey}`,
                'Content-Type': 'application/x-www-form-urlencoded',
              },
              body: new URLSearchParams({
                amount: String(scMerchantNetCents),
                currency: 'usd',
                destination: scConnectId,
                'metadata[reason]': 'store_credit_redeem',
                'metadata[order_item_id]': coupon.order_item_id,
                'metadata[merchant_id]': merchantId,
              }).toString(),
            });

            if (!xferRes.ok) {
              const errText = await xferRes.text();
              console.error(`[StoreCreditRedeem] Transfer 失败 merchant=${merchantId}: ${errText}`);
            } else {
              const xferJson = await xferRes.json();
              console.log(`[StoreCreditRedeem] Transfer 成功 id=${xferJson.id} amount=${scMerchantNetCents}c to=${scConnectId}`);
              // 记录 transfer ID 到 order_items
              await supabase
                .from('order_items')
                .update({ stripe_redeeming_transfer_id: xferJson.id })
                .eq('id', coupon.order_item_id);
            }
          } catch (scErr) {
            console.error('[StoreCreditRedeem] Transfer 异常（需人工处理）:', scErr);
          }
        } else {
          console.warn(`[StoreCreditRedeem] 商家 ${merchantId} 无 Connect 账户，Store Credit 订单资金需人工结算`);
        }
      }
    }
  }

  // 写入核销日志
  const { error: logError } = await supabase
    .from('redemption_log')
    .insert({
      coupon_id: couponId,
      merchant_id: merchantId,
      action: 'redeem',
      actor_user_id: actorUserId,
    });

  if (logError) {
    // 日志写失败不影响核销结果，只记录错误
    console.error('redemption_log insert error:', logError);
  }

  // V3: 不再需要 capture（已改为直接 charge）

  // 发送邮件（即发即忘，不阻断核销流程）
  try {
    const { data: dealInfo } = await supabase
      .from('deals').select('title').eq('id', coupon.deal_id).single();
    const dealTitle = (dealInfo?.title as string | undefined) ?? 'Unknown Deal';

    const { data: itemInfo } = await supabase
      .from('order_items').select('unit_price').eq('id', coupon.order_item_id).single();
    const unitPrice = Number((itemInfo as any)?.unit_price ?? 0);

    const { data: merchantInfo } = await supabase
      .from('merchants').select('name, user_id').eq('id', merchantId).single();
    const merchantName = (merchantInfo?.name as string | undefined) ?? '';

    // 脱敏 coupon code（仅显示后4位）
    const rawCode = ((coupon as any).qr_code as string) ?? '';
    const maskedCode = rawCode.length > 4 ? `****${rawCode.slice(-4)}` : rawCode;

    // C3：发给客户
    const customerUserId = ((coupon as any).user_id as string | null);
    if (customerUserId) {
      const { data: customerUser } = await supabase
        .from('users').select('email').eq('id', customerUserId).single();
      if (customerUser?.email) {
        const { subject, html } = buildC3Email({ dealTitle, merchantName, redeemedAt: now, unitPrice });
        await sendEmail(supabase, {
          to: customerUser.email, subject, htmlBody: html,
          emailCode: 'C3', referenceId: couponId, recipientType: 'customer', userId: customerUserId,
        });
      }
    }

    // M7：发给商家
    if (merchantInfo?.user_id) {
      const { data: merchantUser } = await supabase
        .from('users').select('email').eq('id', merchantInfo.user_id).single();
      if (merchantUser?.email) {
        const { subject, html } = buildM7Email({ merchantName, dealTitle, couponCode: maskedCode, redeemedAt: now, unitPrice });
        await sendEmail(supabase, {
          to: merchantUser.email, subject, htmlBody: html,
          emailCode: 'M7', referenceId: couponId, recipientType: 'merchant', merchantId,
        });
      }
    }
  } catch (emailErr) {
    console.error('merchant-scan redeem: email error:', emailErr);
  }

  const { data: dealTips } = await supabase
    .from('deals')
    .select('tips_enabled, tips_mode, tips_preset_1, tips_preset_2, tips_preset_3, discount_price')
    .eq('id', coupon.deal_id)
    .maybeSingle();

  let tipBaseCents = 0;
  if (coupon.order_item_id) {
    const { data: oiRow } = await supabase
      .from('order_items')
      .select('unit_price')
      .eq('id', coupon.order_item_id)
      .maybeSingle();
    tipBaseCents = Math.round(Number((oiRow as { unit_price?: number } | null)?.unit_price ?? 0) * 100);
  }
  if (tipBaseCents <= 0) {
    const dp = Number((dealTips as { discount_price?: number } | null)?.discount_price ?? 0);
    tipBaseCents = Math.round(dp * 100);
  }

  return jsonResponse({
    redeemed_at: now,
    coupon_id: couponId,
    tip_base_cents: tipBaseCents,
    deal: {
      tips_enabled: (dealTips as { tips_enabled?: boolean } | null)?.tips_enabled ?? false,
      tips_mode: (dealTips as { tips_mode?: string | null } | null)?.tips_mode ?? null,
      tips_preset_1: (dealTips as { tips_preset_1?: number | null } | null)?.tips_preset_1 ?? null,
      tips_preset_2: (dealTips as { tips_preset_2?: number | null } | null)?.tips_preset_2 ?? null,
      tips_preset_3: (dealTips as { tips_preset_3?: number | null } | null)?.tips_preset_3 ?? null,
    },
  });
}

// =============================================================
// POST /merchant-scan/revert — 撤销核销（仅10分钟内有效）
// 请求体: { coupon_id: string }
// =============================================================
async function handleRevert(
  req: Request,
  supabase: ReturnType<typeof createClient>,
  merchantId: string,
  actorUserId: string,
) {
  let body: { coupon_id?: string };
  try {
    body = await req.json();
  } catch {
    return errorResponse('invalid_request', 'Request body must be valid JSON');
  }

  const couponId = body.coupon_id?.trim();
  if (!couponId) {
    return errorResponse('invalid_request', 'coupon_id is required');
  }

  // 查询券状态（含 order_item_id，用于 revert 后回滚 order_items 及重建 ReserveHold）
  const { data: coupon, error: queryError } = await supabase
    .from('coupons')
    .select('id, status, merchant_id, redeemed_at, redeemed_by_merchant_id, redeemed_at_merchant_id, order_item_id')
    .eq('id', couponId)
    .single();

  if (queryError || !coupon) {
    return errorResponse('not_found', 'Voucher not found', undefined, 404);
  }

  // 允许撤销的门店：原始售卖门店 或 实际核销门店
  const isOriginalMerchant = coupon.merchant_id === merchantId;
  const isRedeemingMerchant = coupon.redeemed_by_merchant_id === merchantId || coupon.redeemed_at_merchant_id === merchantId;
  if (!isOriginalMerchant && !isRedeemingMerchant) {
    return errorResponse('wrong_merchant', 'This voucher does not belong to your store', undefined, 403);
  }

  // 检查是否处于已核销状态
  if (coupon.status !== 'used' || !coupon.redeemed_at) {
    return errorResponse('invalid_state', 'This voucher has not been redeemed');
  }

  // 检查是否在10分钟内
  const redeemedAt = new Date(coupon.redeemed_at);
  const minutesAgo = (Date.now() - redeemedAt.getTime()) / 1000 / 60;
  if (minutesAgo > 10) {
    return errorResponse(
      'revert_expired',
      'Cannot revert after 10 minutes',
      `Redeemed at ${coupon.redeemed_at}`,
    );
  }

  const now = new Date().toISOString();

  // 恢复券状态为 active，清空核销相关字段
  const { error: updateError } = await supabase
    .from('coupons')
    .update({
      status: 'active',
      redeemed_at: null,
      redeemed_by_merchant_id: null,
      redeemed_at_merchant_id: null, // 清除实际核销门店
      reverted_at: now,
      used_at: null,
    })
    .eq('id', couponId);

  if (updateError) {
    console.error('revert update error:', updateError);
    return errorResponse('server_error', 'Failed to revert redemption', undefined, 500);
  }

  // ── 回滚 order_items 核销状态 + 重建 ReserveHold ──────────────────────────
  // revert 让券回到「未核销」状态，order_items 和 Hold 也需同步回滚
  const orderItemId = (coupon as any).order_item_id as string | null;
  if (orderItemId) {
    // 回滚 order_items，并取回重建 Hold 所需的字段
    const { data: rolledBackItem } = await supabase
      .from('order_items')
      .update({
        customer_status: 'unused',
        merchant_status: 'unused',
        redeemed_at: null,
        redeemed_merchant_id: null,
        redeemed_by: null,
        stripe_reserve_hold_id: null, // 旧 hold 已在核销时释放，清空等待重建
      })
      .eq('id', orderItemId)
      .select('unit_price, commission_amount, promo_discount, purchased_merchant_id')
      .maybeSingle();

    // 重建 ReserveHold（冻结恢复）
    if (rolledBackItem) {
      const itemMerchantId = (rolledBackItem as any).purchased_merchant_id as string | null;
      if (itemMerchantId) {
        const { data: merchantConnectData } = await supabase
          .from('merchants')
          .select('stripe_account_id, stripe_account_status')
          .eq('id', itemMerchantId)
          .maybeSingle();

        // 只对已完成 Connect 入驻的商家重建 Hold
        const revertConnectId = (merchantConnectData as any)?.stripe_account_status === 'connected'
          ? (merchantConnectData as any)?.stripe_account_id as string | null
          : null;

        if (revertConnectId) {
          const unitPrice = Number((rolledBackItem as any).unit_price ?? 0);
          const promoDiscount = Number((rolledBackItem as any).promo_discount ?? 0);
          const commAmount = Number((rolledBackItem as any).commission_amount ?? 0);
          const merchantNetCents = Math.round((unitPrice - promoDiscount - commAmount) * 100);

          if (merchantNetCents > 0) {
            const stripeKey = Deno.env.get('STRIPE_SECRET_KEY') ?? '';
            // fire-and-forget：重建失败不阻断 revert 响应
            createReserveHold(revertConnectId, merchantNetCents, stripeKey).then(async (newHoldId) => {
              if (newHoldId) {
                await supabase
                  .from('order_items')
                  .update({ stripe_reserve_hold_id: newHoldId })
                  .eq('id', orderItemId);
                console.log(`[Revert] ReserveHold 重建成功 item=${orderItemId} hold=${newHoldId}`);
              }
            }).catch(err => {
              console.error(`[Revert] ReserveHold 重建失败 item=${orderItemId}:`, err);
            });
          }
        }
      }
    }
  }

  // 写入撤销日志
  const { error: logError } = await supabase
    .from('redemption_log')
    .insert({
      coupon_id: couponId,
      merchant_id: merchantId,
      action: 'revert',
      actor_user_id: actorUserId,
    });

  if (logError) {
    console.error('redemption_log revert insert error:', logError);
  }

  return jsonResponse({ reverted_at: now, coupon_id: couponId });
}

// =============================================================
// 辅助：验证门店是否有权核销此 Deal
// 优先使用 orders.applicable_store_ids（购买时快照），
// 如果为 NULL（历史订单），回退查 deal_applicable_stores 当前状态
// 返回 { allowed: boolean, message?: string }
// =============================================================
async function checkStoreRedemptionEligibility(
  supabase: ReturnType<typeof createClient>,
  dealId: string,
  merchantId: string,
  snapshotStoreIds: string[] | null,
): Promise<{ allowed: boolean; message?: string }> {

  // ── 情况 1：有购买时快照 → 直接判断 ──
  if (snapshotStoreIds && snapshotStoreIds.length > 0) {
    if (snapshotStoreIds.includes(merchantId)) {
      return { allowed: true };
    }

    // 不在快照中 → 查出快照中门店的名称提示用户
    const { data: validStores } = await supabase
      .from('merchants')
      .select('name')
      .in('id', snapshotStoreIds);

    // deno-lint-ignore no-explicit-any
    const names = (validStores ?? []).map((r: any) => r.name).filter(Boolean).join(', ');
    return {
      allowed: false,
      message: names
        ? `This voucher is not valid at this location. Valid at: ${names}`
        : 'This voucher is not valid at this location.',
    };
  }

  // ── 情况 2：无快照（历史订单）→ 回退查当前 active 门店 ──
  const { data: activeStores } = await supabase
    .from('deal_applicable_stores')
    .select('store_id')
    .eq('deal_id', dealId)
    .eq('status', 'active');

  if (!activeStores || activeStores.length === 0) {
    // 没有 deal_applicable_stores 记录 → 单店 Deal，检查 merchant_id 是否匹配
    const { data: deal } = await supabase
      .from('deals')
      .select('merchant_id')
      .eq('id', dealId)
      .single();

    if (deal && deal.merchant_id === merchantId) {
      return { allowed: true };
    }
    return { allowed: false, message: 'This voucher is not valid at this location.' };
  }

  // deno-lint-ignore no-explicit-any
  const activeIds = activeStores.map((r: any) => r.store_id);
  if (activeIds.includes(merchantId)) {
    return { allowed: true };
  }

  // 查出 active 门店名称提示用户
  const { data: storeNames } = await supabase
    .from('merchants')
    .select('name')
    .in('id', activeIds);

  // deno-lint-ignore no-explicit-any
  const names = (storeNames ?? []).map((r: any) => r.name).filter(Boolean).join(', ');
  return {
    allowed: false,
    message: names
      ? `This voucher is not valid at this location. Valid at: ${names}`
      : 'This voucher is not valid at this location.',
  };
}

// =============================================================
// GET /merchant-scan/history — 分页获取核销历史
// Query params: date_from, date_to, deal_id, page, per_page
// =============================================================
async function handleHistory(
  url: URL,
  supabase: ReturnType<typeof createClient>,
  merchantId: string,
) {
  const dateFrom = url.searchParams.get('date_from');
  const dateTo = url.searchParams.get('date_to');
  const dealId = url.searchParams.get('deal_id');
  const page = Math.max(1, parseInt(url.searchParams.get('page') ?? '1', 10));
  const perPage = Math.min(50, Math.max(1, parseInt(url.searchParams.get('per_page') ?? '20', 10)));
  const offset = (page - 1) * perPage;

  // 查询 redemption_log，JOIN coupons / deals / users 获取完整信息
  // 只查询 action='redeem' 的记录作为核销历史主列表
  let query = supabase
    .from('redemption_log')
    .select(`
      id,
      action,
      created_at,
      coupon_id,
      coupons!inner (
        qr_code,
        reverted_at,
        deal_id,
        deals!inner (
          title
        ),
        users!coupons_user_id_fkey (
          full_name
        )
      )
    `, { count: 'exact' })
    .eq('merchant_id', merchantId)
    .eq('action', 'redeem')
    .order('created_at', { ascending: false })
    .range(offset, offset + perPage - 1);

  // 日期筛选
  if (dateFrom) {
    query = query.gte('created_at', `${dateFrom}T00:00:00.000Z`);
  }
  if (dateTo) {
    query = query.lte('created_at', `${dateTo}T23:59:59.999Z`);
  }

  // Deal 筛选（通过 coupons.deal_id 过滤）
  if (dealId) {
    query = query.eq('coupons.deal_id', dealId);
  }

  const { data: logs, error, count } = await query;

  if (error) {
    console.error('history query error:', error);
    return errorResponse('server_error', 'Failed to fetch redemption history', undefined, 500);
  }

  // 格式化返回数据
  // deno-lint-ignore no-explicit-any
  const records = (logs ?? []).map((log: any) => {
    const coupon = log.coupons;
    const deal = coupon?.deals;
    const userData = coupon?.users;
    return {
      id: log.id,
      coupon_id: log.coupon_id,
      coupon_code: coupon?.qr_code ?? '',
      deal_title: deal?.title ?? 'Unknown Deal',
      user_name: maskUserName(userData?.full_name ?? null),
      redeemed_at: log.created_at,
      is_reverted: coupon?.reverted_at != null,
      reverted_at: coupon?.reverted_at ?? null,
    };
  });

  const total = count ?? 0;

  return jsonResponse({
    data: records,
    total,
    page,
    per_page: perPage,
    has_more: offset + perPage < total,
  });
}
