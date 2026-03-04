// =============================================================
// Edge Function: merchant-reviews
// 商家端评价管理 API
//
// 路由:
//   GET  /merchant-reviews          — 分页评价列表（支持 rating 筛选）
//   POST /merchant-reviews/:id/reply — 提交商家回复（限1次）
//   GET  /merchant-reviews/stats    — 评价统计数据
// =============================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// CORS 响应头（支持 Flutter app 跨域调用）
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
};

// 统一 JSON 响应工具
const jsonResponse = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });

// 错误响应工具
const errorResponse = (error: string, message: string, status = 400) =>
  jsonResponse({ error, message }, status);

// =============================================================
// Deno.serve 入口
// =============================================================
Deno.serve(async (req: Request) => {
  // OPTIONS 预检请求
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  // 从请求头获取 JWT，创建用户级别 Supabase 客户端（触发 RLS）
  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    return errorResponse('unauthorized', 'Missing Authorization header', 401);
  }

  const supabaseUrl  = Deno.env.get('SUPABASE_URL')!;
  const supabaseKey  = Deno.env.get('SUPABASE_ANON_KEY')!;
  const serviceKey   = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

  // 用户客户端：受 RLS 约束
  const userClient = createClient(supabaseUrl, supabaseKey, {
    global: { headers: { Authorization: authHeader } },
  });

  // 服务端客户端：绕过 RLS（仅用于写 merchant_reply）
  const serviceClient = createClient(supabaseUrl, serviceKey);

  // 解析 URL 路径
  const url     = new URL(req.url);
  const pathRaw = url.pathname;

  // 去掉函数名前缀 /merchant-reviews → 纯路径
  // 在 Supabase Edge 中 pathname 通常为 /merchant-reviews 或 /merchant-reviews/stats 等
  const prefix    = '/merchant-reviews';
  const subPath   = pathRaw.startsWith(prefix)
    ? pathRaw.slice(prefix.length) || '/'
    : '/';

  // =============================================================
  // 路由分发
  // =============================================================

  // GET /merchant-reviews/stats — 评价统计
  if (req.method === 'GET' && subPath === '/stats') {
    return await handleGetStats(userClient);
  }

  // GET /merchant-reviews — 评价列表
  if (req.method === 'GET' && (subPath === '/' || subPath === '')) {
    return await handleListReviews(userClient, url.searchParams);
  }

  // POST /merchant-reviews/:id/reply — 提交回复
  const replyMatch = subPath.match(/^\/([^/]+)\/reply$/);
  if (req.method === 'POST' && replyMatch) {
    const reviewId = replyMatch[1];
    return await handlePostReply(userClient, serviceClient, reviewId, req);
  }

  return errorResponse('not_found', 'Route not found', 404);
});

// =============================================================
// handleListReviews — 分页评价列表
// Query params:
//   rating   int?   — 筛选星级 (1-5)
//   page     int    — 页码 (default 1)
//   per_page int    — 每页条数 (default 20)
// =============================================================
async function handleListReviews(
  client: ReturnType<typeof createClient>,
  params: URLSearchParams,
): Promise<Response> {
  try {
    // 获取当前登录商家 ID
    const merchantId = await getCurrentMerchantId(client);
    if (!merchantId) {
      return errorResponse('merchant_not_found', 'Merchant account not found', 404);
    }

    // 解析查询参数
    const ratingFilter = params.get('rating') ? parseInt(params.get('rating')!, 10) : null;
    const page         = Math.max(1, parseInt(params.get('page') ?? '1', 10));
    const perPage      = Math.min(50, Math.max(1, parseInt(params.get('per_page') ?? '20', 10)));
    const offset       = (page - 1) * perPage;

    // 构建查询：通过 deals 表关联 merchant_id
    // 联表查询：reviews → deals → users（获取用户名）
    let query = client
      .from('reviews')
      .select(
        `
        id,
        rating,
        comment,
        merchant_reply,
        replied_at,
        created_at,
        deals!inner(merchant_id),
        users(full_name, avatar_url)
        `,
        { count: 'exact' },
      )
      .eq('deals.merchant_id', merchantId)
      .order('created_at', { ascending: false })
      .range(offset, offset + perPage - 1);

    // 若指定了星级筛选
    if (ratingFilter && ratingFilter >= 1 && ratingFilter <= 5) {
      query = query.eq('rating', ratingFilter);
    }

    const { data, error, count } = await query;

    if (error) {
      console.error('[handleListReviews] DB error:', error);
      return errorResponse('db_error', error.message, 500);
    }

    // 格式化评价列表（从 nested join 结构提取字段）
    const reviews = (data ?? []).map((row: Record<string, unknown>) => {
      const user     = (row.users as Record<string, unknown>) ?? {};
      return {
        id:             row.id,
        user_name:      (user.full_name as string) ?? 'Anonymous',
        avatar_url:     (user.avatar_url as string) ?? null,
        rating:         row.rating,
        comment:        row.comment,
        image_urls:     [],                     // 后续支持图片时从 storage 获取
        merchant_reply: row.merchant_reply,
        replied_at:     row.replied_at,
        created_at:     row.created_at,
      };
    });

    const total   = count ?? 0;
    const hasMore = offset + perPage < total;

    return jsonResponse({
      data: reviews,
      pagination: {
        page,
        per_page: perPage,
        total,
        has_more: hasMore,
      },
    });
  } catch (err) {
    console.error('[handleListReviews] Unexpected error:', err);
    return errorResponse('internal_error', 'Internal server error', 500);
  }
}

