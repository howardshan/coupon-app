// =============================================================
// Edge Function: merchant-orders (V3 — order_items 维度)
// 路由：
//   GET/POST /merchant-orders     — 分页订单列表（每行 = 1 个 order_item）
//   GET /merchant-orders/export   — 导出 CSV（order_items 维度）
//   GET /merchant-orders/:id      — 订单详情（order 基本信息 + items 列表）
// 认证：Bearer JWT（merchant 用户，通过 auth.uid() 关联 merchants 表）
//
// V3 变更说明:
//   - handleList 改为 order_items 维度，每行是一张券
//   - 商家可见条件: purchased_merchant_id = 自己门店 OR applicable_store_ids @> [merchantId]
//   - handleDetail 返回 order 基本信息 + items 数组 + customer 信息
//   - 向后兼容：旧 orders 已通过 migration 迁移到 order_items
// =============================================================

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { resolveAuth, requirePermission } from "../_shared/auth.ts";

// CORS headers
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-merchant-id, x-app-bearer',
  'Access-Control-Allow-Methods': 'GET, POST, PATCH, OPTIONS',
};

// 统一 JSON 响应
function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

// 错误响应
function errorResponse(message: string, code: string, status = 400): Response {
  return jsonResponse({ error: code, message }, status);
}

// =============================================================
// 主入口
// =============================================================
serve(async (req: Request) => {
  // OPTIONS 预检
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  // 支持 GET / POST / PATCH
  if (!['GET', 'POST', 'PATCH'].includes(req.method)) {
    return errorResponse('Method not allowed', 'method_not_allowed', 405);
  }

  // 初始化 Supabase（使用 service_role 绕过 RLS，通过代码层面鉴权）
  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';

  // 解析 URL 与路径
  const url = new URL(req.url);
  const pathname = url.pathname;
  const match = pathname.match(/\/merchant-orders\/?(.*)$/);
  const suffix = match ? match[1].replace(/^\/|\/$/g, '') : '';
  const pathParts = suffix ? suffix.split('/') : [];
  const subPath = pathParts[0] ?? '';

  // 列表路由若为 POST：从 body 取 access_token 与分页参数（网关可能脱敏 query/header）
  let listBody: Record<string, unknown> | null = null;
  if (req.method === 'POST' && subPath === '') {
    listBody = await req.json().catch(() => ({})) as Record<string, unknown>;
  }
  const bodyToken = (listBody?.access_token != null ? String(listBody.access_token).trim() : '') || '';
  const queryToken = url.searchParams.get('access_token')?.trim() ?? '';
  const customToken = req.headers.get('x-app-bearer')?.trim() ?? '';
  const authHeader = req.headers.get('Authorization') ?? req.headers.get('authorization');
  const headerToken = authHeader?.replace(/^\s*Bearer\s+/i, '')?.trim() ?? '';
  const userJwt = bodyToken || queryToken || customToken || headerToken;

  if (!userJwt) {
    return errorResponse('Missing authorization (header, query access_token, or body access_token)', 'unauthorized', 401);
  }

  // 使用 getClaims(token) 校验 JWT 并取用户 id，不依赖请求头（网关可能不转发 Authorization）
  const userClient = createClient(supabaseUrl, anonKey);
  const { data: claimsData, error: claimsError } = await userClient.auth.getClaims(userJwt);
  if (claimsError || !claimsData?.claims?.sub) {
    console.error('[merchant-orders] getClaims failed', { error: claimsError?.message });
    return errorResponse('Invalid or expired token', 'unauthorized', 401);
  }
  const userId = claimsData.claims.sub as string;

  // 统一鉴权
  const serviceClient = createClient(supabaseUrl, serviceRoleKey);
  let auth;
  try {
    auth = await resolveAuth(serviceClient, userId, req.headers);
  } catch (e) {
    return errorResponse((e as Error).message, 'unauthorized', 403);
  }
  requirePermission(auth, 'orders');

  const merchantId = auth.merchantId;

  // ----------------------------------------------------------------
  // 路由分发
  // ----------------------------------------------------------------

  // 退款申请列表（GET /merchant-orders/refund-requests）
  if (subPath === 'refund-requests' && req.method === 'GET' && !pathParts[1]) {
    return await handleRefundRequestsList(serviceClient, merchantId, url.searchParams);
  }

  // 退款申请审批（PATCH /merchant-orders/refund-requests/:id）
  if (subPath === 'refund-requests' && req.method === 'PATCH' && pathParts[1]) {
    const refundRequestId = pathParts[1];
    const patchBody = await req.json().catch(() => ({}));
    return await handleRefundRequestDecision(
      serviceClient,
      merchantId,
      userId,
      refundRequestId,
      patchBody,
    );
  }

  // 导出 CSV（必须在 :id 路由前检查，避免 "export" 被当作 uuid）
  if (subPath === 'export') {
    return await handleExport(serviceClient, merchantId, url.searchParams);
  }

  // V2.7 订单转移
  if (subPath === 'transfers') {
    const transferId = pathParts[1] ?? '';
    return await handleOrderTransfers(req, serviceClient, auth, transferId);
  }

  // 订单详情（path 为 merchant-orders/:id 或 query 带 ?id=）
  // V3: :id 是 order_id，返回该 order 下属于当前商家的全部 items
  const detailIdFromPath = subPath && subPath !== '' ? subPath : null;
  const detailIdFromQuery = url.searchParams.get('id')?.trim() ?? null;
  const orderIdForDetail = detailIdFromPath || detailIdFromQuery;
  if (orderIdForDetail) {
    return await handleDetail(serviceClient, merchantId, orderIdForDetail);
  }

  // 订单列表（默认）：POST 时用 body 参数，GET 时用 query
  return await handleList(serviceClient, merchantId, listBody ?? url.searchParams);
});

// =============================================================
// 工具函数：统一取参数（兼容 URLSearchParams 和 body 对象）
// =============================================================
function getParam(
  params: URLSearchParams | Record<string, unknown>,
  key: string,
): string | null {
  if (params instanceof URLSearchParams) {
    return params.get(key) ?? null;
  }
  const v = params[key];
  if (v == null) return null;
  return String(v).trim() || null;
}

// =============================================================
// 工具函数：向后兼容 — 将旧 status 映射到 customer_item_status
// =============================================================
function mapLegacyStatusToCustomerStatus(status: string): string | null {
  const mapping: Record<string, string> = {
    'unused': 'unused',
    'used': 'used',
    'expired': 'expired',
    'refunded': 'refund_success',
    'refund_requested': 'refund_pending',
    'refund_pending_merchant': 'refund_review',
    'refund_pending_admin': 'refund_review',
    'refund_rejected': 'refund_reject',
    'refund_failed': 'refund_reject',
  };
  return mapping[status] ?? null;
}

