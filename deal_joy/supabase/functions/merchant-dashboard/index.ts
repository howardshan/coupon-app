// ============================================================
// merchant-dashboard Edge Function
// GET  /merchant-dashboard → 返回今日数据 + 7天趋势 + 待办 + 门店状态
// PATCH /merchant-dashboard → 更新门店 is_online 状态
// ============================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { resolveAuth, requirePermission } from "../_shared/auth.ts";
import { logMerchantActivity } from "../_shared/merchant_activity_log.ts";

// CORS 响应头（允许商家端 App 跨域调用）
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-merchant-id',
  'Access-Control-Allow-Methods': 'GET, PATCH, POST, OPTIONS',
};

// 统一 JSON 响应封装
function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

// 统一错误响应封装
function errorResponse(message: string, status = 400): Response {
  return jsonResponse({ error: message }, status);
}

Deno.serve(async (req: Request) => {
  // 处理 CORS 预检请求
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // --------------------------------------------------------
    // 1. 验证 JWT — 获取当前登录用户
    // --------------------------------------------------------
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return errorResponse('Missing authorization header', 401);
    }

    // 使用 anon key 创建 client（携带用户 JWT，RLS 生效）
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      {
        global: { headers: { Authorization: authHeader } },
        auth: { persistSession: false },
      },
    );

    // 使用 service role client 调用 SECURITY DEFINER 函数
    const serviceClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      { auth: { persistSession: false } },
    );

    // 获取当前用户 ID
    const { data: { user }, error: userError } = await supabase.auth.getUser();
    if (userError || !user) {
      return errorResponse('Unauthorized', 401);
    }

    // --------------------------------------------------------
    // 2. 统一鉴权
    // --------------------------------------------------------
    let auth;
    try {
      auth = await resolveAuth(serviceClient, user.id, req.headers);
    } catch (e) {
      return errorResponse((e as Error).message, 403);
    }
    requirePermission(auth, 'orders');

    const merchantId: string = auth.merchantId;

    // 查询商家详细信息（dashboard 展示需要）
    const { data: merchant, error: merchantError } = await serviceClient
      .from('merchants')
      .select('id, name, is_online, status')
      .eq('id', merchantId)
      .single();

    if (merchantError || !merchant) {
      return errorResponse('Merchant profile not found', 404);
    }

    // --------------------------------------------------------
    // 3. 根据 HTTP method 路由
    // --------------------------------------------------------
    // 解析 URL 路径
    const url = new URL(req.url);
    const pathParts = url.pathname.split('/').filter(Boolean);
    // pathParts[0] = 'merchant-dashboard', pathParts[1] = sub-route
    const subRoute = pathParts[1] ?? '';

    if (req.method === 'GET' && subRoute === 'brand-overview') {
      // V2.1 品牌总览 — 需要品牌管理员权限
      if (!auth.isBrandAdmin || !auth.brandId) {
        return errorResponse('Brand admin access required', 403);
      }
      return await handleBrandOverview(serviceClient, auth.brandId);
    }

    if (req.method === 'GET' && subRoute === 'brand-rankings') {
      // V2.1 门店排行
      if (!auth.isBrandAdmin || !auth.brandId) {
        return errorResponse('Brand admin access required', 403);
      }
      const sortBy = url.searchParams.get('sort_by') ?? 'revenue';
      const days = parseInt(url.searchParams.get('days') ?? '30', 10);
      return await handleBrandRankings(serviceClient, auth.brandId, sortBy, days);
    }

    if (req.method === 'GET' && subRoute === 'brand-health') {
      // V2.1 门店健康度
      if (!auth.isBrandAdmin || !auth.brandId) {
        return errorResponse('Brand admin access required', 403);
      }
      return await handleBrandHealth(serviceClient, auth.brandId);
    }

    if (req.method === 'GET') {
      return await handleGet(serviceClient, merchantId, merchant);
    }

    if (req.method === 'PATCH') {
      return await handlePatch(serviceClient, supabase, merchantId, req, user.id);
    }

    return errorResponse('Method not allowed', 405);
  } catch (err) {
    console.error('[merchant-dashboard] Unhandled error:', err);
    return errorResponse('Internal server error', 500);
  }
});

