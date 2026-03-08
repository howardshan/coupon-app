// ============================================================
// merchant-dashboard Edge Function
// GET  /merchant-dashboard → 返回今日数据 + 7天趋势 + 待办 + 门店状态
// PATCH /merchant-dashboard → 更新门店 is_online 状态
// ============================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { resolveAuth, requirePermission } from "../_shared/auth.ts";

// CORS 响应头（允许商家端 App 跨域调用）
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-merchant-id',
  'Access-Control-Allow-Methods': 'GET, PATCH, OPTIONS',
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
    if (req.method === 'GET') {
      return await handleGet(serviceClient, merchantId, merchant);
    }

    if (req.method === 'PATCH') {
      return await handlePatch(serviceClient, supabase, merchantId, req);
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

  // 使用 user client 更新（RLS 策略: merchants_manage_own — user_id = auth.uid()）
  const { error: updateError } = await userClient
    .from('merchants')
    .update({ is_online: body.is_online, updated_at: new Date().toISOString() })
    .eq('id', merchantId);

  if (updateError) {
    console.error('[merchant-dashboard] update is_online error:', updateError);
    return errorResponse('Failed to update store status', 500);
  }

  return jsonResponse({
    success: true,
    isOnline: body.is_online,
    message: body.is_online ? 'Store is now online' : 'Store is now offline',
  });
}
