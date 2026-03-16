// Edge Function: submit-refund-request
// 用户核销后 24h 内提交退款申请，走商家审批流程
// 验证：订单 status == 'used'，coupons.used_at 在 24h 内
// 创建 refund_requests 记录，订单状态 → refund_pending_merchant

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2?target=deno';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const body = await req.json();
    const { orderId, reason, access_token } = body as {
      orderId?: string;
      reason?: string;
      access_token?: string;
    };

    // 输入校验
    if (!orderId || typeof orderId !== 'string' || orderId.trim() === '') {
      return new Response(
        JSON.stringify({ error: 'orderId is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }
    if (!reason || typeof reason !== 'string' || reason.trim().length < 10) {
      return new Response(
        JSON.stringify({ error: 'reason must be at least 10 characters' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }
    if (reason.trim().length > 500) {
      return new Response(
        JSON.stringify({ error: 'reason must not exceed 500 characters' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // 从 Authorization header 或 body 中提取 JWT
    const authHeader = req.headers.get('Authorization');
    const token = access_token?.trim() || authHeader?.replace(/^\s*Bearer\s+/i, '')?.trim();
    if (!token) {
      return new Response(
        JSON.stringify({ error: 'Unauthorized' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

    // 用户客户端：验证 JWT + RLS 保证只能查自己的订单
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: `Bearer ${token}` } },
    });

    // 验证 JWT 并获取 user id
    const { data: userData, error: userError } = await userClient.auth.getUser(token);
    if (userError || !userData?.user) {
      return new Response(
        JSON.stringify({ error: 'Unauthorized' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }
    const userId = userData.user.id;

    // service role 客户端：绕过 RLS 执行写操作
    const serviceClient = createClient(supabaseUrl, serviceRoleKey);

    // 查询订单（含关联券）
    const { data: order, error: orderError } = await serviceClient
      .from('orders')
      .select('id, user_id, deal_id, coupon_id, status, total_amount, coupons!fk_orders_coupon_id(used_at, merchant_id)')
      .eq('id', orderId.trim())
      .single();

    if (orderError || !order) {
      return new Response(
        JSON.stringify({ error: 'Order not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // RLS 等效校验：确保订单属于当前用户
    if (order.user_id !== userId) {
      return new Response(
        JSON.stringify({ error: 'Order not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // 校验订单状态必须是 used
    if (order.status !== 'used') {
      return new Response(
        JSON.stringify({ error: `Order status is '${order.status}', must be 'used' to submit post-use refund` }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // 校验 24h 窗口
    const coupon = (order.coupons as { used_at: string | null; merchant_id: string } | null);
    if (!coupon || !coupon.used_at) {
      return new Response(
        JSON.stringify({ error: 'Coupon redemption time not found' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }
    const usedAt = new Date(coupon.used_at);
    const now = new Date();
    const hoursSinceUse = (now.getTime() - usedAt.getTime()) / (1000 * 60 * 60);
    if (hoursSinceUse > 24) {
      return new Response(
        JSON.stringify({ error: 'Post-use refund window has expired (24 hours after redemption)' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const merchantId = coupon.merchant_id;

    // 检查是否已有进行中的退款申请
    const { data: existingRequest } = await serviceClient
      .from('refund_requests')
      .select('id, status')
      .eq('order_id', orderId)
      .not('status', 'in', '(rejected_admin,cancelled)')
      .maybeSingle();

    if (existingRequest) {
      return new Response(
        JSON.stringify({ error: 'A refund request already exists for this order', requestId: existingRequest.id }),
        { status: 409, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const nowIso = now.toISOString();

    // 创建退款申请记录
    const { data: refundRequest, error: insertError } = await serviceClient
      .from('refund_requests')
      .insert({
        order_id: orderId,
        user_id: userId,
        merchant_id: merchantId,
        status: 'pending_merchant',
        refund_amount: order.total_amount,
        reason: reason.trim(),
        created_at: nowIso,
        updated_at: nowIso,
      })
      .select('id')
      .single();

    if (insertError || !refundRequest) {
      console.error('[submit-refund-request] insert error:', insertError);
      return new Response(
        JSON.stringify({ error: 'Failed to create refund request' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // 更新订单状态 → refund_pending_merchant
    await serviceClient
      .from('orders')
      .update({
        status: 'refund_pending_merchant',
        updated_at: nowIso,
      })
      .eq('id', orderId);

    return new Response(
      JSON.stringify({
        refundRequestId: refundRequest.id,
        status: 'pending_merchant',
        message: 'Refund request submitted successfully',
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  } catch (err) {
    console.error('[submit-refund-request] error:', err);
    return new Response(
      JSON.stringify({ error: err instanceof Error ? err.message : 'Unknown error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  }
});