// ============================================================
// GET handler — 聚合返回所有 dashboard 数据
// ============================================================
async function handleGet(
  serviceClient: ReturnType<typeof createClient>,
  merchantId: string,
  merchant: { id: string; name: string; is_online: boolean; status: string },
): Promise<Response> {
  // 并行调用三个统计函数，减少总延迟
  const [dailyResult, trendResult, todosResult] = await Promise.all([
    serviceClient.rpc('get_merchant_daily_stats', { p_merchant_id: merchantId }),
    serviceClient.rpc('get_merchant_weekly_trend', { p_merchant_id: merchantId }),
    serviceClient.rpc('get_merchant_todos', { p_merchant_id: merchantId }),
  ]);

  // 检查每个调用的错误
  if (dailyResult.error) {
    console.error('[merchant-dashboard] daily stats error:', dailyResult.error);
    return errorResponse('Failed to fetch daily stats', 500);
  }
  if (trendResult.error) {
    console.error('[merchant-dashboard] weekly trend error:', trendResult.error);
    return errorResponse('Failed to fetch weekly trend', 500);
  }
  if (todosResult.error) {
    console.error('[merchant-dashboard] todos error:', todosResult.error);
    return errorResponse('Failed to fetch todos', 500);
  }

  // 解析今日数据（rpc 返回数组，取第一行）
  const dailyRow = dailyResult.data?.[0] ?? {
    today_orders: 0,
    today_redemptions: 0,
    today_revenue: 0,
    pending_coupons: 0,
  };

  // 解析待办数据（取第一行）
  const todosRow = todosResult.data?.[0] ?? {
    pending_reviews: 0,
    pending_refunds: 0,
    influencer_requests: 0,
  };

  // 解析 7 天趋势（数组，每天一行）
  const weeklyTrend = (trendResult.data ?? []).map((row: {
    trend_date: string;
    daily_orders: number;
    daily_revenue: number;
  }) => ({
    date: row.trend_date,
    orders: Number(row.daily_orders),
    revenue: Number(row.daily_revenue),
  }));

  // 构造响应
  const responseBody = {
    merchantId: merchant.id,
    merchantName: merchant.name,
    merchantStatus: merchant.status,
    isOnline: merchant.is_online,
    stats: {
      todayOrders: Number(dailyRow.today_orders),
      todayRedemptions: Number(dailyRow.today_redemptions),
      todayRevenue: Number(dailyRow.today_revenue),
      pendingCoupons: Number(dailyRow.pending_coupons),
    },
    weeklyTrend,
    todos: {
      pendingReviews: Number(todosRow.pending_reviews),
      pendingRefunds: Number(todosRow.pending_refunds),
      influencerRequests: Number(todosRow.influencer_requests),
    },
  };

  return jsonResponse(responseBody);
}

// ============================================================
// PATCH handler — 更新门店 is_online 状态
// ============================================================
async function handlePatch(
  serviceClient: ReturnType<typeof createClient>,
  userClient: ReturnType<typeof createClient>,
  merchantId: string,
  req: Request,
  actorUserId: string,
): Promise<Response> {
  // 解析请求体
  let body: { is_online?: boolean };
  try {
    body = await req.json();
  } catch {
    return errorResponse('Invalid JSON body');
  }

  if (typeof body.is_online !== 'boolean') {
    return errorResponse('is_online must be a boolean value');
  }

  const { data: beforeRow, error: beforeErr } = await serviceClient
    .from('merchants')
    .select('is_online')
    .eq('id', merchantId)
    .single();

  if (beforeErr) {
    console.error('[merchant-dashboard] read is_online before patch:', beforeErr);
  }

  // 使用 user client 更新（RLS 策略: merchants_manage_own — user_id = auth.uid()）
  const { error: updateError } = await userClient
    .from('merchants')
    .update({ is_online: body.is_online, updated_at: new Date().toISOString() })
    .eq('id', merchantId);

  if (updateError) {
    console.error('[merchant-dashboard] update is_online error:', updateError);
    return errorResponse('Failed to update store status', 500);
  }

  if (beforeRow && beforeRow.is_online !== body.is_online) {
    await logMerchantActivity(serviceClient, {
      merchant_id: merchantId,
      event_type: body.is_online ? 'store_online_merchant' : 'store_offline_merchant',
      actor_type: 'merchant_owner',
      actor_user_id: actorUserId,
    });
  }

  return jsonResponse({
    success: true,
    isOnline: body.is_online,
    message: body.is_online ? 'Store is now online' : 'Store is now offline',
  });
}

