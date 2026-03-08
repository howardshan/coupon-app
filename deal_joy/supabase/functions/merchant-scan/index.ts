// =============================================================
// Edge Function: merchant-scan
// 功能: 团购券核销相关 API — 验证/核销/撤销/历史记录
// 路由:
//   POST /merchant-scan/verify  — 验证券码（只查询，不核销）
//   POST /merchant-scan/redeem  — 执行核销
//   POST /merchant-scan/revert  — 撤销核销（10分钟内）
//   GET  /merchant-scan/history — 分页获取核销历史
// =============================================================

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { resolveAuth, requirePermission } from "../_shared/auth.ts";

// CORS 响应头（允许商家端 App 调用）
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-merchant-id',
  'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
};

// 统一 JSON 响应工具函数
function jsonResponse(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

// 错误响应工具函数
function errorResponse(error: string, message: string, detail?: string, status = 400) {
  return jsonResponse({ error, message, detail }, status);
}

// 对用户名进行脱敏处理，例如 "John Smith" → "J*** Smith"
function maskUserName(fullName: string | null): string {
  if (!fullName) return 'Unknown User';
  const parts = fullName.trim().split(' ');
  if (parts.length === 0) return 'Unknown User';
  // 保留首字母，其余用 *** 替代
  const first = parts[0];
  const rest = parts.slice(1).join(' ');
  const masked = first.charAt(0) + '***';
  return rest ? `${masked} ${rest}` : masked;
}

// =============================================================
// 主路由处理器
// =============================================================
serve(async (req: Request) => {
  // 处理 CORS 预检请求
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  const url = new URL(req.url);
  const pathname = url.pathname;

  // 从请求头提取 JWT，用于身份验证
  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    return errorResponse('unauthorized', 'Missing authorization header', undefined, 401);
  }

  // 创建 Supabase 客户端（service_role 用于 BYPASS RLS 执行核销写操作）
  const supabaseAdmin = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  );

  // 创建用户级别客户端（用于验证 JWT 和获取当前用户信息）
  const supabaseUser = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_ANON_KEY') ?? '',
    { global: { headers: { Authorization: authHeader } } },
  );

  // 验证 JWT 并获取当前登录用户
  const { data: { user }, error: authError } = await supabaseUser.auth.getUser();
  if (authError || !user) {
    return errorResponse('unauthorized', 'Invalid or expired token', undefined, 401);
  }

  // 统一鉴权
  let auth;
  try {
    auth = await resolveAuth(supabaseAdmin, user.id, req.headers);
  } catch (e) {
    return errorResponse('unauthorized', (e as Error).message, undefined, 403);
  }
  requirePermission(auth, 'scan');

  // 获取商家名称（核销记录需要）
  const { data: merchant } = await supabaseAdmin
    .from('merchants')
    .select('id, name, status')
    .eq('id', auth.merchantId)
    .single();

  if (!merchant) {
    return errorResponse('forbidden', 'No merchant account found for this user', undefined, 403);
  }

  const merchantId = merchant.id;

  // 路由分发
  if (req.method === 'POST' && pathname.endsWith('/verify')) {
    return handleVerify(req, supabaseAdmin, merchantId);
  }

  if (req.method === 'POST' && pathname.endsWith('/redeem')) {
    return handleRedeem(req, supabaseAdmin, merchantId, user.id);
  }

  if (req.method === 'POST' && pathname.endsWith('/revert')) {
    return handleRevert(req, supabaseAdmin, merchantId, user.id);
  }

  if (req.method === 'GET' && pathname.endsWith('/history')) {
    return handleHistory(url, supabaseAdmin, merchantId);
  }

  return errorResponse('not_found', 'Route not found', undefined, 404);
});