// =============================================================
// handleList — V4: order 维度分页列表
// 查询 order_items 后在应用层按 order_id 分组，每行 = 1 个 order
// 只聚合属于当前商家的 items 金额与状态
// =============================================================
async function handleList(
  client: ReturnType<typeof createClient>,
  merchantId: string,
  params: URLSearchParams | Record<string, unknown>,
): Promise<Response> {
  // 解析筛选参数
  const customerStatus = getParam(params, 'customer_status');
  const merchantStatus = getParam(params, 'merchant_status');
  const status = getParam(params, 'status');
  // display_status：商家端组合状态筛选（优先级最高）
  const displayStatus = getParam(params, 'display_status');
  const dateFrom = getParam(params, 'date_from');
  const dateTo = getParam(params, 'date_to');
  const dealId = getParam(params, 'deal_id');
  const page = Math.max(parseInt(getParam(params, 'page') ?? '1', 10), 1);
  const perPage = Math.min(Math.max(parseInt(getParam(params, 'per_page') ?? '20', 10), 1), 100);
  const offset = (page - 1) * perPage;

  // 查询 order_items，获取属于当前商家的全部项
  let query = client
    .from('order_items')
    .select(`
      id,
      order_id,
      deal_id,
      unit_price,
      service_fee,
      customer_status,
      merchant_status,
      redeemed_at,
      refunded_at,
      refund_reason,
      created_at,
      orders!inner (
        id,
        order_number,
        created_at,
        paid_at,
        users!inner (
          full_name
        )
      ),
      deals!inner (
        id,
        title
      ),
      coupons!order_items_coupon_id_fkey (
        coupon_code,
        qr_code,
        status,
        expires_at
      )
    `)
    .or(`purchased_merchant_id.eq.${merchantId},applicable_store_ids.cs.{${merchantId}}`);

  // display_status 组合筛选（优先），映射 4 种商家端展示状态
  if (displayStatus) {
    switch (displayStatus) {
      case 'unused':
        // 待使用：用户尚未核销
        query = query.eq('customer_status', 'unused');
        break;
      case 'redeemed':
        // 已核销待结算：用户已使用，商家尚未收到结算
        query = query.eq('customer_status', 'used').eq('merchant_status', 'unpaid');
        break;
      case 'settled':
        // 已结算：商家已收到结算款
        query = query.eq('customer_status', 'used').eq('merchant_status', 'paid');
        break;
      case 'refunded':
        // 已退款：用户申请退款成功
        query = query.eq('customer_status', 'refund_success');
        break;
    }
  } else if (customerStatus) {
    query = query.eq('customer_status', customerStatus);
  } else if (merchantStatus) {
    query = query.eq('merchant_status', merchantStatus);
  } else if (status) {
    const mapped = mapLegacyStatusToCustomerStatus(status);
    if (mapped) {
      query = query.eq('customer_status', mapped);
    }
  }

  // 日期范围筛选
  if (dateFrom) {
    query = query.gte('created_at', dateFrom);
  }
  if (dateTo) {
    query = query.lte('created_at', dateTo + 'T23:59:59.999Z');
  }

  if (dealId) {
    query = query.eq('deal_id', dealId);
  }

  // 拉取全部匹配项（上限 2000），应用层按 order_id 分组分页
  const { data, error } = await query
    .order('created_at', { ascending: false })
    .limit(2000);

  if (error) {
    console.error('[merchant-orders] handleList error:', error);
    return errorResponse('Failed to fetch orders', 'server_error', 500);
  }

  const rows = (data ?? []) as Record<string, unknown>[];

  // 按 order_id 分组
  const orderMap = new Map<string, {
    orderId: string;
    orderNumber: string;
    userName: string;
    orderCreatedAt: string;
    paidAt: string | null;
    merchantTotal: number;
    items: Record<string, unknown>[];
    dealTitleSet: Set<string>;
    dealTitles: string[];
    primaryCouponExpiresAt: string | null;
  }>();

  for (const row of rows) {
    const orderId = row.order_id as string;

    if (!orderMap.has(orderId)) {
      const order = row.orders as Record<string, unknown> | null;
      const usersData = order?.users as Record<string, unknown> | null;
      const fullName = (usersData?.full_name as string | null) ?? 'Customer';

      orderMap.set(orderId, {
        orderId,
        orderNumber: (order?.order_number as string | null) ?? 'DJ-????????',
        userName: fullName.split(' ')[0],
        orderCreatedAt: (order?.created_at as string) ?? (row.created_at as string),
        paidAt: (order?.paid_at as string | null) ?? null,
        merchantTotal: 0,
        items: [],
        dealTitleSet: new Set(),
        dealTitles: [],
        primaryCouponExpiresAt: null,
      });
    }

    const group = orderMap.get(orderId)!;
    group.items.push(row);
    group.merchantTotal += (row.unit_price as number) ?? 0;

    // 收集 deal 标题（去重）
    const deal = row.deals as Record<string, unknown> | null;
    const title = (deal?.title as string) ?? '';
    if (title && !group.dealTitleSet.has(title)) {
      group.dealTitleSet.add(title);
      group.dealTitles.push(title);
    }

    // 收集 unused items 中最早的券过期时间（前端用来计算 expired / pending_refund）
    if (row.customer_status === 'unused') {
      const couponRaw = row.coupons as Record<string, unknown>[] | Record<string, unknown> | null;
      const coupon = Array.isArray(couponRaw) ? (couponRaw[0] ?? null) : couponRaw;
      const expiresAt = (coupon as Record<string, unknown> | null)?.expires_at as string | null;
      if (expiresAt && (!group.primaryCouponExpiresAt || expiresAt < group.primaryCouponExpiresAt)) {
        group.primaryCouponExpiresAt = expiresAt;
      }
    }
  }

  // 按 order 的 created_at DESC 排序
  const sortedOrders = Array.from(orderMap.values())
    .sort((a, b) => new Date(b.orderCreatedAt).getTime() - new Date(a.orderCreatedAt).getTime());

  const totalCount = sortedOrders.length;
  const pagedOrders = sortedOrders.slice(offset, offset + perPage);

  // 格式化输出
  const result = pagedOrders.map((group) => ({
    order_id: group.orderId,
    order_number: group.orderNumber,
    user_name: group.userName,
    merchant_total: Math.round(group.merchantTotal * 100) / 100,
    item_count: group.items.length,
    deal_titles: group.dealTitles,
    customer_status: computePrimaryStatus(group.items),
    // 商家端结算状态（用于商家视角的筛选与展示）
    merchant_status: computePrimaryMerchantStatus(group.items),
    coupon_expires_at: group.primaryCouponExpiresAt,
    created_at: group.orderCreatedAt,
    paid_at: group.paidAt,
  }));

  return jsonResponse({
    data: result,
    total: totalCount,
    page,
    per_page: perPage,
    has_more: page * perPage < totalCount,
  });
}

