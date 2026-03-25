import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// CORS 头，允许跨域请求
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
    // 初始化 Supabase 客户端（service role 绕过 RLS，在函数内自行做权限校验）
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, serviceRoleKey);

    // ----------------------------------------------------------------
    // 1. 验证用户身份（从 Authorization header 中解析 JWT）
    // ----------------------------------------------------------------
    const authHeader = req.headers.get('Authorization');
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return new Response(
        JSON.stringify({ error: 'Missing or invalid Authorization header' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 401 },
      );
    }

    const token = authHeader.replace('Bearer ', '');

    // 使用 anon key 客户端验证 token，获取用户信息
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
    const anonClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: `Bearer ${token}` } },
    });

    const { data: { user }, error: authError } = await anonClient.auth.getUser();
    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: 'Unauthorized: invalid token' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 401 },
      );
    }

    const currentUserId = user.id;

    // ----------------------------------------------------------------
    // 2. 解析请求体
    // ----------------------------------------------------------------
    const body = await req.json();
    const { gift_id } = body as { gift_id?: string };

    if (!gift_id) {
      return new Response(
        JSON.stringify({ error: 'Missing required field: gift_id' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 },
      );
    }

    // ----------------------------------------------------------------
    // 3. 查询礼品记录，验证归属和状态
    // ----------------------------------------------------------------
    const { data: gift, error: giftError } = await supabase
      .from('coupon_gifts')
      .select('id, gifter_user_id, status, order_item_id')
      .eq('id', gift_id)
      .single();

    if (giftError || !gift) {
      return new Response(
        JSON.stringify({ error: 'Gift not found' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 404 },
      );
    }

    // 验证当前用户是赠送者
    if (gift.gifter_user_id !== currentUserId) {
      return new Response(
        JSON.stringify({ error: 'Forbidden: you are not the gifter of this gift' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 403 },
      );
    }

    // 只有 pending 状态的礼品才可撤回（已领取的无法撤回）
    if (gift.status !== 'pending') {
      return new Response(
        JSON.stringify({ error: `Cannot recall gift with status: ${gift.status}` }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 422 },
      );
    }

    // ----------------------------------------------------------------
    // 4. 查询关联的 order_item 和 coupon，用于后续恢复
    // ----------------------------------------------------------------
    const { data: orderItem, error: itemError } = await supabase
      .from('order_items')
      .select('id, coupon_id')
      .eq('id', gift.order_item_id)
      .single();

    if (itemError || !orderItem) {
      return new Response(
        JSON.stringify({ error: 'Associated order item not found' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 404 },
      );
    }

    // ----------------------------------------------------------------
    // 5. 原子执行撤回操作（使用 service role 绕过 RLS）
    // ----------------------------------------------------------------

    // 5a. 更新 coupon_gifts: status='recalled', recalled_at=now()
    const { error: recallGiftError } = await supabase
      .from('coupon_gifts')
      .update({
        status: 'recalled',
        recalled_at: new Date().toISOString(),
      })
      .eq('id', gift_id);

    if (recallGiftError) {
      throw new Error(`Failed to update gift status: ${recallGiftError.message}`);
    }

    // 5b. 恢复 order_items.customer_status = 'unused'
    const { error: itemUpdateError } = await supabase
      .from('order_items')
      .update({ customer_status: 'unused' })
      .eq('id', gift.order_item_id);

    if (itemUpdateError) {
      throw new Error(`Failed to restore order item status: ${itemUpdateError.message}`);
    }

    // 5c. 恢复 coupons: is_gifted=false, current_holder_user_id=gifter_user_id
    if (orderItem.coupon_id) {
      const { error: couponUpdateError } = await supabase
        .from('coupons')
        .update({
          is_gifted: false,
          current_holder_user_id: currentUserId,
        })
        .eq('id', orderItem.coupon_id);

      if (couponUpdateError) {
        throw new Error(`Failed to restore coupon: ${couponUpdateError.message}`);
      }
    }

    // ----------------------------------------------------------------
    // 6. 返回成功
    // ----------------------------------------------------------------
    return new Response(
      JSON.stringify({ success: true }),
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
