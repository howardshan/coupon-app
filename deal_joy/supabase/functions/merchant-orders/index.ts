// =============================================================
// Edge Function: merchant-orders
// 路由：
//   GET /merchant-orders          — 分页订单列表（支持 status/date/deal 筛选）
//   GET /merchant-orders/export   — 导出 CSV
//   GET /merchant-orders/:id      — 单个订单详情（含完整时间线）
// 认证：Bearer JWT（merchant 用户，通过 auth.uid() 关联 merchants 表）
// =============================================================

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { resolveAuth, requirePermission } from "../_shared/auth.ts";

// CORS headers
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-merchant-id',
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

  // 用 user JWT 鉴权：验证 merchant 身份
  const authHeader = req.headers.get('Authorization');
  if (!authHeader?.startsWith('Bearer ')) {
    return errorResponse('Missing authorization header', 'unauthorized', 401);
  }
  const userJwt = authHeader.replace('Bearer ', '');

  // 用 user JWT 初始化客户端，用于鉴权校验
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: `Bearer ${userJwt}` } },
  });

  // 验证 JWT 合法性并获取 user
  const { data: { user }, error: userError } = await userClient.auth.getUser();
  if (userError || !user) {
    return errorResponse('Invalid or expired token', 'unauthorized', 401);
  }

  // 统一鉴权
  const serviceClient = createClient(supabaseUrl, serviceRoleKey);
  let auth;
  try {
    auth = await resolveAuth(serviceClient, user.id, req.headers);
  } catch (e) {
    return errorResponse((e as Error).message, 'unauthorized', 403);
  }
  requirePermission(auth, 'orders');

  const merchantId = auth.merchantId;

  // 解析路径
  const url = new URL(req.url);
  // 路径示例：/merchant-orders、/merchant-orders/export、/merchant-orders/:id
  const pathParts = url.pathname.replace(/^\/merchant-orders\/?/, '').split('/').filter(Boolean);
  const subPath = pathParts[0] ?? '';

  // ----------------------------------------------------------------
  // 路由分发
  // ----------------------------------------------------------------

  // 导出 CSV（必须在 :id 路由前检查，避免 "export" 被当作 uuid）
  if (subPath === 'export') {
    return await handleExport(serviceClient, merchantId, url.searchParams);
  }

  // V2.7 订单转移
  if (subPath === 'transfers') {
    const transferId = pathParts[1] ?? '';
    return await handleOrderTransfers(req, serviceClient, auth, transferId);
  }

  // 订单详情（subPath 是 UUID）
  if (subPath && subPath !== '') {
    return await handleDetail(serviceClient, merchantId, subPath);
  }

  // 订单列表（默认）
  return await handleList(serviceClient, merchantId, url.searchParams);
});

// =============================================================
// handleList — 分页订单列表
// =============================================================
async function handleList(
  client: ReturnType<typeof createClient>,
  merchantId: string,
  params: URLSearchParams,
): Promise<Response> {
  const status = params.get('status') ?? null;
  const dateFrom = params.get('date_from') ?? null;
  const dateTo = params.get('date_to') ?? null;
  const dealId = params.get('deal_id') ?? null;
  const page = Math.max(parseInt(params.get('page') ?? '1', 10), 1);
  const perPage = Math.min(Math.max(parseInt(params.get('per_page') ?? '20', 10), 1), 100);

  // 调用数据库函数 get_merchant_orders
  const { data, error } = await client.rpc('get_merchant_orders', {
    p_merchant_id: merchantId,
    p_status: status,
    p_date_from: dateFrom,
    p_date_to: dateTo,
    p_deal_id: dealId,
    p_page: page,
    p_per_page: perPage,
  });

  if (error) {
    console.error('get_merchant_orders error:', error);
    return errorResponse('Failed to fetch orders', 'server_error', 500);
  }

  const rows = (data ?? []) as Record<string, unknown>[];
  const totalCount = rows.length > 0 ? Number(rows[0].total_count) : 0;
  const hasMore = page * perPage < totalCount;

  // 移除 total_count 字段（不暴露给前端，通过 total 字段传递）
  const cleanRows = rows.map(({ total_count: _, ...rest }) => rest);

  return jsonResponse({
    data: cleanRows,
    total: totalCount,
    page,
    per_page: perPage,
    has_more: hasMore,
  });
}

