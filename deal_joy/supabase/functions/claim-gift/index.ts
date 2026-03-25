import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// CORS 头，允许跨域请求（claim-gift 为公开 API，无需认证）
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
  // 处理 CORS 预检请求
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // 初始化 Supabase service role 客户端（公开 API，无需用户认证）
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, serviceRoleKey);

    // ----------------------------------------------------------------
    // 1. 解析请求体
    // ----------------------------------------------------------------
    const body = await req.json();
    const { claim_token, user_id } = body as { claim_token?: string; user_id?: string };

    if (!claim_token) {
      return new Response(
        JSON.stringify({ error: 'Missing required field: claim_token' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 },
      );
    }

    // ----------------------------------------------------------------
    // 2. 根据 claim_token 查找礼品记录，JOIN 关联表获取完整信息
    // ----------------------------------------------------------------
    const { data: gift, error: giftError } = await supabase
      .from('coupon_gifts')
      .select(`
        id,
        status,
        claimed_at,
        recipient_user_id,
        gift_message,
        token_expires_at,
        order_item_id,
        gifter_user_id,
        order_items!inner(
          id,
          coupon_id,
          deal_id,
          deals!inner(
            id,
            title,
            usage_notes,
            expires_at,
            merchants!inner(
              id,
              name,
              address
            )
          ),
          coupons(
            id,
            coupon_code,
            qr_code,
            expires_at,
            status
          )
        )
      `)
      .eq('claim_token', claim_token)
      .single();

    if (giftError || !gift) {
      return new Response(
        JSON.stringify({ error: 'Gift not found: invalid claim token' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 404 },
      );
    }

    // ----------------------------------------------------------------
    // 3. 验证礼品状态
    // ----------------------------------------------------------------

    // 已撤回或已过期的礼品无法领取
    if (gift.status === 'recalled') {
      return new Response(
        JSON.stringify({ error: 'This gift has been recalled by the sender' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 410 },
      );
    }

    if (gift.status === 'expired') {
      return new Response(
        JSON.stringify({ error: 'This gift link has expired' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 410 },
      );
    }

    // 检查 token 是否已超过有效期
    if (gift.token_expires_at && new Date(gift.token_expires_at) < new Date()) {
      // 自动标记为 expired
      await supabase
        .from('coupon_gifts')
        .update({ status: 'expired' })
        .eq('id', gift.id);

      return new Response(
        JSON.stringify({ error: 'This gift link has expired' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 410 },
      );
    }

    // 提取关联数据（order_items 是对象，非数组）
    const orderItem = gift.order_items as any;
    const deal = orderItem?.deals as any;
    const merchant = deal?.merchants as any;
    const coupon = orderItem?.coupons as any;

    // 检查券是否过期
    const couponExpiresAt = coupon?.expires_at ?? deal?.expires_at;
    if (couponExpiresAt && new Date(couponExpiresAt) < new Date()) {
      return new Response(
        JSON.stringify({ error: 'The coupon in this gift has expired' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 410 },
      );
    }

    // ----------------------------------------------------------------
    // 4. 幂等处理：如果已经是 claimed 状态，直接返回券信息
    // ----------------------------------------------------------------

    // 查询赠送者姓名（无论是否已领取都需要）
    const { data: gifterUser } = await supabase
      .from('users')
      .select('full_name')
      .eq('id', gift.gifter_user_id)
      .single();

    if (gift.status === 'claimed') {
      return new Response(
        JSON.stringify({
          status: 'claimed',
          already_claimed: true,
          coupon_code:      coupon?.coupon_code  ?? '',
          qr_code:          coupon?.qr_code      ?? '',
          deal_title:       deal?.title          ?? '',
          merchant_name:    merchant?.name       ?? '',
          merchant_address: merchant?.address    ?? '',
          usage_notes:      deal?.usage_notes    ?? '',
          expires_at:       couponExpiresAt      ?? null,
          gift_message:     gift.gift_message    ?? '',
          gifter_name:      gifterUser?.full_name ?? '',
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 },
      );
    }

    // ----------------------------------------------------------------
    // 5. 执行领取操作
    // ----------------------------------------------------------------

    // 5a. 更新 coupon_gifts: status='claimed', claimed_at=now(), recipient_user_id=user_id
    const { error: claimGiftError } = await supabase
      .from('coupon_gifts')
      .update({
        status: 'claimed',
        claimed_at: new Date().toISOString(),
        ...(user_id ? { recipient_user_id: user_id } : {}),
      })
      .eq('id', gift.id);

    if (claimGiftError) {
      throw new Error(`Failed to claim gift: ${claimGiftError.message}`);
    }

    // 5b. 如果提供了 user_id，更新 coupons.current_holder_user_id
    if (user_id && coupon?.id) {
      const { error: couponUpdateError } = await supabase
        .from('coupons')
        .update({ current_holder_user_id: user_id })
        .eq('id', coupon.id);

      if (couponUpdateError) {
        // 非致命错误，记录但不中断流程
        console.error(`Warning: Failed to update coupon holder: ${couponUpdateError.message}`);
      }
    }

    // ----------------------------------------------------------------
    // 6. 返回券信息
    // ----------------------------------------------------------------
    return new Response(
      JSON.stringify({
        status: 'claimed',
        already_claimed: false,
        coupon_code:      coupon?.coupon_code  ?? '',
        qr_code:          coupon?.qr_code      ?? '',
        deal_title:       deal?.title          ?? '',
        merchant_name:    merchant?.name       ?? '',
        merchant_address: merchant?.address    ?? '',
        usage_notes:      deal?.usage_notes    ?? '',
        expires_at:       couponExpiresAt      ?? null,
        gift_message:     gift.gift_message    ?? '',
        gifter_name:      gifterUser?.full_name ?? '',
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 },
    );
  } catch (error) {
    // 捕获未预期的服务器错误
    return new Response(
      JSON.stringify({ error: error.message }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 },
    );
  }
});