// 计算 order 下 items 的商家结算主状态（优先级：unpaid > unused > paid > refund_success）
function computePrimaryMerchantStatus(items: Record<string, unknown>[]): string {
  const priority: Record<string, number> = {
    'unpaid': 3,
    'unused': 2,
    'paid': 1,
    'refund_success': 0,
  };
  let maxP = -1;
  let primary = 'unused';
  for (const item of items) {
    const s = (item.merchant_status as string) ?? 'unused';
    const p = priority[s] ?? 0;
    if (p > maxP) { maxP = p; primary = s; }
  }
  return primary;
}

// 计算 order 下 items 的主状态（最需关注的状态优先）
function computePrimaryStatus(items: Record<string, unknown>[]): string {
  const priority: Record<string, number> = {
    'refund_review': 8,
    'refund_pending': 7,
    'refund_processing': 6,
    'refund_reject': 5,
    'unused': 4,
    'paid': 4,      // paid = 已付款未使用，与 unused 同级
    'gifted': 3,    // 已赠出，仍优先于已退款展示
    'used': 3,
    'refund_success': 1,
    'expired': 0,
  };
  let maxP = -1;
  let primary = 'unused';
  for (const item of items) {
    const s = (item.customer_status as string) ?? 'unused';
    const p = priority[s] ?? 0;
    if (p > maxP) { maxP = p; primary = s; }
  }
  return primary;
}

// 商家端脱敏：赠礼受赠邮箱
function maskRecipientEmail(email: string): string {
  const at = email.indexOf('@');
  if (at <= 0) return '***';
  const local = email.slice(0, at);
  const domain = email.slice(at + 1);
  const head = local.length > 0 ? local[0] : '?';
  return `${head}***@${domain}`;
}

/** 从 coupon_gifts 行构造时间线式事件（送出 / 收回） */
function buildMerchantGiftEvents(rows: unknown): Array<{
  kind: 'sent' | 'recalled';
  at: string;
  to_hint?: string | null;
}> {
  if (!Array.isArray(rows) || rows.length === 0) return [];
  const sorted = [...rows].sort(
    (a, b) =>
      new Date(String((a as Record<string, unknown>).created_at ?? 0)).getTime() -
      new Date(String((b as Record<string, unknown>).created_at ?? 0)).getTime(),
  );
  const out: Array<{ kind: 'sent' | 'recalled'; at: string; to_hint?: string | null }> = [];
  for (const raw of sorted) {
    const g = raw as Record<string, unknown>;
    const ca = g.created_at as string | null;
    if (ca) {
      const email = (g.recipient_email as string | null)?.trim();
      const uid = (g.recipient_user_id as string | null)?.trim();
      const giftType = (g.gift_type as string | null) ?? null;
      let hint: string | null = null;
      if (email && email.includes('@')) hint = maskRecipientEmail(email);
      else if (uid && uid.length > 8) hint = `User ${uid.slice(0, 8)}…`;
      else if (giftType === 'in_app') hint = 'Friend (in-app)';
      out.push({ kind: 'sent', at: ca, to_hint: hint });
    }
    const status = g.status as string | null;
    const ra = g.recalled_at as string | null;
    if (status === 'recalled' && ra) {
      out.push({ kind: 'recalled', at: ra });
    }
  }
  return out;
}

