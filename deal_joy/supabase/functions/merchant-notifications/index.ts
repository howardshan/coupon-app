// =============================================================
// Edge Function: merchant-notifications
// 路由：
//   GET    /merchant-notifications              — 分页通知列表（支持 unread_only=true&page=N）
//   GET    /merchant-notifications/unread-count — 未读数量（用于 Badge）
//   PATCH  /merchant-notifications/read-all    — 全部标记已读
//   PATCH  /merchant-notifications/:id/read    — 单条标记已读
//   POST   /merchant-notifications/fcm-token   — 注册/更新 FCM Token
// 认证：Bearer JWT（merchant 用户，通过 auth.uid() 关联 merchants 表）
// =============================================================

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// CORS headers
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, PATCH, POST, OPTIONS',
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
  // OPTIONS 预检（CORS）
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  // 初始化 Supabase 环境变量
  const supabaseUrl  = Deno.env.get('SUPABASE_URL') ?? '';
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  const anonKey      = Deno.env.get('SUPABASE_ANON_KEY') ?? '';

  // 提取 Bearer JWT
  const authHeader = req.headers.get('Authorization');
  if (!authHeader?.startsWith('Bearer ')) {
    return errorResponse('Missing authorization header', 'unauthorized', 401);
  }
  const userJwt = authHeader.replace('Bearer ', '');

  // 用 user JWT 验证身份
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: `Bearer ${userJwt}` } },
  });

  const { data: { user }, error: userError } = await userClient.auth.getUser();
  if (userError || !user) {
    return errorResponse('Invalid or expired token', 'unauthorized', 401);
  }

  // 查询当前用户对应的 merchant
  const serviceClient = createClient(supabaseUrl, serviceRoleKey);
  const { data: merchant, error: merchantError } = await serviceClient
    .from('merchants')
    .select('id, status')
    .eq('user_id', user.id)
    .single();

  if (merchantError || !merchant) {
    return errorResponse('Merchant account not found', 'merchant_not_found', 404);
  }

  const merchantId = merchant.id as string;

  // 解析 URL 路径
  const url      = new URL(req.url);
  // 路径格式示例: /merchant-notifications、/merchant-notifications/read-all
  const pathParts = url.pathname.replace(/^\/merchant-notifications\/?/, '').split('/').filter(Boolean);
  // pathParts[0] = 具体资源 ID 或动作名 (read-all, unread-count, fcm-token)
  // pathParts[1] = 子操作 (read)

  const method = req.method;

  // =============================================================
  // 路由分发
  // =============================================================

  // GET /merchant-notifications/unread-count
  if (method === 'GET' && pathParts[0] === 'unread-count') {
    return handleUnreadCount(serviceClient, merchantId);
  }

  // PATCH /merchant-notifications/read-all
  if (method === 'PATCH' && pathParts[0] === 'read-all') {
    return handleMarkAllRead(serviceClient, merchantId);
  }

  // PATCH /merchant-notifications/:id/read
  if (method === 'PATCH' && pathParts.length === 2 && pathParts[1] === 'read') {
    return handleMarkRead(serviceClient, merchantId, pathParts[0]);
  }

  // POST /merchant-notifications/fcm-token
  if (method === 'POST' && pathParts[0] === 'fcm-token') {
    return handleRegisterFcmToken(serviceClient, merchantId, req);
  }

  // GET /merchant-notifications （分页列表，必须放在最后避免误匹配）
  if (method === 'GET' && pathParts.length === 0) {
    return handleFetchNotifications(serviceClient, merchantId, url.searchParams);
  }

  return errorResponse('Not found', 'not_found', 404);
});

// =============================================================
// Handler: GET /merchant-notifications
// 查询参数：unread_only=true, page=1, per_page=20
// =============================================================
async function handleFetchNotifications(
  client: ReturnType<typeof createClient>,
  merchantId: string,
  params: URLSearchParams
): Promise<Response> {
  try {
    const unreadOnly = params.get('unread_only') === 'true';
    const page       = Math.max(1, parseInt(params.get('page') ?? '1', 10));
    const perPage    = Math.min(50, Math.max(1, parseInt(params.get('per_page') ?? '20', 10)));
    const offset     = (page - 1) * perPage;

    // 构建查询
    let query = client
      .from('merchant_notifications')
      .select('*', { count: 'exact' })
      .eq('merchant_id', merchantId)
      .order('created_at', { ascending: false })
      .range(offset, offset + perPage - 1);

    if (unreadOnly) {
      query = query.eq('is_read', false);
    }

    const { data, error, count } = await query;

    if (error) {
      console.error('fetchNotifications error:', error);
      return errorResponse('Failed to fetch notifications', 'fetch_failed', 500);
    }

    const total   = count ?? 0;
    const hasMore = offset + perPage < total;

    return jsonResponse({
      data:     data ?? [],
      total,
      page,
      per_page: perPage,
      has_more: hasMore,
    });
  } catch (err) {
    console.error('handleFetchNotifications unexpected error:', err);
    return errorResponse('Internal server error', 'internal_error', 500);
  }
}

