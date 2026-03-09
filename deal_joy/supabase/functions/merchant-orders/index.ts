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
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
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

  // 仅支持 GET
  if (req.method !== 'GET') {
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

  // 解析路径（Supabase 实际 pathname 为 /functions/v1/merchant-orders 或 /functions/v1/merchant-orders/export 或 /functions/v1/merchant-orders/:id）
  const url = new URL(req.url);
  const pathname = url.pathname;
  const match = pathname.match(/\/merchant-orders\/?(.*)$/);
  const suffix = match ? match[1].replace(/^\/|\/$/g, '') : '';
  const pathParts = suffix ? suffix.split('/') : [];
  const subPath = pathParts[0] ?? '';

  // ----------------------------------------------------------------
  // 路由分发
  // ----------------------------------------------------------------

  // 导出 CSV（必须在 :id 路由前检查，避免 "export" 被当作 uuid）
  if (subPath === 'export') {
    return await handleExport(serviceClient, merchantId, url.searchParams);
  }

  // 订单详情：优先用 query 参数 ?id= 兜底（避免 path 被截断导致 404）
  const orderIdFromQuery = url.searchParams.get('id');
  if (orderIdFromQuery?.trim()) {
    return await handleDetail(serviceClient, merchantId, orderIdFromQuery.trim());
  }

  // 订单详情（subPath 是 UUID，path 形式）
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
  console.log('[merchant-orders] handleDetail', { orderId, merchantId });
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
      refund_rejected_at,
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
      coupons!coupons_order_id_fkey (
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
    // 将真实错误写入 Edge Function 日志，便于排查 404 原因
    if (orderError) {
      console.error('[merchant-orders] handleDetail order fetch failed', {
        orderId,
        code: orderError.code,
        message: orderError.message,
        details: orderError.details,
      });
    }
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
      refund_rejected_at: order.refund_rejected_at ?? null,
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