// =============================================================
// POST /merchant-scan/verify — 验证券码（不核销）
// 请求体: { code: string }
// 返回: CouponInfo 或 错误信息
// =============================================================
async function handleVerify(
  req: Request,
  supabase: ReturnType<typeof createClient>,
  merchantId: string,
) {
  let body: { code?: string };
  try {
    body = await req.json();
  } catch {
    return errorResponse('invalid_request', 'Request body must be valid JSON');
  }

  const code = body.code?.trim();
  if (!code) {
    return errorResponse('invalid_code', 'Please enter a valid voucher code');
  }

  // 查询券码，JOIN deals 获取标题，JOIN users 获取用户名
  const { data: coupon, error } = await supabase
    .from('coupons')
    .select(`
      id,
      qr_code,
      status,
      expires_at,
      redeemed_at,
      reverted_at,
      merchant_id,
      deal_id,
      deals!inner (
        title
      ),
      users!coupons_user_id_fkey (
        full_name
      )
    `)
    .eq('qr_code', code)
    .maybeSingle();

  if (error) {
    console.error('verify query error:', error);
    return errorResponse('server_error', 'Failed to query coupon', undefined, 500);
  }

  if (!coupon) {
    return errorResponse('not_found', 'Invalid voucher code');
  }

  // 检查是否属于当前商家
  if (coupon.merchant_id !== merchantId) {
    return errorResponse(
      'wrong_merchant',
      'This voucher is not valid for your store',
    );
  }

  // 检查各种状态异常
  if (coupon.status === 'used' && !coupon.reverted_at) {
    const redeemedDate = coupon.redeemed_at
      ? new Date(coupon.redeemed_at).toLocaleDateString('en-US', {
        month: 'short', day: 'numeric', year: 'numeric',
      })
      : 'unknown date';
    return errorResponse(
      'already_used',
      `This voucher has already been redeemed on ${redeemedDate}`,
      coupon.redeemed_at,
    );
  }

  if (coupon.status === 'refunded') {
    return errorResponse(
      'already_refunded',
      'This voucher has been refunded and is no longer valid',
    );
  }

  if (coupon.status === 'expired') {
    const expiredDate = new Date(coupon.expires_at).toLocaleDateString('en-US', {
      month: 'short', day: 'numeric', year: 'numeric',
    });
    return errorResponse(
      'expired',
      `This voucher expired on ${expiredDate}`,
      coupon.expires_at,
    );
  }

  // 额外检查：即使数据库状态是 active，也要检查到期时间
  if (new Date(coupon.expires_at) < new Date()) {
    const expiredDate = new Date(coupon.expires_at).toLocaleDateString('en-US', {
      month: 'short', day: 'numeric', year: 'numeric',
    });
    return errorResponse(
      'expired',
      `This voucher expired on ${expiredDate}`,
      coupon.expires_at,
    );
  }

  // 获取用户名并脱敏
  // deno-lint-ignore no-explicit-any
  const userData = (coupon as any).users;
  const rawName = userData?.full_name ?? null;
  const maskedName = maskUserName(rawName);

  // deno-lint-ignore no-explicit-any
  const dealData = (coupon as any).deals;
  const dealTitle = dealData?.title ?? 'Unknown Deal';

  return jsonResponse({
    id: coupon.id,
    code: coupon.qr_code,
    deal_title: dealTitle,
    user_name: maskedName,
    valid_until: coupon.expires_at,
    status: coupon.status,
    redeemed_at: coupon.redeemed_at,
    error: null,
  });
}

// =============================================================
// POST /merchant-scan/redeem — 执行核销
// 请求体: { coupon_id: string }
// =============================================================
async function handleRedeem(
  req: Request,
  supabase: ReturnType<typeof createClient>,
  merchantId: string,
  actorUserId: string,
) {
  let body: { coupon_id?: string };
  try {
    body = await req.json();
  } catch {
    return errorResponse('invalid_request', 'Request body must be valid JSON');
  }

  const couponId = body.coupon_id?.trim();
  if (!couponId) {
    return errorResponse('invalid_request', 'coupon_id is required');
  }

  // 查询券的当前状态
  const { data: coupon, error: queryError } = await supabase
    .from('coupons')
    .select('id, status, merchant_id, expires_at, redeemed_at, deal_id')
    .eq('id', couponId)
    .single();

  if (queryError || !coupon) {
    return errorResponse('not_found', 'Voucher not found', undefined, 404);
  }

  // 安全检查：只能核销自己门店的券
  if (coupon.merchant_id !== merchantId) {
    return errorResponse('wrong_merchant', 'This voucher is not valid for your store', undefined, 403);
  }

  // 状态检查
  if (coupon.status === 'used') {
    // 防重复提交：如果10秒内已核销，视为幂等请求，返回成功
    if (coupon.redeemed_at) {
      const secondsAgo = (Date.now() - new Date(coupon.redeemed_at).getTime()) / 1000;
      if (secondsAgo <= 10) {
        return jsonResponse({ redeemed_at: coupon.redeemed_at, coupon_id: couponId });
      }
    }
    return errorResponse('already_used', 'This voucher has already been redeemed');
  }

  if (coupon.status === 'refunded') {
    return errorResponse('already_refunded', 'This voucher has been refunded');
  }

  if (coupon.status === 'expired' || new Date(coupon.expires_at) < new Date()) {
    return errorResponse('expired', 'This voucher has expired');
  }

  const now = new Date().toISOString();

  // 更新 coupons 表：标记为已使用
  const { error: updateError } = await supabase
    .from('coupons')
    .update({
      status: 'used',
      redeemed_at: now,
      redeemed_by_merchant_id: merchantId,
      used_at: now,
    })
    .eq('id', couponId);

  if (updateError) {
    console.error('redeem update error:', updateError);
    return errorResponse('server_error', 'Failed to redeem voucher', undefined, 500);
  }

  // 写入核销日志
  const { error: logError } = await supabase
    .from('redemption_log')
    .insert({
      coupon_id: couponId,
      merchant_id: merchantId,
      action: 'redeem',
      actor_user_id: actorUserId,
    });

  if (logError) {
    // 日志写失败不影响核销结果，只记录错误
    console.error('redemption_log insert error:', logError);
  }

  return jsonResponse({ redeemed_at: now, coupon_id: couponId });
}