// =============================================================
// handleDetail — V3: 订单详情
// 入参 orderId 为 order UUID
// 返回:
//   order  — 订单基本信息（金额、单号、时间）+ 费用汇总
//   items  — 属于当前商家的 order_items 列表（含品牌佣金分解）
//   customer — 用户信息（脱敏）
// =============================================================
async function handleDetail(
  client: ReturnType<typeof createClient>,
  merchantId: string,
  orderId: string,
): Promise<Response> {
  console.log('[merchant-orders] handleDetail V3', { orderId, merchantId });

  // 同时查询：全局费率配置 + 商家专属费率（含品牌 brand_id）
  const [configRes, merchantRes] = await Promise.all([
    client
      .from('platform_commission_config')
      .select('commission_rate, stripe_processing_rate, stripe_flat_fee')
      .single(),
    client
      .from('merchants')
      .select('commission_free_until, commission_rate, commission_stripe_rate, commission_stripe_flat_fee, commission_effective_from, commission_effective_to, brand_id')
      .eq('id', merchantId)
      .single(),
  ]);

  // 解析全局费率
  const globalConfig = configRes.data;
  let vCommissionRate = parseFloat(String(globalConfig?.commission_rate ?? 0.15));
  let vStripeRate     = parseFloat(String(globalConfig?.stripe_processing_rate ?? 0.03));
  let vStripeFlatFee  = parseFloat(String(globalConfig?.stripe_flat_fee ?? 0.30));

  // 判断商家专属费率是否在生效期内，若是则覆盖全局
  const merchantData = merchantRes.data;
  if (merchantData?.commission_rate != null || merchantData?.commission_stripe_rate != null) {
    const today = new Date(); today.setHours(0, 0, 0, 0);
    const ef = merchantData.commission_effective_from ? new Date(merchantData.commission_effective_from) : null;
    const et = merchantData.commission_effective_to   ? new Date(merchantData.commission_effective_to)   : null;
    const active = (!ef && !et)
      || (ef && !et && today >= ef)
      || (!ef && et && today <= et)
      || (ef && et && today >= ef && today <= et);
    if (active) {
      if (merchantData.commission_rate        != null) vCommissionRate = parseFloat(String(merchantData.commission_rate));
      if (merchantData.commission_stripe_rate != null) vStripeRate     = parseFloat(String(merchantData.commission_stripe_rate));
      if (merchantData.commission_stripe_flat_fee != null) vStripeFlatFee = parseFloat(String(merchantData.commission_stripe_flat_fee));
    }
  }

  // 免费期内平台佣金为 0（品牌佣金不受免费期影响）
  const freeUntil = merchantData?.commission_free_until ? new Date(merchantData.commission_free_until) : null;
  const isInFreePeriod = freeUntil ? new Date() <= freeUntil : false;
  if (isInFreePeriod) {
    vCommissionRate = 0;
  }

  // 查询品牌佣金率（通过 merchants.brand_id → brands.commission_rate）
  let brandCommissionRate = 0;
  const brandId = merchantData?.brand_id ?? null;
  if (brandId) {
    const { data: brandData } = await client
      .from('brands')
      .select('commission_rate')
      .eq('id', brandId)
      .maybeSingle();
    if (brandData?.commission_rate != null) {
      brandCommissionRate = parseFloat(String(brandData.commission_rate));
    }
  }

  // 查询 order 基本信息 + 用户信息（含退款申请时间用于 timeline）
  const { data: order, error: orderError } = await client
    .from('orders')
    .select(`
      id,
      order_number,
      total_amount,
      service_fee_total,
      items_amount,
      store_credit_used,
      paid_at,
      created_at,
      updated_at,
      refund_requested_at,
      users!inner (
        full_name,
        email
      )
    `)
    .eq('id', orderId)
    .maybeSingle();

  if (orderError) {
    console.error('[merchant-orders] handleDetail order fetch error', {
      orderId,
      code: orderError.code,
      message: orderError.message,
    });
    return errorResponse('Order not found', 'not_found', 404);
  }

  if (!order) {
    return errorResponse('Order not found', 'not_found', 404);
  }

  // 查询该 order 下属于当前商家的 order_items
  const { data: itemRows, error: itemsError } = await client
    .from('order_items')
    .select(`
      id,
      deal_id,
      coupon_id,
      unit_price,
      service_fee,
      purchased_merchant_id,
      applicable_store_ids,
      redeemed_merchant_id,
      redeemed_at,
      redeemed_by,
      refunded_at,
      refund_reason,
      refund_amount,
      refund_method,
      customer_status,
      merchant_status,
      created_at,
      updated_at,
      deals!inner (
        id,
        title,
        original_price,
        discount_price,
        tips_enabled,
        tips_mode,
        tips_preset_1,
        tips_preset_2,
        tips_preset_3
      ),
      coupons!order_items_coupon_id_fkey (
        id,
        qr_code,
        coupon_code,
        status,
        expires_at,
        redeemed_at,
        used_at
      ),
      coupon_gifts (
        id,
        status,
        gift_type,
        created_at,
        recalled_at,
        recipient_email,
        recipient_user_id
      )
    `)
    .eq('order_id', orderId)
    // 仅返回属于该商家的 items（购买门店 = 我 OR 适用门店包含我）
    .or(`purchased_merchant_id.eq.${merchantId},applicable_store_ids.cs.{${merchantId}}`);

  if (itemsError) {
    console.error('[merchant-orders] handleDetail items fetch error', itemsError);
    return errorResponse('Failed to fetch order items', 'server_error', 500);
  }

  const items = itemRows ?? [];

  // 如果没有任何属于该商家的 items，拒绝访问
  if (items.length === 0) {
    return errorResponse('Access denied or order not found', 'forbidden', 403);
  }

  // 构造用户显示信息（脱敏：只显示 first name）
  const usersData = order.users as Record<string, unknown> | null;
  const fullName = (usersData?.full_name as string | null) ?? 'Customer';
  const customerName = fullName.split(' ')[0];

  // 格式化 items 列表（含品牌佣金分解）；金额汇总在下方基于 formattedItems 的 reduce（避免重复声明 merchantItemsAmount）
  const formattedItems = items.map((row) => {
    const deal = row.deals as Record<string, unknown> | null;
    const couponArr = row.coupons as Record<string, unknown>[] | Record<string, unknown> | null;
    const coupon = Array.isArray(couponArr) ? (couponArr[0] ?? null) : couponArr;

    // 计算每个 item 的费用明细
    const unitPrice  = parseFloat(String((row.unit_price as number) ?? 0));
    const platformFee = Math.round(unitPrice * vCommissionRate * 100) / 100;
    const brandFee    = Math.round(unitPrice * brandCommissionRate * 100) / 100;
    const stripeFee   = Math.round((unitPrice * vStripeRate + vStripeFlatFee) * 100) / 100;
    const netAmount   = Math.round((unitPrice - platformFee - brandFee - stripeFee) * 100) / 100;

    const customerSt = String(row.customer_status ?? "");
    const isRedeemed = row.redeemed_at != null || customerSt === "used" || customerSt === "redeemed";
    const tipsEnabled = Boolean(deal?.tips_enabled);
    const tipsMode = (deal?.tips_mode as string | null) ?? null;
    const tipsPreset1 = deal?.tips_preset_1 ?? null;
    const tipsPreset2 = deal?.tips_preset_2 ?? null;
    const tipsPreset3 = deal?.tips_preset_3 ?? null;
    let tipBaseCents = Math.round(unitPrice * 100);
    if (tipBaseCents <= 0) {
      tipBaseCents = Math.round(parseFloat(String(deal?.discount_price ?? 0)) * 100);
    }

    return {
      id: row.id,
      deal_id: row.deal_id,
      deal_title: deal?.title ?? null,
      deal_original_price: deal?.original_price ?? null,
      deal_discount_price: deal?.discount_price ?? null,
      unit_price: row.unit_price,
      service_fee: row.service_fee,
      // 费用分解
      platform_fee_rate: vCommissionRate,
      platform_fee:      platformFee,
      brand_fee_rate:    brandCommissionRate,
      brand_fee:         brandFee,
      stripe_fee:        stripeFee,
      net_amount:        netAmount,
      // V3 双状态
      customer_status: row.customer_status,
      merchant_status: row.merchant_status,
      // coupon 信息
      coupon_id: row.coupon_id,
      coupon_code: (coupon?.coupon_code ?? coupon?.qr_code) as string | null ?? null,
      coupon_status: coupon?.status ?? null,
      coupon_expires_at: coupon?.expires_at ?? null,
      // 核销信息
      redeemed_at: row.redeemed_at,
      redeemed_merchant_id: row.redeemed_merchant_id,
      // 退款信息
      refunded_at: row.refunded_at,
      refund_method: row.refund_method,
      refund_amount: row.refund_amount,
      refund_reason: row.refund_reason,
      // 赠礼 / 收回（coupon_gifts 多段历史，邮箱脱敏）
      gift_events: buildMerchantGiftEvents(row.coupon_gifts),
      // 时间戳
      created_at: row.created_at,
      updated_at: row.updated_at,
      // 小费：第二遍根据 coupon_tips 写入 tip / can_collect_tip（与 merchant-scan redeem 口径一致）
      _tip_collect_meta: {
        isRedeemed,
        tipsEnabled,
        tipsMode,
        tipsPreset1,
        tipsPreset2,
        tipsPreset3,
        tipBaseCents,
        refunded: Boolean(row.refunded_at),
      },
    };
  });

  const tipCouponIds = formattedItems
    .map((it) => it.coupon_id as string | null)
    .filter((id): id is string => typeof id === "string" && id.length > 0);

  /** coupon_id → paid 展示用 payload；以及 pending/paid 用于屏蔽重复收小费 */
  const tipPaidMap = new Map<string, Record<string, unknown>>();
  const tipBlockingStatus = new Map<string, string>();
  if (tipCouponIds.length > 0) {
    const { data: allTipRows } = await client
      .from("coupon_tips")
      .select("coupon_id, amount_cents, currency, status, paid_at, stripe_payment_intent_id")
      .in("coupon_id", tipCouponIds);
    for (const tr of allTipRows ?? []) {
      const cid = tr.coupon_id as string;
      const st = String(tr.status ?? "");
      if (st === "paid") {
        tipPaidMap.set(cid, {
          amount_cents: tr.amount_cents,
          currency: tr.currency ?? "usd",
          paid_at: tr.paid_at,
          stripe_payment_intent_id: tr.stripe_payment_intent_id,
        });
        tipBlockingStatus.set(cid, "paid");
      } else if (st === "pending" && tipBlockingStatus.get(cid) !== "paid") {
        tipBlockingStatus.set(cid, "pending");
      }
    }
    for (let i = 0; i < formattedItems.length; i++) {
      const it = formattedItems[i] as Record<string, unknown>;
      const cid = it.coupon_id as string | null;
      it.tip = cid ? tipPaidMap.get(cid) ?? null : null;

      const meta = it._tip_collect_meta as {
        isRedeemed: boolean;
        tipsEnabled: boolean;
        tipsMode: string | null;
        tipsPreset1: unknown;
        tipsPreset2: unknown;
        tipsPreset3: unknown;
        tipBaseCents: number;
        refunded: boolean;
      };
      delete it._tip_collect_meta;

      const blocked = cid ? tipBlockingStatus.has(cid) : false;
      const canCollect = Boolean(
        cid &&
          meta.isRedeemed &&
          meta.tipsEnabled &&
          meta.tipBaseCents > 0 &&
          !blocked &&
          !meta.refunded,
      );
      it.can_collect_tip = canCollect;
      if (canCollect) {
        it.collect_tip_base_cents = meta.tipBaseCents;
        it.collect_tip_deal = {
          tips_enabled: true,
          tips_mode: meta.tipsMode,
          tips_preset_1: meta.tipsPreset1,
          tips_preset_2: meta.tipsPreset2,
          tips_preset_3: meta.tipsPreset3,
        };
      }
    }
  } else {
    for (const it of formattedItems) {
      const rec = it as Record<string, unknown>;
      delete rec._tip_collect_meta;
      rec.tip = null;
      rec.can_collect_tip = false;
    }
  }

  // 计算该商家在本订单中的金额汇总（仅统计属于该商家的 items）
  const merchantItemsAmount = formattedItems.reduce(
    (sum, item) => sum + ((item.unit_price as number) || 0), 0
  );
  const merchantServiceFee = formattedItems.reduce(
    (sum, item) => sum + ((item.service_fee as number) || 0), 0
  );
  const merchantTotal = merchantItemsAmount + merchantServiceFee;

  // 汇总订单级别的费用
  const totalPlatformFee = Math.round(formattedItems.reduce((s, i) => s + i.platform_fee, 0) * 100) / 100;
  const totalBrandFee    = Math.round(formattedItems.reduce((s, i) => s + i.brand_fee, 0) * 100) / 100;
  const totalStripeFee   = Math.round(formattedItems.reduce((s, i) => s + i.stripe_fee, 0) * 100) / 100;
  const totalNetAmount   = Math.round(formattedItems.reduce((s, i) => s + i.net_amount, 0) * 100) / 100;

  // 构造 timeline（从 order 和 items 数据推算各阶段时间）
  const timeline: Array<{ event: string; timestamp: string | null; completed: boolean }> = [];

  // 1. purchased：订单创建
  timeline.push({
    event: 'purchased',
    timestamp: (order.paid_at ?? order.created_at) as string | null,
    completed: true,
  });

  // 2. redeemed：任意一张券已核销
  const redeemedItem = items.find((i) => i.redeemed_at);
  if (redeemedItem) {
    timeline.push({
      event: 'redeemed',
      timestamp: redeemedItem.redeemed_at as string | null,
      completed: true,
    });
  }

  // 3. refund_requested：如果订单有退款申请时间
  const refundRequestedAt = (order as Record<string, unknown>).refund_requested_at as string | null ?? null;
  if (refundRequestedAt) {
    timeline.push({
      event: 'refund_requested',
      timestamp: refundRequestedAt,
      completed: true,
    });
  }

  // 4. refunded：任意一张券已退款
  const refundedItem = items.find((i) => i.refunded_at);
  if (refundedItem) {
    timeline.push({
      event: 'refunded',
      timestamp: refundedItem.refunded_at as string | null,
      completed: true,
    });
  }

  return jsonResponse({
    order: {
      id: order.id,
      order_number: order.order_number,
      total_amount: order.total_amount,           // 订单全局总额（含所有商家，仅供参考）
      merchant_items_amount: merchantItemsAmount, // 该商家的商品金额小计
      merchant_service_fee: merchantServiceFee,   // 该商家的手续费合计
      merchant_total: merchantTotal,              // 该商家的应收总额（展示用）
      service_fee_total: (order.service_fee_total as number | null) ?? 0,
      items_amount: (order.items_amount as number | null) ?? order.total_amount,
      store_credit_used: (order.store_credit_used as number | null) ?? 0,
      paid_at: order.paid_at,
      created_at: order.created_at,
      timeline,
      // 订单级别费用汇总（品牌佣金分解）
      total_platform_fee: totalPlatformFee,
      total_brand_fee:    totalBrandFee,
      total_stripe_fee:   totalStripeFee,
      total_net_amount:   totalNetAmount,
    },
    items: formattedItems,
    customer: {
      name: customerName,
      email: usersData?.email ?? null,
    },
  });
}