// =============================================================
// Handler: GET /merchant-notifications/unread-count
// 返回该商家未读通知总数
// =============================================================
async function handleUnreadCount(
  client: ReturnType<typeof createClient>,
  merchantId: string
): Promise<Response> {
  try {
    const { count, error } = await client
      .from('merchant_notifications')
      .select('*', { count: 'exact', head: true })  // head: true 不返回数据，只返回 count
      .eq('merchant_id', merchantId)
      .eq('is_read', false);

    if (error) {
      console.error('unreadCount error:', error);
      return errorResponse('Failed to fetch unread count', 'fetch_failed', 500);
    }

    return jsonResponse({ unread_count: count ?? 0 });
  } catch (err) {
    console.error('handleUnreadCount unexpected error:', err);
    return errorResponse('Internal server error', 'internal_error', 500);
  }
}

// =============================================================
// Handler: PATCH /merchant-notifications/:id/read
// 将指定通知标记为已读
// =============================================================
async function handleMarkRead(
  client: ReturnType<typeof createClient>,
  merchantId: string,
  notificationId: string
): Promise<Response> {
  try {
    // 验证 UUID 格式（防止 SQL 注入风险）
    const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (!uuidRegex.test(notificationId)) {
      return errorResponse('Invalid notification ID format', 'invalid_id', 400);
    }

    const { error } = await client
      .from('merchant_notifications')
      .update({ is_read: true })
      .eq('id', notificationId)
      .eq('merchant_id', merchantId);  // 确保只能更新自己的通知

    if (error) {
      console.error('markRead error:', error);
      return errorResponse('Failed to mark notification as read', 'update_failed', 500);
    }

    return jsonResponse({ success: true, notification_id: notificationId });
  } catch (err) {
    console.error('handleMarkRead unexpected error:', err);
    return errorResponse('Internal server error', 'internal_error', 500);
  }
}

// =============================================================
// Handler: PATCH /merchant-notifications/read-all
// 将该商家所有通知全部标记为已读
// =============================================================
async function handleMarkAllRead(
  client: ReturnType<typeof createClient>,
  merchantId: string
): Promise<Response> {
  try {
    const { error } = await client
      .from('merchant_notifications')
      .update({ is_read: true })
      .eq('merchant_id', merchantId)
      .eq('is_read', false);  // 仅更新未读，减少 I/O

    if (error) {
      console.error('markAllRead error:', error);
      return errorResponse('Failed to mark all notifications as read', 'update_failed', 500);
    }

    return jsonResponse({ success: true });
  } catch (err) {
    console.error('handleMarkAllRead unexpected error:', err);
    return errorResponse('Internal server error', 'internal_error', 500);
  }
}

// =============================================================
// Handler: POST /merchant-notifications/fcm-token
// Body: { fcm_token: string, device_type: 'ios' | 'android' }
// UPSERT：相同 (merchant_id, fcm_token) 时更新 updated_at 和 device_type
// =============================================================
async function handleRegisterFcmToken(
  client: ReturnType<typeof createClient>,
  merchantId: string,
  req: Request
): Promise<Response> {
  try {
    let body: Record<string, unknown>;
    try {
      body = await req.json();
    } catch {
      return errorResponse('Invalid JSON body', 'invalid_body', 400);
    }

    const fcmToken  = body['fcm_token'] as string | undefined;
    const deviceType = body['device_type'] as string | undefined;

    // 参数校验
    if (!fcmToken || typeof fcmToken !== 'string' || fcmToken.trim().length === 0) {
      return errorResponse('fcm_token is required', 'missing_token', 400);
    }
    if (!deviceType || !['ios', 'android'].includes(deviceType)) {
      return errorResponse('device_type must be "ios" or "android"', 'invalid_device_type', 400);
    }

    // UPSERT：同一 (merchant_id, fcm_token) 只保留一条，更新时间戳
    const { error } = await client
      .from('merchant_fcm_tokens')
      .upsert(
        {
          merchant_id: merchantId,
          fcm_token:   fcmToken.trim(),
          device_type: deviceType,
          updated_at:  new Date().toISOString(),
        },
        { onConflict: 'merchant_id,fcm_token' }  // 唯一约束触发 UPDATE
      );

    if (error) {
      console.error('registerFcmToken error:', error);
      return errorResponse('Failed to register FCM token', 'upsert_failed', 500);
    }

    return jsonResponse({ success: true, merchant_id: merchantId });
  } catch (err) {
    console.error('handleRegisterFcmToken unexpected error:', err);
    return errorResponse('Internal server error', 'internal_error', 500);
  }
}
