// =============================================================
// Edge Function: user-order-detail
// 用户端订单详情 V3：返回 order + items 列表，每个 item 含 coupon 信息
// 路由：GET /user-order-detail?order_id=xxx 或 POST body { order_id, access_token }
// 认证：优先从 body.access_token 取 JWT（网关可能不转发 Header），否则从 Authorization 取
// 兼容旧订单：没有 order_items 时从 orders 旧字段构建单条 item
// =============================================================

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
};

function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function errorResponse(message: string, code: string, status = 400): Response {
  return jsonResponse({ error: code, message }, status);
}

// 对 payment_intent_id 进行脱敏：保留最后 8 位，前面用 **** 替换
function maskPaymentIntentId(raw: string | null | undefined): string {
  if (!raw) return '';
  return raw.length > 8 ? '****' + raw.slice(-8) : raw;
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  if (!['GET', 'POST'].includes(req.method)) {
    return errorResponse('Method not allowed', 'method_not_allowed', 405);
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

  const url = new URL(req.url);
  let orderId = url.searchParams.get('order_id')?.trim() ?? null;

  // POST 时从 body 取 order_id 与 access_token（网关可能不转发 Authorization）
  let bodyToken = '';
  if (req.method === 'POST') {
    try {
      const body = (await req.json()) as { order_id?: string; access_token?: string };
      if (body.order_id != null) orderId = String(body.order_id).trim() || null;
      if (body.access_token != null) bodyToken = String(body.access_token).trim();
    } catch {
      // body 解析失败时保留 query 的 order_id
    }
  }

  const authHeader = req.headers.get('Authorization') ?? req.headers.get('authorization');
  const headerToken = authHeader?.replace(/^\s*Bearer\s+/i, '')?.trim() ?? '';
  const token = bodyToken || headerToken;

  if (!token) {
    return errorResponse('Missing authorization (header or body access_token)', 'unauthorized', 401);
  }

  // 验证 JWT，获取 userId
  const userClient = createClient(supabaseUrl, anonKey);
  const { data: claimsData, error: claimsError } = await userClient.auth.getClaims(token);
  if (claimsError || !claimsData?.claims?.sub) {
    return errorResponse('Invalid or expired token', 'unauthorized', 401);
  }
  const userId = claimsData.claims.sub as string;

  if (!orderId) {
    return errorResponse('Missing order_id', 'bad_request', 400);
  }

  // 使用 service_role 客户端查询（跳过 RLS，后面手动校验 user_id）
  const client = createClient(supabaseUrl, serviceRoleKey);

  // -------------------------------------------------------
  // Step 1: 查询 orders 表基本信息
  // -------------------------------------------------------
  const { data: order, error: orderError } = await client
    .from('orders')
    .select(`
      id,
      order_number,
      user_id,
      items_amount,
      service_fee_total,
      total_amount,
      payment_intent_id,
      paid_at,
      created_at,
      updated_at,
      deal_id,
      unit_price,
      quantity,
      status,
      refund_reason,
      refund_requested_at,
      refunded_at,
      refund_rejected_at,
      purchased_merchant_id
    `)
    .eq('id', orderId)
    .single();

  if (orderError || !order) {
    return errorResponse('Order not found', 'not_found', 404);
  }

  // 验证只能查自己的订单
  if ((order as { user_id: string }).user_id !== userId) {
    return errorResponse('Access denied', 'forbidden', 403);
  }

  // -------------------------------------------------------
  // Step 2: 查询 order_items + deals + merchants + coupons
  // -------------------------------------------------------
  const { data: rawItems } = await client
    .from('order_items')
    .select(`
      id,
      deal_id,
      coupon_id,
      unit_price,
      service_fee,
      customer_status,
      merchant_status,
      purchased_merchant_id,
      redeemed_merchant_id,
      redeemed_at,
      refunded_at,
      refund_reason,
      refund_amount,
      refund_method,
      selected_options,
      created_at,
      deals (
        id,
        title,
        image_urls
      ),
      coupons!order_items_coupon_id_fkey (
        id,
        qr_code,
        coupon_code,
        status,
        expires_at,
        purchased_merchant_id
      )
    `)
    .eq('order_id', orderId)
    .order('created_at', { ascending: true });

  // -------------------------------------------------------
  // Step 3: 查询商家名称（purchased_merchant + redeemed_merchant）
  //   先收集所有需要查的 merchant_id，批量查询后建 Map
  // -------------------------------------------------------
  const merchantIdSet = new Set<string>();

  // 订单级 purchased_merchant_id（旧订单兼容）
  if (order.purchased_merchant_id) {
    merchantIdSet.add(order.purchased_merchant_id);
  }

  // item 级的 purchased_merchant_id 和 redeemed_merchant_id
  if (rawItems && rawItems.length > 0) {
    for (const item of rawItems) {
      const typedItem = item as {
        purchased_merchant_id?: string | null;
        redeemed_merchant_id?: string | null;
        coupons?: { purchased_merchant_id?: string | null } | null;
      };
      if (typedItem.purchased_merchant_id) merchantIdSet.add(typedItem.purchased_merchant_id);
      if (typedItem.redeemed_merchant_id) merchantIdSet.add(typedItem.redeemed_merchant_id);
      if (typedItem.coupons?.purchased_merchant_id) {
        merchantIdSet.add(typedItem.coupons.purchased_merchant_id);
      }
    }
  }

  // 批量查询商家名称
  const merchantMap = new Map<string, string>();
  if (merchantIdSet.size > 0) {
    const { data: merchants } = await client
      .from('merchants')
      .select('id, name')
      .in('id', Array.from(merchantIdSet));

    if (merchants) {
      for (const m of merchants as { id: string; name: string }[]) {
        merchantMap.set(m.id, m.name);
      }
    }
  }

  // -------------------------------------------------------
  // Step 4: 构建 items 数组
  //   - V3 新订单：使用 order_items 数据
  //   - 旧订单兼容：order_items 为空时，从 orders 旧字段 + coupons 构建单条 item
  // -------------------------------------------------------
  type TimelineEvent = { event: string; timestamp: string | null; completed: boolean };
  type OrderItem = {
    id: string;
    dealId: string | null;
    dealTitle: string;
    dealImageUrl: string | null;
    unitPrice: number;
    serviceFee: number;
    customerStatus: string;
    merchantStatus: string;
    couponId: string | null;
    couponCode: string | null;
    couponQrCode: string | null;
    couponStatus: string | null;
    couponExpiresAt: string | null;
    purchasedMerchantId: string | null;
    purchasedMerchantName: string | null;
    redeemedAt: string | null;
    redeemedMerchantId: string | null;
    redeemedMerchantName: string | null;
    refundedAt: string | null;
    refundMethod: string | null;
    refundAmount: number | null;
    refundReason: string | null;
    selectedOptions: unknown;
  };

  let items: OrderItem[] = [];

  if (rawItems && rawItems.length > 0) {
    // V3 新订单：从 order_items 构建
    items = (rawItems as Array<{
      id: string;
      deal_id: string | null;
      coupon_id: string | null;
      unit_price: number;
      service_fee: number;
      customer_status: string;
      merchant_status: string;
      purchased_merchant_id: string | null;
      redeemed_merchant_id: string | null;
      redeemed_at: string | null;
      refunded_at: string | null;
      refund_reason: string | null;
      refund_amount: number | null;
      refund_method: string | null;
      selected_options: unknown;
      deals: {
        id: string;
        title: string;
        image_urls: string[] | null;
      } | null;
      coupons: {
        id: string;
        qr_code: string | null;
        coupon_code: string | null;
        status: string | null;
        expires_at: string | null;
        purchased_merchant_id: string | null;
      } | null;
    }>).map((item) => {
      const deal = item.deals;
      const coupon = item.coupons;

      // 优先从 coupon 取 purchased_merchant_id，再从 item 取
      const purchasedMerchantId =
        coupon?.purchased_merchant_id ?? item.purchased_merchant_id ?? null;
      const redeemedMerchantId = item.redeemed_merchant_id ?? null;

      return {
        id: item.id,
        dealId: item.deal_id,
        dealTitle: deal?.title ?? '',
        dealImageUrl:
          Array.isArray(deal?.image_urls) && deal.image_urls.length > 0
            ? deal.image_urls[0]
            : null,
        unitPrice: Number(item.unit_price ?? 0),
        serviceFee: Number(item.service_fee ?? 0),
        customerStatus: item.customer_status ?? 'unused',
        merchantStatus: item.merchant_status ?? 'unused',
        couponId: coupon?.id ?? item.coupon_id ?? null,
        couponCode: coupon?.coupon_code ?? null,
        couponQrCode: coupon?.qr_code ?? null,
        couponStatus: coupon?.status ?? null,
        couponExpiresAt: coupon?.expires_at ?? null,
        purchasedMerchantId,
        purchasedMerchantName: purchasedMerchantId
          ? (merchantMap.get(purchasedMerchantId) ?? null)
          : null,
        redeemedAt: item.redeemed_at ?? null,
        redeemedMerchantId,
        redeemedMerchantName: redeemedMerchantId
          ? (merchantMap.get(redeemedMerchantId) ?? null)
          : null,
        refundedAt: item.refunded_at ?? null,
        refundMethod: item.refund_method ?? null,
        refundAmount: item.refund_amount != null ? Number(item.refund_amount) : null,
        refundReason: item.refund_reason ?? null,
        selectedOptions: item.selected_options ?? null,
      };
    });
  } else {
    // 旧订单兼容：从 orders 旧字段构建单条 item
    // 查询旧 coupons（通过 order_id 关联）
    const { data: legacyCoupons } = await client
      .from('coupons')
      .select('id, qr_code, coupon_code, status, expires_at, purchased_merchant_id, used_at, redeemed_at')
      .eq('order_id', orderId)
      .limit(1);

    const legacyCoupon = legacyCoupons && legacyCoupons.length > 0
      ? (legacyCoupons[0] as {
          id: string;
          qr_code: string | null;
          coupon_code: string | null;
          status: string | null;
          expires_at: string | null;
          purchased_merchant_id: string | null;
          used_at: string | null;
          redeemed_at: string | null;
        })
      : null;

    // 查询旧 deal 信息（从 orders.deal_id 获取）
    let legacyDealTitle = '';
    let legacyDealImageUrl: string | null = null;

    if (order.deal_id) {
      const { data: legacyDeal } = await client
        .from('deals')
        .select('id, title, image_urls')
        .eq('id', order.deal_id)
        .single();

      if (legacyDeal) {
        const typedDeal = legacyDeal as { title: string; image_urls: string[] | null };
        legacyDealTitle = typedDeal.title ?? '';
        legacyDealImageUrl =
          Array.isArray(typedDeal.image_urls) && typedDeal.image_urls.length > 0
            ? typedDeal.image_urls[0]
            : null;
      }
    }

    // 将旧 order.status 映射为 customer_item_status
    const statusMap: Record<string, string> = {
      unused: 'unused',
      authorized: 'unused',
      used: 'used',
      refunded: 'refund_success',
      refund_requested: 'refund_pending',
      refund_pending_merchant: 'refund_review',
      refund_pending_admin: 'refund_review',
      refund_rejected: 'refund_reject',
      refund_failed: 'refund_reject',
      expired: 'refund_success',
      voided: 'refund_success',
    };
    const customerStatus = statusMap[order.status as string] ?? 'unused';
    const merchantStatus = order.status === 'used' ? 'unpaid' : 'unused';

    const purchasedMerchantId =
      legacyCoupon?.purchased_merchant_id ?? order.purchased_merchant_id ?? null;

    items = [
      {
        id: order.id, // 旧订单没有 item id，用 order id 代替
        dealId: order.deal_id ?? null,
        dealTitle: legacyDealTitle,
        dealImageUrl: legacyDealImageUrl,
        unitPrice: Number(order.unit_price ?? 0),
        serviceFee: 0,
        customerStatus,
        merchantStatus,
        couponId: legacyCoupon?.id ?? null,
        couponCode: legacyCoupon?.coupon_code ?? null,
        couponQrCode: legacyCoupon?.qr_code ?? null,
        couponStatus: legacyCoupon?.status ?? null,
        couponExpiresAt: legacyCoupon?.expires_at ?? null,
        purchasedMerchantId,
        purchasedMerchantName: purchasedMerchantId
          ? (merchantMap.get(purchasedMerchantId) ?? null)
          : null,
        redeemedAt: legacyCoupon?.redeemed_at ?? null,
        redeemedMerchantId: null,
        redeemedMerchantName: null,
        refundedAt: order.refunded_at ?? null,
        refundMethod: order.status === 'refunded' ? 'original_payment' : null,
        refundAmount:
          order.status === 'refunded' ? Number(order.total_amount ?? 0) : null,
        refundReason: order.refund_reason ?? null,
        selectedOptions: null,
      },
    ];
  }

  // -------------------------------------------------------
  // Step 5: 构建 timeline
  //   - 订单级：purchased 事件
  //   - Item 级：每个 item 的 redeemed / refunded 事件（去重合并）
  // -------------------------------------------------------
  const timeline: TimelineEvent[] = [
    {
      event: 'purchased',
      timestamp: (order.paid_at as string | null) ?? (order.created_at as string | null),
      completed: true,
    },
  ];

  // 收集所有 redeemed 和 refunded 事件（可能有多个 item，取最早的时间）
  const redeemedTimestamps: string[] = [];
  const refundedTimestamps: string[] = [];

  for (const item of items) {
    if (item.redeemedAt) redeemedTimestamps.push(item.redeemedAt);
    if (item.refundedAt) refundedTimestamps.push(item.refundedAt);
  }

  // 兼容旧订单：从 orders 字段补充事件
  if (redeemedTimestamps.length === 0 && order.status === 'used') {
    // 旧订单已使用但没有 redeemed_at，用 updated_at 代替
    redeemedTimestamps.push(order.updated_at as string);
  }

  if (redeemedTimestamps.length > 0) {
    // 取最早的 redeemed 时间作为代表
    const earliestRedeemed = redeemedTimestamps.sort()[0];
    timeline.push({
      event: 'redeemed',
      timestamp: earliestRedeemed,
      completed: true,
    });
  }

  // refund_requested 事件（订单级字段）
  if (order.refund_requested_at) {
    timeline.push({
      event: 'refund_requested',
      timestamp: order.refund_requested_at as string,
      completed: true,
    });
  }

  // refunded 事件
  if (refundedTimestamps.length > 0) {
    const earliestRefunded = refundedTimestamps.sort()[0];
    timeline.push({
      event: 'refunded',
      timestamp: earliestRefunded,
      completed: true,
    });
  } else if (order.refunded_at) {
    // 兼容旧订单：从 orders 字段获取
    timeline.push({
      event: 'refunded',
      timestamp: order.refunded_at as string,
      completed: true,
    });
  }

  // -------------------------------------------------------
  // Step 6: 组装最终响应
  // -------------------------------------------------------
  return jsonResponse({
    order: {
      id: order.id,
      orderNumber: order.order_number ?? null,
      userId: order.user_id,
      itemsAmount: order.items_amount != null ? Number(order.items_amount) : Number(order.total_amount ?? 0),
      serviceFeeTotal: Number(order.service_fee_total ?? 0),
      totalAmount: Number(order.total_amount ?? 0),
      paymentIntentId: maskPaymentIntentId(order.payment_intent_id as string | null),
      paidAt: (order.paid_at as string | null) ?? null,
      createdAt: order.created_at,
      items,
      timeline,
    },
  });
});