// =============================================================
// handleExport — V3: 导出 CSV（order_items 维度）
// =============================================================
async function handleExport(
  client: ReturnType<typeof createClient>,
  merchantId: string,
  params: URLSearchParams,
): Promise<Response> {
  const customerStatus = params.get('customer_status') ?? null;
  const merchantStatus = params.get('merchant_status') ?? null;
  const status = params.get('status') ?? null;  // 向后兼容
  const dateFrom = params.get('date_from') ?? null;
  const dateTo = params.get('date_to') ?? null;
  const dealId = params.get('deal_id') ?? null;

  // 构建查询（导出最多 1000 条，防止超时）
  let query = client
    .from('order_items')
    .select(`
      id,
      order_id,
      deal_id,
      unit_price,
      service_fee,
      customer_status,
      merchant_status,
      redeemed_at,
      refunded_at,
      refund_reason,
      refund_amount,
      refund_method,
      created_at,
      orders!inner (
        order_number,
        total_amount,
        paid_at,
        users!inner (
          full_name
        )
      ),
      deals!inner (
        title
      ),
      coupons!order_items_coupon_id_fkey (
        coupon_code,
        qr_code,
        status,
        expires_at
      )
    `)
    .or(`purchased_merchant_id.eq.${merchantId},applicable_store_ids.cs.{${merchantId}}`);

  // 状态筛选
  if (customerStatus) {
    query = query.eq('customer_status', customerStatus);
  } else if (merchantStatus) {
    query = query.eq('merchant_status', merchantStatus);
  } else if (status) {
    const mapped = mapLegacyStatusToCustomerStatus(status);
    if (mapped) query = query.eq('customer_status', mapped);
  }

  // 日期范围筛选
  if (dateFrom) {
    query = query.gte('created_at', dateFrom);
  }
  if (dateTo) {
    query = query.lte('created_at', dateTo + 'T23:59:59.999Z');
  }
  if (dealId) {
    query = query.eq('deal_id', dealId);
  }

  const { data, error } = await query
    .order('created_at', { ascending: false })
    .limit(1000);

  if (error) {
    console.error('[merchant-orders] export error:', error);
    return errorResponse('Failed to export orders', 'server_error', 500);
  }

  const rows = (data ?? []) as Record<string, unknown>[];

  // 构造 CSV 内容（V3 字段）
  const csvHeader = [
    'Order#',
    'Item ID',
    'Customer',
    'Deal',
    'Unit Price (USD)',
    'Service Fee (USD)',
    'Customer Status',
    'Merchant Status',
    'Coupon Code',
    'Coupon Expires',
    'Purchased Date',
    'Redeemed Date',
    'Refunded Date',
    'Refund Method',
    'Refund Amount (USD)',
    'Refund Reason',
  ].join(',');

  const csvRows = rows.map((row) => {
    const order = row.orders as Record<string, unknown> | null;
    const deal = row.deals as Record<string, unknown> | null;
    const couponArr = row.coupons as Record<string, unknown>[] | Record<string, unknown> | null;
    const coupon = Array.isArray(couponArr) ? (couponArr[0] ?? null) : couponArr;
    const usersData = order?.users as Record<string, unknown> | null;
    const fullName = (usersData?.full_name as string | null) ?? 'Customer';
    const displayName = fullName.split(' ')[0];

    const cols = [
      order?.order_number ?? '',
      row.id ?? '',
      displayName,
      `"${String(deal?.title ?? '').replace(/"/g, '""')}"`,
      Number(row.unit_price ?? 0).toFixed(2),
      Number(row.service_fee ?? 0).toFixed(2),
      row.customer_status ?? '',
      row.merchant_status ?? '',
      (coupon?.coupon_code ?? coupon?.qr_code ?? '') as string,
      coupon?.expires_at ? formatDate(coupon.expires_at as string) : '',
      row.created_at ? formatDate(row.created_at as string) : '',
      row.redeemed_at ? formatDate(row.redeemed_at as string) : '',
      row.refunded_at ? formatDate(row.refunded_at as string) : '',
      row.refund_method ?? '',
      row.refund_amount != null ? Number(row.refund_amount).toFixed(2) : '',
      `"${String(row.refund_reason ?? '').replace(/"/g, '""')}"`,
    ];
    return cols.join(',');
  });

  const csvContent = [csvHeader, ...csvRows].join('\n');

  // 生成文件名：merchant_orders_YYYY-MM-DD.csv
  const dateStr = new Date().toISOString().slice(0, 10);
  const filename = `merchant_orders_${dateStr}.csv`;

  return new Response(csvContent, {
    status: 200,
    headers: {
      ...corsHeaders,
      'Content-Type': 'text/csv; charset=utf-8',
      'Content-Disposition': `attachment; filename="${filename}"`,
    },
  });
}