// =============================================================
// handlePostReply — 提交商家回复
// Body: { reply: string }
// 限制: 每条评价只能回复1次
// =============================================================
async function handlePostReply(
  userClient:    ReturnType<typeof createClient>,
  serviceClient: ReturnType<typeof createClient>,
  reviewId:      string,
  req:           Request,
): Promise<Response> {
  try {
    // 解析请求体
    let body: Record<string, unknown>;
    try {
      body = await req.json();
    } catch {
      return errorResponse('invalid_body', 'Request body must be valid JSON', 400);
    }

    const reply = (body.reply as string | undefined)?.trim();
    if (!reply || reply.length === 0) {
      return errorResponse('validation_error', 'Reply content cannot be empty', 400);
    }
    if (reply.length > 300) {
      return errorResponse('validation_error', 'Reply must be 300 characters or less', 400);
    }

    // 获取当前商家 ID
    const merchantId = await getCurrentMerchantId(userClient);
    if (!merchantId) {
      return errorResponse('merchant_not_found', 'Merchant account not found', 404);
    }

    // 查询该评价，验证:
    //   1. 评价存在
    //   2. 评价属于该商家的门店 deal
    //   3. 尚未回复
    const { data: review, error: fetchError } = await userClient
      .from('reviews')
      .select('id, merchant_reply, deals!inner(merchant_id)')
      .eq('id', reviewId)
      .eq('deals.merchant_id', merchantId)
      .maybeSingle();

    if (fetchError) {
      console.error('[handlePostReply] Fetch error:', fetchError);
      return errorResponse('db_error', fetchError.message, 500);
    }

    if (!review) {
      return errorResponse('review_not_found', 'Review not found or does not belong to your store', 404);
    }

    // 检查是否已回复（限1次）
    const existingReply = (review as Record<string, unknown>).merchant_reply;
    if (existingReply !== null && existingReply !== undefined) {
      return errorResponse('already_replied', 'You have already replied to this review', 409);
    }

    // 使用 service_role 客户端写入回复（绕过 RLS 更新限制）
    const now = new Date().toISOString();
    const { error: updateError } = await serviceClient
      .from('reviews')
      .update({
        merchant_reply: reply,
        replied_at:     now,
      })
      .eq('id', reviewId);

    if (updateError) {
      console.error('[handlePostReply] Update error:', updateError);
      return errorResponse('db_error', updateError.message, 500);
    }

    return jsonResponse({
      success:        true,
      review_id:      reviewId,
      merchant_reply: reply,
      replied_at:     now,
    });
  } catch (err) {
    console.error('[handlePostReply] Unexpected error:', err);
    return errorResponse('internal_error', 'Internal server error', 500);
  }
}

// =============================================================
// handleGetStats — 评价统计
// 调用 get_review_stats DB 函数
// =============================================================
async function handleGetStats(
  client: ReturnType<typeof createClient>,
): Promise<Response> {
  try {
    // 获取当前商家 ID
    const merchantId = await getCurrentMerchantId(client);
    if (!merchantId) {
      return errorResponse('merchant_not_found', 'Merchant account not found', 404);
    }

    // 调用 DB 函数
    const { data, error } = await client.rpc('get_review_stats', {
      p_merchant_id: merchantId,
    });

    if (error) {
      console.error('[handleGetStats] RPC error:', error);
      return errorResponse('db_error', error.message, 500);
    }

    // RPC 返回数组，取第一行
    const row = Array.isArray(data) && data.length > 0
      ? (data[0] as Record<string, unknown>)
      : null;

    if (!row) {
      // 尚无评价时返回空统计
      return jsonResponse({
        avg_rating:          0,
        total_count:         0,
        rating_distribution: { '1': 0, '2': 0, '3': 0, '4': 0, '5': 0 },
        top_keywords:        [],
      });
    }

    return jsonResponse({
      avg_rating:          row.avg_rating,
      total_count:         row.total_count,
      rating_distribution: row.rating_distribution,
      top_keywords:        row.top_keywords ?? [],
    });
  } catch (err) {
    console.error('[handleGetStats] Unexpected error:', err);
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
