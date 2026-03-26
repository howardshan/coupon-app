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
import { resolveAuth } from '../_shared/auth.ts';

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

  // V2.6 高级分析 — 跨店对比（品牌管理员专用）
  if (subPath === '/cross-store' || subPath === '/cross-store/') {
    return await handleCrossStoreAnalysis(userClient, req.headers, url.searchParams);
  }

  // V2.6 AI 诊断建议
  if (subPath === '/diagnostics' || subPath === '/diagnostics/') {
    return await handleDiagnostics(userClient);
  }

  // V2.6 趋势预测
  if (subPath === '/trends' || subPath === '/trends/') {
    return await handleTrends(userClient, url.searchParams);
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
        redeem_revenue:    0,
        pending_revenue:   0,
        paid_revenue:      0,
      });
    }

    return jsonResponse({
      days_range:        days,
      views_count:       Number(row.views_count)       ?? 0,
      orders_count:      Number(row.orders_count)      ?? 0,
      redemptions_count: Number(row.redemptions_count) ?? 0,
      revenue:           Number(row.revenue)           ?? 0,
      redeem_revenue:    Number(row.redeem_revenue)    ?? 0,
      pending_revenue:   Number(row.pending_revenue)   ?? 0,
      paid_revenue:      Number(row.paid_revenue)      ?? 0,
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

// =============================================================
// V2.6 跨店对比分析（品牌管理员专用）
// GET /merchant-analytics/cross-store?days=30&metric=revenue
// =============================================================
async function handleCrossStoreAnalysis(
  client: ReturnType<typeof createClient>,
  headers: Headers,
  params: URLSearchParams,
): Promise<Response> {
  try {
    const { data: { user } } = await client.auth.getUser();
    if (!user) return errorResponse('unauthorized', 'Not authenticated', 401);

    const auth = await resolveAuth(client, user.id, headers);
    if (!auth.isBrandAdmin || !auth.brandId) {
      return errorResponse('forbidden', 'Brand admin access required', 403);
    }

    const days = parseInt(params.get('days') ?? '30', 10);
    const sinceDate = new Date();
    sinceDate.setDate(sinceDate.getDate() - days);

    // 获取品牌下所有门店
    const { data: stores } = await client
      .from('merchants')
      .select('id, name, address')
      .eq('brand_id', auth.brandId)
      .eq('status', 'approved');

    if (!stores || stores.length === 0) {
      return jsonResponse({ stores: [] });
    }

    const storeIds = stores.map((s: { id: string }) => s.id);

    // 获取各门店在时间范围内的订单数据
    const { data: orders } = await client
      .from('orders')
      .select('merchant_id, total_amount, status, created_at')
      .in('merchant_id', storeIds)
      .gte('created_at', sinceDate.toISOString());

    // 获取各门店的评价数据
    const { data: reviews } = await client
      .from('reviews')
      .select('merchant_id, rating, created_at')
      .in('merchant_id', storeIds)
      .gte('created_at', sinceDate.toISOString());

    // 按门店聚合
    const storeStats = stores.map((store: { id: string; name: string; address: string }) => {
      const storeOrders = (orders ?? []).filter(
        (o: { merchant_id: string }) => o.merchant_id === store.id
      );
      const storeReviews = (reviews ?? []).filter(
        (r: { merchant_id: string }) => r.merchant_id === store.id
      );
      const completedOrders = storeOrders.filter(
        (o: { status: string }) => o.status === 'completed' || o.status === 'redeemed'
      );

      const revenue = completedOrders.reduce(
        (sum: number, o: { total_amount: number }) => sum + (o.total_amount ?? 0), 0
      );
      const avgRating = storeReviews.length > 0
        ? storeReviews.reduce((sum: number, r: { rating: number }) => sum + r.rating, 0) / storeReviews.length
        : 0;

      return {
        store_id: store.id,
        store_name: store.name,
        address: store.address,
        total_orders: storeOrders.length,
        completed_orders: completedOrders.length,
        revenue,
        review_count: storeReviews.length,
        avg_rating: Math.round(avgRating * 10) / 10,
        refund_count: storeOrders.filter(
          (o: { status: string }) => o.status === 'refunded'
        ).length,
      };
    });

    return jsonResponse({ stores: storeStats, days });
  } catch (err) {
    console.error('[handleCrossStoreAnalysis] Error:', err);
    return errorResponse('internal_error', 'Internal server error', 500);
  }
}

// =============================================================
// V2.6 AI 诊断建议
// GET /merchant-analytics/diagnostics
// 基于规则的经营建议（非 LLM，基于阈值判断）
// =============================================================
async function handleDiagnostics(
  client: ReturnType<typeof createClient>,
): Promise<Response> {
  try {
    const merchantId = await getCurrentMerchantId(client);
    if (!merchantId) {
      return errorResponse('merchant_not_found', 'Merchant account not found', 404);
    }

    const suggestions: { type: string; severity: string; title: string; description: string }[] = [];

    // 检查最近 30 天数据
    const since30d = new Date();
    since30d.setDate(since30d.getDate() - 30);

    // 获取订单和退款数据
    const { data: orders } = await client
      .from('orders')
      .select('status, total_amount, created_at')
      .eq('merchant_id', merchantId)
      .gte('created_at', since30d.toISOString());

    const totalOrders = orders?.length ?? 0;
    const refunds = (orders ?? []).filter((o: { status: string }) => o.status === 'refunded');
    const refundRate = totalOrders > 0 ? refunds.length / totalOrders : 0;

    // 获取评价数据
    const { data: reviews } = await client
      .from('reviews')
      .select('rating')
      .eq('merchant_id', merchantId)
      .gte('created_at', since30d.toISOString());

    const avgRating = (reviews ?? []).length > 0
      ? (reviews ?? []).reduce((s: number, r: { rating: number }) => s + r.rating, 0) / reviews!.length
      : 0;

    // 获取活跃 deal 数
    const { count: activeDeals } = await client
      .from('deals')
      .select('id', { count: 'exact', head: true })
      .eq('merchant_id', merchantId)
      .eq('is_active', true);

    // 规则引擎：生成建议
    if (refundRate > 0.15) {
      suggestions.push({
        type: 'refund',
        severity: 'high',
        title: 'High Refund Rate',
        description: `Your refund rate is ${(refundRate * 100).toFixed(1)}% (${refunds.length}/${totalOrders}). Consider improving deal descriptions and photos to set accurate customer expectations.`,
      });
    }

    if (avgRating > 0 && avgRating < 3.5) {
      suggestions.push({
        type: 'rating',
        severity: 'high',
        title: 'Low Customer Rating',
        description: `Average rating is ${avgRating.toFixed(1)}/5. Review negative feedback and address common complaints to improve satisfaction.`,
      });
    }

    if (totalOrders < 5) {
      suggestions.push({
        type: 'traffic',
        severity: 'medium',
        title: 'Low Order Volume',
        description: `Only ${totalOrders} orders in the last 30 days. Consider creating promotions or adjusting pricing to attract more customers.`,
      });
    }

    if ((activeDeals ?? 0) < 2) {
      suggestions.push({
        type: 'deals',
        severity: 'medium',
        title: 'Few Active Deals',
        description: `You have ${activeDeals ?? 0} active deals. Adding more variety can increase discoverability and sales.`,
      });
    }

    if ((reviews ?? []).length < 3) {
      suggestions.push({
        type: 'reviews',
        severity: 'low',
        title: 'Few Reviews',
        description: 'Encourage customers to leave reviews. Stores with more reviews rank higher in search results.',
      });
    }

    if (suggestions.length === 0) {
      suggestions.push({
        type: 'success',
        severity: 'low',
        title: 'Looking Good!',
        description: 'No issues detected. Keep up the great work!',
      });
    }

    return jsonResponse({
      diagnostics: suggestions,
      stats: {
        total_orders: totalOrders,
        refund_rate: Math.round(refundRate * 1000) / 10,
        avg_rating: Math.round(avgRating * 10) / 10,
        active_deals: activeDeals ?? 0,
        review_count: (reviews ?? []).length,
      },
    });
  } catch (err) {
    console.error('[handleDiagnostics] Error:', err);
    return errorResponse('internal_error', 'Internal server error', 500);
  }
}

// =============================================================
// V2.6 趋势预测
// GET /merchant-analytics/trends?days=90
// 计算收入/订单/评分的趋势线 + 简单预测
// =============================================================
async function handleTrends(
  client: ReturnType<typeof createClient>,
  params: URLSearchParams,
): Promise<Response> {
  try {
    const merchantId = await getCurrentMerchantId(client);
    if (!merchantId) {
      return errorResponse('merchant_not_found', 'Merchant account not found', 404);
    }

    const days = parseInt(params.get('days') ?? '90', 10);
    const sinceDate = new Date();
    sinceDate.setDate(sinceDate.getDate() - days);

    // 获取历史订单数据
    const { data: orders } = await client
      .from('orders')
      .select('total_amount, status, created_at')
      .eq('merchant_id', merchantId)
      .gte('created_at', sinceDate.toISOString())
      .order('created_at');

    // 按周聚合
    const weeklyData: Record<string, { revenue: number; orders: number; refunds: number }> = {};
    for (const order of (orders ?? [])) {
      const date = new Date(order.created_at);
      // 周一为一周开始
      const weekStart = new Date(date);
      weekStart.setDate(date.getDate() - date.getDay() + 1);
      const weekKey = weekStart.toISOString().split('T')[0];

      if (!weeklyData[weekKey]) {
        weeklyData[weekKey] = { revenue: 0, orders: 0, refunds: 0 };
      }
      weeklyData[weekKey].orders++;
      if (order.status === 'completed' || order.status === 'redeemed') {
        weeklyData[weekKey].revenue += order.total_amount ?? 0;
      }
      if (order.status === 'refunded') {
        weeklyData[weekKey].refunds++;
      }
    }

    // 转为排序数组
    const weeks = Object.entries(weeklyData)
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([week, data]) => ({ week, ...data }));

    // 简单线性趋势（最近3周 vs 前3周对比）
    const recentWeeks = weeks.slice(-3);
    const earlierWeeks = weeks.slice(-6, -3);

    const recentAvgRevenue = recentWeeks.length > 0
      ? recentWeeks.reduce((s, w) => s + w.revenue, 0) / recentWeeks.length
      : 0;
    const earlierAvgRevenue = earlierWeeks.length > 0
      ? earlierWeeks.reduce((s, w) => s + w.revenue, 0) / earlierWeeks.length
      : 0;

    const revenueTrend = earlierAvgRevenue > 0
      ? ((recentAvgRevenue - earlierAvgRevenue) / earlierAvgRevenue) * 100
      : 0;

    const recentAvgOrders = recentWeeks.length > 0
      ? recentWeeks.reduce((s, w) => s + w.orders, 0) / recentWeeks.length
      : 0;
    const earlierAvgOrders = earlierWeeks.length > 0
      ? earlierWeeks.reduce((s, w) => s + w.orders, 0) / earlierWeeks.length
      : 0;

    const ordersTrend = earlierAvgOrders > 0
      ? ((recentAvgOrders - earlierAvgOrders) / earlierAvgOrders) * 100
      : 0;

    return jsonResponse({
      weekly_data: weeks,
      trends: {
        revenue_change_pct: Math.round(revenueTrend * 10) / 10,
        orders_change_pct: Math.round(ordersTrend * 10) / 10,
        revenue_direction: revenueTrend > 5 ? 'up' : revenueTrend < -5 ? 'down' : 'stable',
        orders_direction: ordersTrend > 5 ? 'up' : ordersTrend < -5 ? 'down' : 'stable',
      },
      forecast: {
        next_week_revenue_est: Math.round(recentAvgRevenue * 1.0),
        next_week_orders_est: Math.round(recentAvgOrders),
      },
    });
  } catch (err) {
    console.error('[handleTrends] Error:', err);
    return errorResponse('internal_error', 'Internal server error', 500);
  }
}