// =============================================================
// 工具函数：格式化时间戳为 YYYY-MM-DD HH:mm
// =============================================================
function formatDate(isoString: string): string {
  try {
    const d = new Date(isoString);
    const pad = (n: number) => String(n).padStart(2, '0');
    return `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())} ${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}`;
  } catch {
    return isoString;
  }
}

// =============================================================
// V2.7 订单转移
// GET  /merchant-orders/transfers — 获取转移记录
// POST /merchant-orders/transfers — 发起订单转移
// PATCH /merchant-orders/transfers/:id — 接受/拒绝转移
// =============================================================
async function handleOrderTransfers(
  req: Request,
  // deno-lint-ignore no-explicit-any
  client: any,
  // deno-lint-ignore no-explicit-any
  auth: any,
  transferId: string,
): Promise<Response> {
  const merchantId = auth.merchantId;

  switch (req.method) {
    case 'GET': {
      // 获取与当前门店相关的所有转移记录
      const { data, error } = await client
        .from('order_transfers')
        .select('*, orders(id, order_number, total_amount, status)')
        .or(`from_merchant_id.eq.${merchantId},to_merchant_id.eq.${merchantId}`)
        .order('created_at', { ascending: false })
        .limit(50);
      if (error) return errorResponse(error.message, 'db_error', 500);
      return jsonResponse({ transfers: data ?? [] });
    }

    case 'POST': {
      // 发起订单转移
      const body = await req.json().catch(() => ({}));
      if (!body.order_id || !body.to_merchant_id) {
        return errorResponse('order_id and to_merchant_id are required', 'validation_error', 400);
      }

      // 校验订单属于当前门店
      const { data: order } = await client
        .from('orders')
        .select('id, merchant_id, status')
        .eq('id', body.order_id)
        .eq('merchant_id', merchantId)
        .single();

      if (!order) {
        return errorResponse('Order not found or not yours', 'not_found', 404);
      }

      // 校验目标门店在同一品牌
      if (auth.brandId) {
        const { data: targetStore } = await client
          .from('merchants')
          .select('id, brand_id')
          .eq('id', body.to_merchant_id)
          .single();
        if (!targetStore || targetStore.brand_id !== auth.brandId) {
          return errorResponse('Target store not in your brand', 'forbidden', 403);
        }
      } else {
        return errorResponse('Order transfers require brand stores', 'forbidden', 403);
      }

      const { data: transfer, error } = await client
        .from('order_transfers')
        .insert({
          order_id: body.order_id,
          from_merchant_id: merchantId,
          to_merchant_id: body.to_merchant_id,
          reason: body.reason ?? '',
          transferred_by: auth.userId,
        })
        .select()
        .single();

      if (error) return errorResponse(error.message, 'db_error', 500);
      return jsonResponse({ transfer }, 201);
    }

    case 'PATCH': {
      // 接受或拒绝转移
      if (!transferId) return errorResponse('Missing transfer id', 'validation_error', 400);

      const body = await req.json().catch(() => ({}));
      const action = body.action; // 'accept' | 'reject'

      if (!['accept', 'reject'].includes(action)) {
        return errorResponse('action must be accept or reject', 'validation_error', 400);
      }

      // 校验转移记录存在且目标是当前门店
      const { data: existing } = await client
        .from('order_transfers')
        .select('id, order_id, to_merchant_id, status')
        .eq('id', transferId)
        .eq('to_merchant_id', merchantId)
        .eq('status', 'pending')
        .single();

      if (!existing) {
        return errorResponse('Transfer not found or already processed', 'not_found', 404);
      }

      const newStatus = action === 'accept' ? 'accepted' : 'rejected';

      // 更新转移记录
      const { error: updateErr } = await client
        .from('order_transfers')
        .update({
          status: newStatus,
          responded_by: auth.userId,
          responded_at: new Date().toISOString(),
        })
        .eq('id', transferId);

      if (updateErr) return errorResponse(updateErr.message, 'db_error', 500);

      // 如果接受，更新订单的 merchant_id
      if (action === 'accept') {
        await client
          .from('orders')
          .update({ merchant_id: merchantId })
          .eq('id', existing.order_id);
      }

      return jsonResponse({ success: true, status: newStatus });
    }

    default:
      return errorResponse('Method not allowed', 'method_not_allowed', 405);
  }
}