// =============================================================
// POST /merchant-scan/revert — 撤销核销（仅10分钟内有效）
// 请求体: { coupon_id: string }
// =============================================================
async function handleRevert(
  req: Request,
  supabase: ReturnType<typeof createClient>,
  merchantId: string,
  actorUserId: string,
) {
  let body: { coupon_id?: string };
  try {
    body = await req.json();
  } catch {
    return errorResponse('invalid_request', 'Request body must be valid JSON');
  }

  const couponId = body.coupon_id?.trim();
  if (!couponId) {
    return errorResponse('invalid_request', 'coupon_id is required');
  }

  // 查询券状态
  const { data: coupon, error: queryError } = await supabase
    .from('coupons')
    .select('id, status, merchant_id, redeemed_at, redeemed_by_merchant_id')
    .eq('id', couponId)
    .single();

  if (queryError || !coupon) {
    return errorResponse('not_found', 'Voucher not found', undefined, 404);
  }

  // 只能撤销自己门店的核销
  if (coupon.merchant_id !== merchantId) {
    return errorResponse('wrong_merchant', 'This voucher does not belong to your store', undefined, 403);
  }

  // 检查是否处于已核销状态
  if (coupon.status !== 'used' || !coupon.redeemed_at) {
    return errorResponse('invalid_state', 'This voucher has not been redeemed');
  }

  // 检查是否在10分钟内
  const redeemedAt = new Date(coupon.redeemed_at);
  const minutesAgo = (Date.now() - redeemedAt.getTime()) / 1000 / 60;
  if (minutesAgo > 10) {
    return errorResponse(
      'revert_expired',
      'Cannot revert after 10 minutes',
      `Redeemed at ${coupon.redeemed_at}`,
    );
  }

  const now = new Date().toISOString();

  // 恢复券状态为 active，清空核销相关字段
  const { error: updateError } = await supabase
    .from('coupons')
    .update({
      status: 'active',
      redeemed_at: null,
      redeemed_by_merchant_id: null,
      reverted_at: now,
      used_at: null,
    })
    .eq('id', couponId);

  if (updateError) {
    console.error('revert update error:', updateError);
    return errorResponse('server_error', 'Failed to revert redemption', undefined, 500);
  }

  // 写入撤销日志
  const { error: logError } = await supabase
    .from('redemption_log')
    .insert({
      coupon_id: couponId,
      merchant_id: merchantId,
      action: 'revert',
      actor_user_id: actorUserId,
    });

  if (logError) {
    console.error('redemption_log revert insert error:', logError);
  }

  return jsonResponse({ reverted_at: now, coupon_id: couponId });
}

// =============================================================
// GET /merchant-scan/history — 分页获取核销历史
// Query params: date_from, date_to, deal_id, page, per_page
// =============================================================
async function handleHistory(
  url: URL,
  supabase: ReturnType<typeof createClient>,
  merchantId: string,
) {
  const dateFrom = url.searchParams.get('date_from');
  const dateTo = url.searchParams.get('date_to');
  const dealId = url.searchParams.get('deal_id');
  const page = Math.max(1, parseInt(url.searchParams.get('page') ?? '1', 10));
  const perPage = Math.min(50, Math.max(1, parseInt(url.searchParams.get('per_page') ?? '20', 10)));
  const offset = (page - 1) * perPage;

  // 查询 redemption_log，JOIN coupons / deals / users 获取完整信息
  // 只查询 action='redeem' 的记录作为核销历史主列表
  let query = supabase
    .from('redemption_log')
    .select(`
      id,
      action,
      created_at,
      coupon_id,
      coupons!inner (
        qr_code,
        reverted_at,
        deal_id,
        deals!inner (
          title
        ),
        users!coupons_user_id_fkey (
          full_name
        )
      )
    `, { count: 'exact' })
    .eq('merchant_id', merchantId)
    .eq('action', 'redeem')
    .order('created_at', { ascending: false })
    .range(offset, offset + perPage - 1);

  // 日期筛选
  if (dateFrom) {
    query = query.gte('created_at', `${dateFrom}T00:00:00.000Z`);
  }
  if (dateTo) {
    query = query.lte('created_at', `${dateTo}T23:59:59.999Z`);
  }

  // Deal 筛选（通过 coupons.deal_id 过滤）
  if (dealId) {
    query = query.eq('coupons.deal_id', dealId);
  }

  const { data: logs, error, count } = await query;

  if (error) {
    console.error('history query error:', error);
    return errorResponse('server_error', 'Failed to fetch redemption history', undefined, 500);
  }

  // 格式化返回数据
  // deno-lint-ignore no-explicit-any
  const records = (logs ?? []).map((log: any) => {
    const coupon = log.coupons;
    const deal = coupon?.deals;
    const userData = coupon?.users;
    return {
      id: log.id,
      coupon_id: log.coupon_id,
      coupon_code: coupon?.qr_code ?? '',
      deal_title: deal?.title ?? 'Unknown Deal',
      user_name: maskUserName(userData?.full_name ?? null),
      redeemed_at: log.created_at,
      is_reverted: coupon?.reverted_at != null,
      reverted_at: coupon?.reverted_at ?? null,
    };
  });

  const total = count ?? 0;

  return jsonResponse({
    data: records,
    total,
    page,
    per_page: perPage,
    has_more: offset + perPage < total,
  });
}