// ============================================================
// V2.1 品牌总览 — 汇总所有门店数据
// ============================================================
async function handleBrandOverview(
  serviceClient: ReturnType<typeof createClient>,
  brandId: string,
): Promise<Response> {
  // 并行调用品牌级统计 + 7天趋势
  const [dailyResult, trendResult] = await Promise.all([
    serviceClient.rpc('get_brand_daily_stats', { p_brand_id: brandId }),
    serviceClient.rpc('get_brand_weekly_trend', { p_brand_id: brandId }),
  ]);

  if (dailyResult.error) {
    console.error('[brand-overview] daily stats error:', dailyResult.error);
    return errorResponse('Failed to fetch brand daily stats', 500);
  }
  if (trendResult.error) {
    console.error('[brand-overview] weekly trend error:', trendResult.error);
    return errorResponse('Failed to fetch brand weekly trend', 500);
  }

  // 获取品牌信息
  const { data: brand } = await serviceClient
    .from('brands')
    .select('id, name, logo_url, description')
    .eq('id', brandId)
    .single();

  const dailyRow = dailyResult.data?.[0] ?? {
    total_stores: 0,
    online_stores: 0,
    today_orders: 0,
    today_redemptions: 0,
    today_revenue: 0,
    pending_coupons: 0,
  };

  const weeklyTrend = (trendResult.data ?? []).map((row: {
    trend_date: string;
    daily_orders: number;
    daily_revenue: number;
  }) => ({
    date: row.trend_date,
    orders: Number(row.daily_orders),
    revenue: Number(row.daily_revenue),
  }));

  return jsonResponse({
    brand: {
      id: brand?.id ?? brandId,
      name: brand?.name ?? '',
      logoUrl: brand?.logo_url ?? null,
      description: brand?.description ?? null,
    },
    stats: {
      totalStores: Number(dailyRow.total_stores),
      onlineStores: Number(dailyRow.online_stores),
      todayOrders: Number(dailyRow.today_orders),
      todayRedemptions: Number(dailyRow.today_redemptions),
      todayRevenue: Number(dailyRow.today_revenue),
      pendingCoupons: Number(dailyRow.pending_coupons),
    },
    weeklyTrend,
  });
}

// ============================================================
// V2.1 门店对比排行
// ============================================================
async function handleBrandRankings(
  serviceClient: ReturnType<typeof createClient>,
  brandId: string,
  sortBy: string,
  days: number,
): Promise<Response> {
  const { data, error } = await serviceClient.rpc('get_brand_store_rankings', {
    p_brand_id: brandId,
    p_sort_by: sortBy,
    p_days: days,
  });

  if (error) {
    console.error('[brand-rankings] error:', error);
    return errorResponse('Failed to fetch store rankings', 500);
  }

  const rankings = (data ?? []).map((row: {
    store_id: string;
    store_name: string;
    store_address: string;
    is_online: boolean;
    total_orders: number;
    total_revenue: number;
    total_redeemed: number;
    avg_rating: number;
    review_count: number;
    refund_rate: number;
  }) => ({
    storeId: row.store_id,
    storeName: row.store_name,
    storeAddress: row.store_address ?? '',
    isOnline: row.is_online,
    totalOrders: Number(row.total_orders),
    totalRevenue: Number(row.total_revenue),
    totalRedeemed: Number(row.total_redeemed),
    avgRating: Number(row.avg_rating),
    reviewCount: Number(row.review_count),
    refundRate: Number(row.refund_rate),
  }));

  return jsonResponse({ rankings, sortBy, days });
}

// ============================================================
// V2.1 门店健康度
// ============================================================
async function handleBrandHealth(
  serviceClient: ReturnType<typeof createClient>,
  brandId: string,
): Promise<Response> {
  const { data, error } = await serviceClient.rpc('get_brand_store_health', {
    p_brand_id: brandId,
  });

  if (error) {
    console.error('[brand-health] error:', error);
    return errorResponse('Failed to fetch store health', 500);
  }

  const alerts = (data ?? []).map((row: {
    store_id: string;
    store_name: string;
    alert_type: string;
    alert_message: string;
    alert_value: number;
  }) => ({
    storeId: row.store_id,
    storeName: row.store_name,
    alertType: row.alert_type,
    alertMessage: row.alert_message,
    alertValue: Number(row.alert_value),
  }));

  return jsonResponse({ alerts });
}