/** 券码仅暴露尾部若干位 */
function maskCouponTailRefund(code: string | null | undefined, tail = 4): string | null {
  const normalized = String(code ?? '').replace(/[^a-zA-Z0-9]/g, '').toUpperCase();
  if (!normalized.length) return null;
  if (normalized.length <= tail) return `…${normalized}`;
  return `…${normalized.slice(-tail)}`;
}

function maskNameRefund(name: string): string {
  if (!name) return 'User';
  if (name.length === 1) return `${name[0]}*`;
  return `${name[0]}***${name[name.length - 1]}`;
}

/** Deal 摘要（与 merchant-after-sales 一致） */
function truncateDealSummaryRefund(
  description: string | null | undefined,
  packageContents: string | null | undefined,
  max = 280,
): string | null {
  const parts = [description?.trim(), packageContents?.trim()].filter(Boolean) as string[];
  if (!parts.length) return null;
  const s = parts.join('\n\n');
  if (s.length <= max) return s;
  return `${s.slice(0, max - 1)}…`;
}

type OrderItemRefundEmbed = {
  id: string;
  redeemed_at: string | null;
  unit_price: number | string | null;
  selected_options: unknown;
  coupons: {
    coupon_code?: string | null;
    qr_code?: string | null;
    redeemed_at?: string | null;
    status?: string | null;
    expires_at?: string | null;
  } | null;
  deals: {
    id?: string;
    title?: string | null;
    description?: string | null;
    package_contents?: string | null;
  } | null;
};

function firstOrSelf<T>(v: T | T[] | null | undefined): T | null | undefined {
  if (v == null) return v;
  return Array.isArray(v) ? (v[0] as T) ?? null : v;
}

function buildRefundLineContext(oi: OrderItemRefundEmbed | undefined): Record<string, unknown> | null {
  if (!oi) return null;
  const cp = firstOrSelf(oi.coupons) ?? undefined;
  const deal = firstOrSelf(oi.deals) ?? undefined;
  const code = (cp?.coupon_code?.trim?.() || cp?.qr_code?.trim?.()) || null;
  const redeemed = oi.redeemed_at || cp?.redeemed_at || null;
  const dealSummary = deal
    ? truncateDealSummaryRefund(deal.description, deal.package_contents)
    : null;
  return {
    deal_id: deal?.id ?? null,
    deal_title: deal?.title ?? null,
    deal_summary: dealSummary,
    unit_price: oi.unit_price ?? null,
    selected_options: oi.selected_options ?? null,
    redeemed_at: redeemed,
    coupon_code_tail: maskCouponTailRefund(code),
    coupon_status: cp?.status ?? null,
    coupon_expires_at: cp?.expires_at ?? null,
  };
}

type OrdersRefundEmbed = {
  id?: string;
  order_number?: string | null;
  created_at?: string | null;
  paid_at?: string | null;
  deals?: unknown;
};

function buildRefundOrderContext(row: Record<string, unknown>): Record<string, unknown> | null {
  const orders = row.orders as OrdersRefundEmbed | null | undefined;
  if (!orders?.id) return null;
  const d = firstOrSelf(orders.deals as {
    id?: string;
    title?: string | null;
    description?: string | null;
    package_contents?: string | null;
  } | null) ?? undefined;
  return {
    order_id: orders.id,
    order_number: orders.order_number ?? null,
    order_created_at: orders.created_at ?? null,
    order_paid_at: orders.paid_at ?? null,
    deal_id: d?.id ?? null,
    deal_title: d?.title ?? null,
    deal_summary: d ? truncateDealSummaryRefund(d.description, d.package_contents) : null,
  };
}

async function batchRefundUserDisplayNames(
  client: ReturnType<typeof createClient>,
  rows: Record<string, unknown>[],
): Promise<Map<string, string>> {
  const out = new Map<string, string>();
  const userIds = [
    ...new Set(
      rows
        .map((r) => r.user_id as string | undefined)
        .filter((id): id is string => typeof id === 'string' && id.length > 0),
    ),
  ];
  if (!userIds.length) return out;
  const { data, error } = await client.from('users').select('id, full_name').in('id', userIds);
  if (error) {
    console.error('[merchant-orders] refund list users error:', error);
    return out;
  }
  for (const u of data ?? []) {
    const row = u as { id: string; full_name?: string | null };
    out.set(row.id, maskNameRefund(row.full_name ?? 'Anonymous'));
  }
  return out;
}

/** 按 order_item_id 批量拉取行级券/Deal/核销时间（无用户 PII） */
async function batchRefundLineContexts(
  client: ReturnType<typeof createClient>,
  rows: Record<string, unknown>[],
): Promise<Map<string, Record<string, unknown> | null>> {
  const out = new Map<string, Record<string, unknown> | null>();
  const oiIds = [
    ...new Set(
      rows
        .map((r) => r.order_item_id as string | undefined)
        .filter((id): id is string => typeof id === 'string' && id.length > 0),
    ),
  ];
  if (!oiIds.length) {
    for (const r of rows) out.set(String(r.id), null);
    return out;
  }
  const { data: items, error } = await client
    .from('order_items')
    .select(
      'id, redeemed_at, unit_price, selected_options, coupons(coupon_code, qr_code, status, redeemed_at, expires_at), deals(id, title, description, package_contents)',
    )
    .in('id', oiIds);
  if (error) {
    console.error('[merchant-orders] batch order_items for refunds error:', error);
    for (const r of rows) out.set(String(r.id), null);
    return out;
  }
  const byId = new Map<string, OrderItemRefundEmbed>();
  for (const raw of items ?? []) {
    const oi = raw as unknown as OrderItemRefundEmbed;
    byId.set(oi.id, oi);
  }
  for (const r of rows) {
    const oid = r.order_item_id as string | undefined;
    const ctx = oid ? buildRefundLineContext(byId.get(oid)) : null;
    out.set(String(r.id), ctx);
  }
  return out;
}

