// =============================================================
// Edge Function: user-order-detail
// 用户端订单详情：返回与商家端一致的数据结构（Deal / Payment / Voucher / Timeline）
// 路由：GET /user-order-detail?order_id=xxx 或 POST body { order_id, access_token }
// 认证：优先从 body.access_token 取 JWT（网关可能不转发 Header），否则从 Authorization 取
// =============================================================

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
};

function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function errorResponse(message: string, code: string, status = 400): Response {
  return jsonResponse({ error: code, message }, status);
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  if (!['GET', 'POST'].includes(req.method)) {
    return errorResponse('Method not allowed', 'method_not_allowed', 405);
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

  const url = new URL(req.url);
  let orderId = url.searchParams.get('order_id')?.trim() ?? null;

  // POST 时从 body 取 order_id 与 access_token（网关可能不转发 Authorization）
  let bodyToken = '';
  if (req.method === 'POST') {
    try {
      const body = (await req.json()) as { order_id?: string; access_token?: string };
      if (body.order_id != null) orderId = String(body.order_id).trim() || null;
      if (body.access_token != null) bodyToken = String(body.access_token).trim();
    } catch {
      // body 解析失败时保留 query 的 order_id
    }
  }

  const authHeader = req.headers.get('Authorization') ?? req.headers.get('authorization');
  const headerToken = authHeader?.replace(/^\s*Bearer\s+/i, '')?.trim() ?? '';
  const token = bodyToken || headerToken;

  if (!token) {
    return errorResponse('Missing authorization (header or body access_token)', 'unauthorized', 401);
  }

  const userClient = createClient(supabaseUrl, anonKey);
  const { data: claimsData, error: claimsError } = await userClient.auth.getClaims(token);
  if (claimsError || !claimsData?.claims?.sub) {
    return errorResponse('Invalid or expired token', 'unauthorized', 401);
  }
  const userId = claimsData.claims.sub as string;

  if (!orderId) {
    return errorResponse('Missing order_id', 'bad_request', 400);
  }

  const client = createClient(supabaseUrl, serviceRoleKey);

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
        image_urls,
        merchants ( name )
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
    return errorResponse('Order not found', 'not_found', 404);
  }

  if ((order as { user_id: string }).user_id !== userId) {
    return errorResponse('Access denied', 'forbidden', 403);
  }

  const { data: payment } = await client
    .from('payments')
    .select('payment_intent_id, status, amount, refund_amount, created_at')
    .eq('order_id', orderId)
    .maybeSingle();

  const coupon = Array.isArray(order.coupons)
    ? (order.coupons[0] ?? null)
    : order.coupons;

  const timeline: Array<{ event: string; timestamp: string | null; completed: boolean }> = [
    { event: 'purchased', timestamp: order.created_at, completed: true },
  ];

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

  const rawIntentId: string = order.payment_intent_id ?? '';
  const maskedIntentId =
    rawIntentId.length > 8 ? '****' + rawIntentId.slice(-8) : rawIntentId;

  const deals = order.deals as {
    title: string;
    original_price: number;
    discount_price: number;
    image_urls?: string[] | null;
    merchants?: { name: string } | null;
  };
  const dealImageUrl =
    Array.isArray(deals?.image_urls) && deals.image_urls.length > 0
      ? deals.image_urls[0]
      : null;
  const merchantName = deals?.merchants?.name ?? null;

  return jsonResponse({
    order: {
      id: order.id,
      order_number: order.order_number,
      status: order.status,
      deal_id: order.deal_id,
      deal_title: deals?.title ?? '',
      deal_original_price: deals?.original_price ?? 0,
      deal_discount_price: deals?.discount_price ?? 0,
      deal_image_url: dealImageUrl,
      merchant_name: merchantName,
      quantity: order.quantity,
      unit_price: order.unit_price,
      total_amount: order.total_amount,
      payment_intent_id_masked: maskedIntentId,
      payment_status: payment?.status ?? null,
      refund_amount: payment?.refund_amount ?? null,
      refund_reason: order.refund_reason ?? null,
      coupon_id: coupon?.id ?? null,
      coupon_code: coupon?.qr_code ?? null,
      coupon_status: coupon?.status ?? null,
      coupon_expires_at: coupon?.expires_at ?? null,
      coupon_used_at: coupon?.used_at ?? null,
      created_at: order.created_at,
      updated_at: order.updated_at,
      refund_requested_at: order.refund_requested_at ?? null,
      refunded_at: order.refunded_at ?? null,
      refund_rejected_at: order.refund_rejected_at ?? null,
      timeline,
    },
  });
});