// =============================================================
// handleDetail — 单个订单详情（含时间线）
// =============================================================
async function handleDetail(
  client: ReturnType<typeof createClient>,
  merchantId: string,
  orderId: string,
): Promise<Response> {
  // 查询订单（通过 deal → merchant 确认归属权）
  const { data: order, error: orderError } = await client
    .from('orders')
    .select(`
      id,
      order_number,
      deal_id,
      user_id,
      quantity,
      unit_price,
      total_amount,
      status,
      payment_intent_id,
      stripe_charge_id,
      refund_reason,
      created_at,
      updated_at,
      refund_requested_at,
      refunded_at,
      deals!inner (
        id,
        title,
        original_price,
        discount_price,
        merchant_id
      ),
      users!inner (
        full_name,
        email
      ),
      coupons (
        id,
        qr_code,
        status,
        used_at,
        redeemed_at,
        expires_at
      )
    `)
    .eq('id', orderId)
    .single();

  if (orderError || !order) {
    return errorResponse('Order not found', 'not_found', 404);
  }

  // 验证该订单属于当前商家
  const deal = order.deals as { merchant_id: string };
  if (deal.merchant_id !== merchantId) {
    return errorResponse('Access denied', 'forbidden', 403);
  }

  // 构造用户显示名（脱敏：只取 first name）
  const user = order.users as { full_name: string | null; email: string };
  const displayName = (user.full_name ?? 'Customer').split(' ')[0];

  // 查询 payments 表（支付详情）
  const { data: payment } = await client
    .from('payments')
    .select('payment_intent_id, status, amount, refund_amount, created_at')
    .eq('order_id', orderId)
    .maybeSingle();

  // 构造时间线事件列表
  const timeline: Array<{ event: string; timestamp: string | null; completed: boolean }> = [
    {
      event: 'purchased',
      timestamp: order.created_at,
      completed: true,
    },
  ];

  const coupon = Array.isArray(order.coupons)
    ? (order.coupons[0] ?? null)
    : order.coupons;

  if (coupon?.redeemed_at || order.status === 'used') {
    timeline.push({
      event: 'redeemed',
      timestamp: coupon?.redeemed_at ?? null,
      completed: true,
    });
  }

  if (order.status === 'refund_requested') {
    timeline.push({
      event: 'refund_requested',
      timestamp: order.refund_requested_at ?? null,
      completed: true,
    });
  }

  if (order.status === 'refunded') {
    // 添加退款申请节点（如果存在）
    if (order.refund_requested_at) {
      timeline.push({
        event: 'refund_requested',
        timestamp: order.refund_requested_at,
        completed: true,
      });
    }
    timeline.push({
      event: 'refunded',
      timestamp: order.refunded_at ?? null,
      completed: true,
    });
  }

  // 掩码处理 payment_intent_id（只显示后8位）
  const rawIntentId: string = order.payment_intent_id ?? '';
  const maskedIntentId = rawIntentId.length > 8
    ? '****' + rawIntentId.slice(-8)
    : rawIntentId;

  return jsonResponse({
    order: {
      id: order.id,
      order_number: order.order_number,
      status: order.status,
      // 用户信息（脱敏）
      user_display_name: displayName,
      // deal 信息
      deal_id: order.deal_id,
      deal_title: (order.deals as { title: string }).title,
      deal_original_price: (order.deals as { original_price: number }).original_price,
      deal_discount_price: (order.deals as { discount_price: number }).discount_price,
      // 支付信息
      quantity: order.quantity,
      unit_price: order.unit_price,
      total_amount: order.total_amount,
      payment_intent_id_masked: maskedIntentId,
      payment_status: payment?.status ?? null,
      refund_amount: payment?.refund_amount ?? null,
      // 退款信息
      refund_reason: order.refund_reason ?? null,
      // coupon 信息
      coupon_code: coupon?.qr_code ?? null,
      coupon_status: coupon?.status ?? null,
      coupon_expires_at: coupon?.expires_at ?? null,
      // 时间戳
      created_at: order.created_at,
      updated_at: order.updated_at,
      refund_requested_at: order.refund_requested_at ?? null,
      refunded_at: order.refunded_at ?? null,
      // 时间线
      timeline,
    },
  });
}

// =============================================================
// handleExport — 导出 CSV
// =============================================================
async function handleExport(
  client: ReturnType<typeof createClient>,
  merchantId: string,
  params: URLSearchParams,
): Promise<Response> {
  const status = params.get('status') ?? null;
  const dateFrom = params.get('date_from') ?? null;
  const dateTo = params.get('date_to') ?? null;
  const dealId = params.get('deal_id') ?? null;

  // 导出时拉取全部（最多 1000 条，防止超时）
  const { data, error } = await client.rpc('get_merchant_orders', {
    p_merchant_id: merchantId,
    p_status: status,
    p_date_from: dateFrom,
    p_date_to: dateTo,
    p_deal_id: dealId,
    p_page: 1,
    p_per_page: 1000,
  });

  if (error) {
    console.error('export error:', error);
    return errorResponse('Failed to export orders', 'server_error', 500);
  }

  const rows = (data ?? []) as Record<string, unknown>[];

  // 构造 CSV 内容
  const csvHeader = [
    'Order#',
    'Customer',
    'Deal',
    'Qty',
    'Amount (USD)',
    'Status',
    'Coupon Code',
    'Created Date',
    'Redeemed Date',
    'Refunded Date',
    'Refund Reason',
  ].join(',');

  const csvRows = rows.map((row) => {
    const cols = [
      row.order_number ?? '',
      row.user_display_name ?? '',
      `"${String(row.deal_title ?? '').replace(/"/g, '""')}"`,
      row.quantity ?? 1,
      Number(row.total_amount ?? 0).toFixed(2),
      row.status ?? '',
      row.coupon_code ?? '',
      row.created_at ? formatDate(row.created_at as string) : '',
      row.coupon_redeemed_at ? formatDate(row.coupon_redeemed_at as string) : '',
      row.refunded_at ? formatDate(row.refunded_at as string) : '',
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