// =============================================================
// handleRefundRequestsList — 退款申请列表
// GET /merchant-orders/refund-requests?status=pending_merchant&page=1&per_page=20
// =============================================================
async function handleRefundRequestsList(
  client: ReturnType<typeof createClient>,
  merchantId: string,
  params: URLSearchParams,
): Promise<Response> {
  const statusFilter = params.get('status');
  const page = Math.max(parseInt(params.get('page') ?? '1', 10), 1);
  const perPage = Math.min(Math.max(parseInt(params.get('per_page') ?? '20', 10), 1), 100);
  const offset = (page - 1) * perPage;

  let query = client
    .from('refund_requests')
    .select(`
      id, status, refund_amount, reason, user_reason,
      merchant_reason, merchant_decided_at, merchant_decision,
      created_at, updated_at,
      user_id,
      order_item_id,
      orders!inner(
        id, order_number, total_amount, status, created_at, paid_at,
        deals!inner(id, title, description, package_contents)
      )
    `, { count: 'exact' })
    .eq('merchant_id', merchantId);

  if (statusFilter) {
    query = query.eq('status', statusFilter);
  }

  const { data, error, count } = await query
    .order('created_at', { ascending: false })
    .range(offset, offset + perPage - 1);

  if (error) {
    console.error('[merchant-orders] refund list error:', error);
    return jsonResponse({ error: 'db_error', message: 'Failed to fetch refund requests' }, 500);
  }

  const rawRows = (data ?? []) as Record<string, unknown>[];
  const lineCtxByRr = await batchRefundLineContexts(client, rawRows);
  const userDisplayMap = await batchRefundUserDisplayNames(client, rawRows);

  // 商家端 Flutter 仍读 merchant_response / responded_at；与 DB 列对齐；不返回 user_id
  const rows = rawRows.map((row: Record<string, unknown>) => {
    const rid = String(row.id);
    const uid = row.user_id as string | undefined;
    const { user_id: _omitUserId, ...rest } = row;
    return {
      ...rest,
      merchant_response: row.merchant_reason ?? null,
      responded_at: row.merchant_decided_at ?? null,
      refund_line_context: lineCtxByRr.get(rid) ?? null,
      refund_order_context: buildRefundOrderContext(row),
      user_display_name: uid ? userDisplayMap.get(uid) ?? 'User' : 'User',
    };
  });

  return jsonResponse({
    data: rows,
    total: count ?? 0,
    page,
    per_page: perPage,
    has_more: (count ?? 0) > offset + perPage,
  });
}

// =============================================================
// handleRefundRequestDecision — 审批退款申请
// PATCH /merchant-orders/refund-requests/:id
// body: { action: 'approve' | 'reject', reason?: string, access_token?: string }
// =============================================================
async function handleRefundRequestDecision(
  client: ReturnType<typeof createClient>,
  merchantId: string,
  actorUserId: string,
  refundRequestId: string,
  body: Record<string, unknown>,
): Promise<Response> {
  const { action, reason } = body as { action?: string; reason?: string };

  if (!action || !['approve', 'reject'].includes(action)) {
    return jsonResponse({ error: 'invalid_action', message: "action must be 'approve' or 'reject'" }, 400);
  }
  if (action === 'reject' && (!reason || reason.trim().length < 10)) {
    return jsonResponse({ error: 'invalid_reason', message: 'Rejection reason must be at least 10 characters' }, 400);
  }

  // 查询退款申请，确认属于该商家且状态为 pending_merchant
  const { data: refundReq, error: rrError } = await client
    .from('refund_requests')
    .select('id, status, order_id, merchant_id, order_item_id')
    .eq('id', refundRequestId)
    .single();

  if (rrError || !refundReq) {
    return jsonResponse({ error: 'not_found', message: 'Refund request not found' }, 404);
  }
  if (refundReq.merchant_id !== merchantId) {
    return jsonResponse({ error: 'forbidden', message: 'Access denied' }, 403);
  }
  if (refundReq.status !== 'pending_merchant') {
    return jsonResponse(
      { error: 'invalid_status', message: `Status is '${refundReq.status}', expected 'pending_merchant'` },
      400,
    );
  }

  const now = new Date().toISOString();
  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

  if (action === 'approve') {
    // 调用 execute-refund 执行实际 Stripe 退款
    const executeUrl = `${supabaseUrl}/functions/v1/execute-refund`;
    const executeResp = await fetch(executeUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${serviceRoleKey}`,
      },
      body: JSON.stringify({ refundRequestId, approvedBy: 'merchant' }),
    });

    if (!executeResp.ok) {
      const errBody = await executeResp.json().catch(() => ({}));
      const errMsg = (errBody as { error?: string }).error ?? 'Execute refund failed';
      return jsonResponse({ error: 'execute_failed', message: errMsg }, 502);
    }

    // 更新退款申请状态（execute-refund 内部也会更新，这里做幂等保障）
    await client
      .from('refund_requests')
      .update({
        status: 'approved_merchant',
        merchant_decision: 'approved',
        merchant_reason: reason?.trim() ?? null,
        merchant_decided_at: now,
        merchant_decided_by: actorUserId,
        updated_at: now,
      })
      .eq('id', refundRequestId);

    return jsonResponse({ success: true, status: 'approved_merchant' });
  } else {
    // 拒绝 → 升级到 pending_admin
    await client
      .from('refund_requests')
      .update({
        status: 'pending_admin',
        merchant_decision: 'rejected',
        merchant_reason: reason?.trim() ?? null,
        merchant_decided_at: now,
        merchant_decided_by: actorUserId,
        updated_at: now,
      })
      .eq('id', refundRequestId);

    // 单笔 order_item 争议：不修改整单 orders.status，避免多单订单被误标
    if (!refundReq.order_item_id) {
      await client
        .from('orders')
        .update({ status: 'refund_pending_admin', updated_at: now })
        .eq('id', refundReq.order_id);
    }

    return jsonResponse({ success: true, status: 'pending_admin' });
  }
}
