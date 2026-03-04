// =============================================================
// Edge Function: merchant-analytics
// 商家端数据分析 API
//
// 路由:
//   GET /merchant-analytics/overview?days=7|30 — 经营概览
//   GET /merchant-analytics/deal-funnel         — Deal 转化漏斗
//   GET /merchant-analytics/customers           — 客群分析
// =============================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// CORS 响应头（支持 Flutter App 跨域调用）
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
};

// 统一 JSON 响应工具函数
const jsonResponse = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });

// 错误响应工具函数
const errorResponse = (error: string, message: string, status = 400) =>
  jsonResponse({ error, message }, status);

// =============================================================
// Deno.serve 主入口
// =============================================================
Deno.serve(async (req: Request) => {
  // OPTIONS 预检请求直接返回
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  // 只允许 GET 方法
  if (req.method !== 'GET') {
    return errorResponse('method_not_allowed', 'Only GET is supported', 405);
  }

  // 从请求头获取 JWT，必须有认证信息
  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    return errorResponse('unauthorized', 'Missing Authorization header', 401);
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const supabaseKey = Deno.env.get('SUPABASE_ANON_KEY')!;

  // 创建用户级 Supabase 客户端（受 RLS 约束）
  const userClient = createClient(supabaseUrl, supabaseKey, {
    global: { headers: { Authorization: authHeader } },
  });

  // 解析 URL 路径
  const url     = new URL(req.url);
  const pathRaw = url.pathname;

  // 去掉函数名前缀，提取子路径
  const prefix  = '/merchant-analytics';
  const subPath = pathRaw.startsWith(prefix)
    ? pathRaw.slice(prefix.length) || '/'
    : '/';

  // =============================================================
  // 路由分发
  // =============================================================

  // GET /merchant-analytics/overview — 经营概览
  if (subPath === '/overview' || subPath === '/overview/') {
    return await handleGetOverview(userClient, url.searchParams);
  }

  // GET /merchant-analytics/deal-funnel — Deal 转化漏斗
  if (subPath === '/deal-funnel' || subPath === '/deal-funnel/') {
    return await handleGetDealFunnel(userClient);
  }

  // GET /merchant-analytics/customers — 客群分析
  if (subPath === '/customers' || subPath === '/customers/') {
    return await handleGetCustomers(userClient);
  }

  return errorResponse('not_found', 'Route not found', 404);
});

// =============================================================
// handleGetOverview — 经营概览
// Query params:
//   days int — 时间范围，支持 7 或 30（默认 7）
// 调用 DB 函数: get_merchant_overview(p_merchant_id, p_days_range)
// =============================================================
async function handleGetOverview(
  client: ReturnType<typeof createClient>,
  params: URLSearchParams,
): Promise<Response> {
  try {
    // 获取当前登录商家 ID
    const merchantId = await getCurrentMerchantId(client);
    if (!merchantId) {
      return errorResponse('merchant_not_found', 'Merchant account not found', 404);
    }

    // 解析并校验 days 参数
    const daysRaw = parseInt(params.get('days') ?? '7', 10);
    const days    = [7, 30].includes(daysRaw) ? daysRaw : 7;

    // 调用 DB 函数
    const { data, error } = await client.rpc('get_merchant_overview', {
      p_merchant_id: merchantId,
      p_days_range:  days,
    });

    if (error) {
      console.error('[handleGetOverview] RPC error:', error);
      return errorResponse('db_error', error.message, 500);
    }

    // RPC 返回数组，取第一行
    const row = Array.isArray(data) && data.length > 0
      ? (data[0] as Record<string, unknown>)
      : null;

    if (!row) {
      // 返回空数据（无订单时正常）
      return jsonResponse({
        days_range:        days,
        views_count:       0,
        orders_count:      0,
        redemptions_count: 0,
        revenue:           0,
      });
    }

    return jsonResponse({
      days_range:        days,
      views_count:       Number(row.views_count)       ?? 0,
      orders_count:      Number(row.orders_count)      ?? 0,
      redemptions_count: Number(row.redemptions_count) ?? 0,
      revenue:           Number(row.revenue)           ?? 0,
    });
  } catch (err) {
    console.error('[handleGetOverview] Unexpected error:', err);
    return errorResponse('internal_error', 'Internal server error', 500);
  }
}

// =============================================================
// handleGetDealFunnel — Deal 转化漏斗
// 调用 DB 函数: get_deal_funnel(p_merchant_id)
// =============================================================
async function handleGetDealFunnel(
  client: ReturnType<typeof createClient>,
): Promise<Response> {
  try {
    const merchantId = await getCurrentMerchantId(client);
    if (!merchantId) {
      return errorResponse('merchant_not_found', 'Merchant account not found', 404);
    }

    const { data, error } = await client.rpc('get_deal_funnel', {
      p_merchant_id: merchantId,
    });

    if (error) {
      console.error('[handleGetDealFunnel] RPC error:', error);
      return errorResponse('db_error', error.message, 500);
    }

    // 格式化返回数据
    const funnels = (data ?? []).map((row: Record<string, unknown>) => ({
      deal_id:                  row.deal_id,
      deal_title:               row.deal_title,
      views:                    Number(row.views)                    ?? 0,
      orders:                   Number(row.orders)                   ?? 0,
      redemptions:              Number(row.redemptions)              ?? 0,
      view_to_order_rate:       Number(row.view_to_order_rate)       ?? 0,
      order_to_redemption_rate: Number(row.order_to_redemption_rate) ?? 0,
    }));

    return jsonResponse({ data: funnels });
  } catch (err) {
    console.error('[handleGetDealFunnel] Unexpected error:', err);
    return errorResponse('internal_error', 'Internal server error', 500);
  }
}

// =============================================================
// handleGetCustomers — 客群分析
// 调用 DB 函数: get_customer_analysis(p_merchant_id)
// =============================================================
async function handleGetCustomers(
  client: ReturnType<typeof createClient>,
): Promise<Response> {
  try {
    const merchantId = await getCurrentMerchantId(client);
    if (!merchantId) {
      return errorResponse('merchant_not_found', 'Merchant account not found', 404);
    }

    const { data, error } = await client.rpc('get_customer_analysis', {
      p_merchant_id: merchantId,
    });

    if (error) {
      console.error('[handleGetCustomers] RPC error:', error);
      return errorResponse('db_error', error.message, 500);
    }

    // RPC 返回数组，取第一行
    const row = Array.isArray(data) && data.length > 0
      ? (data[0] as Record<string, unknown>)
      : null;

    if (!row) {
      return jsonResponse({
        new_customers_count:       0,
        returning_customers_count: 0,
        repeat_rate:               0,
      });
    }

    return jsonResponse({
      new_customers_count:       Number(row.new_customers_count)       ?? 0,
      returning_customers_count: Number(row.returning_customers_count) ?? 0,
      repeat_rate:               Number(row.repeat_rate)               ?? 0,
    });
  } catch (err) {
    console.error('[handleGetCustomers] Unexpected error:', err);
    return errorResponse('internal_error', 'Internal server error', 500);
  }
}

// =============================================================
// 工具函数: getCurrentMerchantId
// 从 auth.uid() 查询 merchants 表获取 merchant ID
// =============================================================
async function getCurrentMerchantId(
  client: ReturnType<typeof createClient>,
): Promise<string | null> {
  const { data: { user } } = await client.auth.getUser();
  if (!user) return null;

  const { data, error } = await client
    .from('merchants')
    .select('id')
    .eq('user_id', user.id)
    .maybeSingle();

  if (error || !data) return null;
  return (data as Record<string, unknown>).id as string;
}
