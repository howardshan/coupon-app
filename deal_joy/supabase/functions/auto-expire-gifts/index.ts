// auto-expire-gifts — Cron Job Edge Function
// 处理赠礼状态过期：当券已过期但 gift 仍为 pending 时，自动将 gift 标为 expired
//
// 建议通过 Supabase Dashboard → Edge Functions → auto-expire-gifts → Schedule
// 设置为每天 00:05 UTC 执行一次（比 auto-refund-expired 晚 5 分钟，确保顺序一致）
//
// 或者通过 pg_cron 调用：
// SELECT cron.schedule(
//   'auto-expire-gifts',
//   '5 0 * * *',
//   $$
//     SELECT net.http_post(
//       url := 'https://kqyolvmgrdekybjrwizx.supabase.co/functions/v1/auto-expire-gifts',
//       headers := '{"Content-Type": "application/json", "Authorization": "Bearer <service_role_key>"}'::jsonb,
//       body := '{}'::jsonb
//     )
//   $$
// );

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

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
    // 使用 service role key，绕过 RLS 进行批量操作
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, serviceRoleKey);

    // 第一步：查询所有 status = 'pending' 的 coupon_gifts
    const { data: pendingGifts, error: fetchError } = await supabase
      .from('coupon_gifts')
      .select('id, order_item_id')
      .eq('status', 'pending');

    if (fetchError) {
      throw new Error(`查询 pending gifts 失败: ${fetchError.message}`);
    }

    if (!pendingGifts || pendingGifts.length === 0) {
      // 没有 pending 的 gift，直接返回
      return new Response(
        JSON.stringify({ expired_count: 0, checked_count: 0 }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    let expiredCount = 0;
    const errors: string[] = [];
    const now = new Date();

    // 第二步：逐个检查关联券是否已过期
    for (const gift of pendingGifts) {
      try {
        // 查询 order_item 关联的 coupon 过期时间
        const { data: orderItem, error: oiError } = await supabase
          .from('order_items')
          .select('coupon_id, coupons(expires_at)')
          .eq('id', gift.order_item_id)
          .maybeSingle();

        if (oiError) {
          errors.push(`order_item ${gift.order_item_id}: ${oiError.message}`);
          continue;
        }

        // 没有关联券或没有过期时间，跳过
        if (!orderItem?.coupons?.expires_at) continue;

        const expiresAt = new Date(orderItem.coupons.expires_at);
        // 券还未过期，跳过
        if (expiresAt > now) continue;

        // 券已过期，执行三步状态更新
        // 步骤 A：将 coupon_gifts.status 更新为 'expired'
        const { error: giftErr } = await supabase
          .from('coupon_gifts')
          .update({
            status: 'expired',
            updated_at: now.toISOString(),
          })
          .eq('id', gift.id);

        if (giftErr) {
          errors.push(`更新 gift ${gift.id} 失败: ${giftErr.message}`);
          continue;
        }

        // 步骤 B：将 order_items.customer_status 更新为 'expired'
        // 让现有的 auto-refund-expired Cron Job 负责处理退款给 gifter
        const { error: oiUpdateErr } = await supabase
          .from('order_items')
          .update({ customer_status: 'expired' })
          .eq('id', gift.order_item_id);

        if (oiUpdateErr) {
          errors.push(`更新 order_item ${gift.order_item_id} 失败: ${oiUpdateErr.message}`);
          // 继续处理 coupon，即使 order_item 更新失败也尽量回滚 is_gifted
        }

        // 步骤 C：将 coupons.is_gifted 更新为 false，让券恢复可用状态
        if (orderItem.coupon_id) {
          const { error: couponErr } = await supabase
            .from('coupons')
            .update({ is_gifted: false })
            .eq('id', orderItem.coupon_id);

          if (couponErr) {
            errors.push(`更新 coupon ${orderItem.coupon_id} 失败: ${couponErr.message}`);
          }
        }

        expiredCount++;
      } catch (itemErr) {
        errors.push(`处理 gift ${gift.id} 时异常: ${(itemErr as Error).message}`);
      }
    }

    // 返回执行摘要
    const result: Record<string, unknown> = {
      expired_count: expiredCount,
      checked_count: pendingGifts.length,
      executed_at: now.toISOString(),
    };

    if (errors.length > 0) {
      result.errors = errors;
    }

    return new Response(JSON.stringify(result), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (error) {
    // 顶层异常，返回 500
    return new Response(
      JSON.stringify({ error: (error as Error).message }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 500,
      },
    );
  }
});
