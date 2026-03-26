// =============================================================
// Edge Function: update-user-tags
// 每小时由 pg_cron 触发，根据用户行为事件计算用户标签
// 路由：
//   POST /update-user-tags — 批量更新所有活跃用户标签
// 认证：Bearer SERVICE_ROLE_KEY（仅 cron 调用）
// =============================================================

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

// 根据小时判断时段
function getTimeSlot(hour: number): string {
  if (hour >= 6 && hour < 10) return 'breakfast';
  if (hour >= 11 && hour < 14) return 'lunch';
  if (hour >= 14 && hour < 17) return 'afternoon';
  if (hour >= 17 && hour < 21) return 'dinner';
  if (hour >= 21 || hour < 2) return 'late_night';
  return 'other';
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, serviceRoleKey);

    // 获取30天内有登录记录的活跃用户
    const thirtyDaysAgo = new Date(Date.now() - 30 * 86400000).toISOString();
    const { data: users, error: usersError } = await supabase
      .from('users')
      .select('id')
      .gt('last_login_at', thirtyDaysAgo);

    if (usersError) throw usersError;
    if (!users || users.length === 0) {
      return jsonResponse({ message: 'No active users to update', count: 0 });
    }

    let updatedCount = 0;

    // 分批处理（每批50个用户）
    const batchSize = 50;
    for (let i = 0; i < users.length; i += batchSize) {
      const batch = users.slice(i, i + batchSize);

      await Promise.all(batch.map(async (user: { id: string }) => {
        try {
          // 获取用户30天内的事件
          const { data: events } = await supabase
            .from('user_events')
            .select('*')
            .eq('user_id', user.id)
            .gt('occurred_at', thirtyDaysAgo)
            .order('occurred_at', { ascending: false })
            .limit(500);

          if (!events || events.length === 0) return;

          // 统计分类偏好
          const categoryCount: Record<string, number> = {};
          const timeSlotCount: Record<string, number> = {};
          let totalSpend = 0;
          let purchaseCount = 0;
          const hashtags: string[] = [];

          for (const event of events) {
            // 浏览事件 — 统计分类
            if (event.event_type === 'view_deal' && event.metadata?.category) {
              const cat = event.metadata.category as string;
              categoryCount[cat] = (categoryCount[cat] ?? 0) + 1;
            }

            // 购买事件 — 统计消费和时段
            if (event.event_type === 'purchase') {
              const hour = new Date(event.occurred_at).getHours();
              const slot = getTimeSlot(hour);
              timeSlotCount[slot] = (timeSlotCount[slot] ?? 0) + 1;
              totalSpend += (event.metadata?.amount as number) ?? 0;
              purchaseCount += 1;

              // 购买也算分类偏好（权重更高）
              if (event.metadata?.category) {
                const cat = event.metadata.category as string;
                categoryCount[cat] = (categoryCount[cat] ?? 0) + 3;
              }
            }

            // 评价事件 — 提取 hashtag
            if (event.event_type === 'review' && event.metadata?.hashtags) {
              hashtags.push(...(event.metadata.hashtags as string[]));
            }
          }

          // 计算 top 3 分类
          const topCategories = Object.entries(categoryCount)
            .sort((a, b) => b[1] - a[1])
            .slice(0, 3)
            .map(([cat]) => cat);

          // 计算活跃时段 top 2
          const activeTimeSlots = Object.entries(timeSlotCount)
            .sort((a, b) => b[1] - a[1])
            .slice(0, 2)
            .map(([slot]) => slot);

          // 最近7天搜索关键词
          const sevenDaysAgo = new Date(Date.now() - 7 * 86400000).toISOString();
          const searchKeywords = events
            .filter(e => e.event_type === 'search' && e.occurred_at > sevenDaysAgo)
            .map(e => e.metadata?.query as string)
            .filter(Boolean)
            .slice(0, 10);

          // 去重 hashtags
          const uniqueHashtags = [...new Set(hashtags)].slice(0, 10);

          // 计算平均消费和价格档次
          const avgSpend = purchaseCount > 0 ? totalSpend / purchaseCount : 0;
          const priceTier = avgSpend < 10 ? 'budget' : avgSpend < 30 ? 'mid' : 'premium';
          const purchaseFrequency = purchaseCount < 1 ? 'low' : purchaseCount < 4 ? 'mid' : 'high';

          // upsert 用户标签
          await supabase.from('user_tags').upsert({
            user_id: user.id,
            top_categories: topCategories,
            avg_spend: avgSpend,
            price_tier: priceTier,
            active_time_slots: activeTimeSlots,
            favorite_hashtags: uniqueHashtags,
            purchase_frequency: purchaseFrequency,
            search_keywords: searchKeywords,
            last_updated_at: new Date().toISOString(),
          });

          updatedCount++;
        } catch (err) {
          console.error(`Failed to update tags for user ${user.id}:`, err);
        }
      }));
    }

    return jsonResponse({
      message: 'User tags updated successfully',
      total_users: users.length,
      updated: updatedCount,
    });
  } catch (error) {
    console.error('update-user-tags error:', error);
    return jsonResponse({ error: (error as Error).message }, 500);
  }
});
