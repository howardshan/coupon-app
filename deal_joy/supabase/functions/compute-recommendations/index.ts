// =============================================================
// Edge Function: compute-recommendations
// 每15分钟由 pg_cron 触发，预计算所有活跃用户的推荐列表
// 路由：
//   POST /compute-recommendations — 批量计算推荐
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

// --- 类型定义 ---

interface RecommendationConfig {
  weights: {
    w_relevance: number;
    w_distance: number;
    w_popularity: number;
    w_quality: number;
    w_freshness: number;
    w_time_slot: number;
  };
  // sponsor_boost 已迁移为 max_sponsor_boost，预计算不再使用
  // 广告排名完全由 get-recommendations 实时处理
  diversity_penalty: number;
  max_same_merchant: number;
  cache_ttl_minutes: number;
}

interface MerchantData {
  id: string;
  name: string;
  avg_rating: number | null;
  review_count: number | null;
  lat: number | null;
  lng: number | null;
  avg_redemption_rate: number | null;
  refund_rate: number | null;
}

interface DealData {
  id: string;
  title: string;
  discount_price: number | null;
  category: string | null;
  meal_type: string | null;
  price_tier: string | null;
  merchant_id: string;
  tags: string[];
  created_at: string;
  total_sold: number | null;
  review_count: number | null;
  rating: number | null;
  merchants: MerchantData;
}

interface UserTag {
  user_id: string;
  top_categories: string[];
  avg_spend: number;
  price_tier: string;
  active_time_slots: string[];
  search_keywords: string[];
  location_lat: number | null;
  location_lng: number | null;
}

// --- 工具函数 ---

function getTimeSlot(hour: number): string {
  if (hour >= 6 && hour < 10) return 'breakfast';
  if (hour >= 11 && hour < 14) return 'lunch';
  if (hour >= 14 && hour < 17) return 'afternoon';
  if (hour >= 17 && hour < 21) return 'dinner';
  if (hour >= 21 || hour < 2) return 'late_night';
  return 'other';
}

// Haversine 公式计算两点距离（km）
function haversineDistance(
  lat1: number, lng1: number,
  lat2: number, lng2: number
): number {
  const R = 6371;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLng = (lng2 - lng1) * Math.PI / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
    Math.sin(dLng / 2) * Math.sin(dLng / 2);
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

// --- 各维度评分函数 ---

function computeRelevance(userTag: UserTag | null, deal: DealData): number {
  if (!userTag) return 0.5; // 无用户标签时返回中性值

  let score = 0;

  // 分类偏好匹配 (0.4)
  const categoryMatch = deal.category && userTag.top_categories.includes(deal.category) ? 1.0 : 0.0;
  score += 0.4 * categoryMatch;

  // 价格匹配 (0.2)
  if (userTag.avg_spend > 0 && deal.discount_price) {
    const priceDiff = Math.abs(deal.discount_price - userTag.avg_spend) / userTag.avg_spend;
    score += 0.2 * Math.max(0, 1 - priceDiff);
  } else {
    score += 0.2 * 0.5;
  }

  // 搜索词匹配 (0.2)
  const searchMatch = userTag.search_keywords.some(keyword =>
    deal.title?.toLowerCase().includes(keyword.toLowerCase()) ||
    deal.category?.toLowerCase().includes(keyword.toLowerCase())
  ) ? 1.0 : 0.0;
  score += 0.2 * searchMatch;

  // 标签匹配 (0.2)
  const tagOverlap = deal.tags?.filter(t => userTag.top_categories.includes(t)).length ?? 0;
  score += 0.2 * Math.min(1.0, tagOverlap / 2);

  return Math.min(1.0, Math.max(0, score));
}

function computeDistance(userTag: UserTag | null, merchant: MerchantData): number {
  if (!userTag?.location_lat || !userTag?.location_lng || !merchant.lat || !merchant.lng) {
    return 0.5; // 无位置信息时返回中性值
  }

  const distKm = haversineDistance(
    userTag.location_lat, userTag.location_lng,
    merchant.lat, merchant.lng
  );

  if (distKm <= 1) return 1.0;
  if (distKm <= 3) return 0.9;
  if (distKm <= 5) return 0.75;
  if (distKm <= 10) return 0.5;
  if (distKm <= 20) return 0.3;
  return 0.1;
}

function computePopularity(deal: DealData, maxSold: number, maxReviews: number): number {
  const recentSales = deal.total_sold ?? 0;
  const reviewCount = deal.review_count ?? 0;

  const salesScore = maxSold > 0
    ? Math.log(1 + recentSales) / Math.log(1 + maxSold)
    : 0;
  const viewScore = maxReviews > 0
    ? Math.log(1 + reviewCount) / Math.log(1 + maxReviews)
    : 0;

  return Math.min(1.0, 0.6 * salesScore + 0.4 * viewScore);
}

function computeQuality(merchant: MerchantData): number {
  const avgRating = merchant.avg_rating ?? 0;
  const reviewCount = merchant.review_count ?? 0;
  const refundRate = merchant.refund_rate ?? 0;

  const ratingScore = avgRating / 5.0;
  const reviewScore = Math.min(1.0, Math.log(1 + reviewCount) / Math.log(100));
  const refundScore = 1 - refundRate;

  return 0.5 * ratingScore + 0.3 * reviewScore + 0.2 * refundScore;
}

function computeFreshness(createdAt: string): number {
  const daysSince = (Date.now() - new Date(createdAt).getTime()) / 86400000;

  if (daysSince <= 3) return 1.0;
  if (daysSince <= 7) return 0.8;
  if (daysSince <= 14) return 0.5;
  if (daysSince <= 30) return 0.2;
  return 0.0;
}

function computeTimeSlotScore(mealType: string | null, currentSlot: string, category: string | null): number {
  // 非餐饮类 deal 返回中性分
  const nonFoodCategories = ['beauty', 'entertainment', 'fitness', 'spa', 'SpaAndMassage', 'HairAndBeauty'];
  if (category && nonFoodCategories.some(c => category.toLowerCase().includes(c.toLowerCase()))) {
    return 0.5;
  }

  if (!mealType || mealType === 'n/a') return 0.5;
  if (mealType === 'all_day') return 0.6;

  // 时段匹配
  const slotMealMap: Record<string, string[]> = {
    'breakfast': ['breakfast'],
    'lunch': ['lunch'],
    'afternoon': ['lunch', 'all_day'],
    'dinner': ['dinner'],
    'late_night': ['dinner', 'all_day'],
    'other': [],
  };

  const matchingMeals = slotMealMap[currentSlot] ?? [];
  return matchingMeals.includes(mealType) ? 1.0 : 0.2;
}

// 多样性去重
function applyDiversityPenalty(
  scored: { dealId: string; merchantId: string; score: number }[],
  config: RecommendationConfig
): { dealId: string; score: number }[] {
  const sorted = [...scored].sort((a, b) => b.score - a.score);
  const merchantCount: Record<string, number> = {};

  return sorted.map(item => {
    merchantCount[item.merchantId] = (merchantCount[item.merchantId] ?? 0) + 1;
    const penalty = merchantCount[item.merchantId] > config.max_same_merchant
      ? config.diversity_penalty
      : 0;
    return { dealId: item.dealId, score: item.score + penalty };
  });
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, serviceRoleKey);

    // 1. 读取当前活跃配置
    const { data: configRow } = await supabase
      .from('recommendation_config')
      .select('*')
      .eq('is_active', true)
      .single();

    if (!configRow) {
      return jsonResponse({ error: 'No active recommendation config found' }, 500);
    }

    const config = configRow.weights as RecommendationConfig;

    // 2. 获取30天内有登录记录的活跃用户
    const thirtyDaysAgo = new Date(Date.now() - 30 * 86400000).toISOString();
    const { data: activeUsers } = await supabase
      .from('users')
      .select('id')
      .gt('last_login_at', thirtyDaysAgo);

    // 3. 获取所有活跃 deals（含商家信息）
    const { data: deals, error: dealsError } = await supabase
      .from('deals')
      .select(`
        id, title, discount_price, category, meal_type, price_tier,
        merchant_id, tags, created_at, total_sold, review_count, rating,
        merchants(id, name, avg_rating, review_count, lat, lng,
                 avg_redemption_rate, refund_rate)
      `)
      .eq('is_active', true);

    if (dealsError) throw dealsError;
    if (!deals || deals.length === 0) {
      return jsonResponse({ message: 'No active deals', count: 0 });
    }

    // 计算全局最大值（用于归一化）
    const maxSold = Math.max(...deals.map(d => d.total_sold ?? 0), 1);
    const maxReviews = Math.max(...deals.map(d => d.review_count ?? 0), 1);

    // Dallas 时区的当前时段
    const dallasHour = new Date().toLocaleString('en-US', {
      timeZone: 'America/Chicago',
      hour: 'numeric',
      hour12: false,
    });
    const currentHour = parseInt(dallasHour, 10);
    const timeSlot = getTimeSlot(currentHour);

    // 4. 计算全局热门缓存（冷启动用）
    const globalScored = deals.map(d => {
      const popularity = computePopularity(d as DealData, maxSold, maxReviews);
      const quality = computeQuality((d as DealData).merchants);
      const freshness = computeFreshness(d.created_at);
      const timeScore = computeTimeSlotScore(d.meal_type, timeSlot, d.category);

      // 预计算只做自然排名，不集成广告（广告由 get-recommendations 实时处理）
      const score = 0.35 * popularity + 0.30 * quality + 0.20 * freshness + 0.15 * timeScore;

      return { dealId: d.id, score };
    }).sort((a, b) => b.score - a.score).slice(0, 100);

    // upsert 全局缓存（按时段）
    await supabase.from('recommendation_global_cache').delete().neq('id', '00000000-0000-0000-0000-000000000000');
    const globalSlots = ['all', timeSlot];
    for (const slot of globalSlots) {
      await supabase.from('recommendation_global_cache').insert({
        deal_ids: globalScored.map(d => d.dealId),
        computed_at: new Date().toISOString(),
        time_slot: slot,
      });
    }

    // 5. 分批计算个人推荐
    if (!activeUsers || activeUsers.length === 0) {
      return jsonResponse({
        message: 'Global cache updated, no active users',
        global_deals: globalScored.length,
      });
    }

    let computedCount = 0;
    const batchSize = 50;

    for (let i = 0; i < activeUsers.length; i += batchSize) {
      const batch = activeUsers.slice(i, i + batchSize);

      // 批量获取用户标签
      const userIds = batch.map(u => u.id);
      const { data: userTags } = await supabase
        .from('user_tags')
        .select('*')
        .in('user_id', userIds);

      const tagMap = new Map<string, UserTag>();
      userTags?.forEach(t => tagMap.set(t.user_id, t as UserTag));

      await Promise.all(batch.map(async (user: { id: string }) => {
        try {
          const userTag = tagMap.get(user.id) ?? null;

          const scored = deals.map(deal => {
            const d = deal as DealData;
            const relevance = computeRelevance(userTag, d);
            const distance = computeDistance(userTag, d.merchants);
            const popularity = computePopularity(d, maxSold, maxReviews);
            const quality = computeQuality(d.merchants);
            const freshness = computeFreshness(d.created_at);
            const timeScore = computeTimeSlotScore(d.meal_type, timeSlot, d.category);

            const w = config.weights;
            let score =
              w.w_relevance * relevance +
              w.w_distance * distance +
              w.w_popularity * popularity +
              w.w_quality * quality +
              w.w_freshness * freshness +
              w.w_time_slot * timeScore;

            // 预计算只做自然排名，不集成广告
            return { dealId: d.id, merchantId: d.merchant_id, score };
          });

          const deduplicated = applyDiversityPenalty(scored, config);
          const top100 = deduplicated
            .sort((a, b) => b.score - a.score)
            .slice(0, 100);

          await supabase.from('recommendation_cache').upsert({
            user_id: user.id,
            deal_ids: top100.map(d => d.dealId),
            scores: Object.fromEntries(top100.map(d => [d.dealId, d.score])),
            computed_at: new Date().toISOString(),
            config_version: configRow.version,
          });

          computedCount++;
        } catch (err) {
          console.error(`Failed to compute recommendations for user ${user.id}:`, err);
        }
      }));
    }

    return jsonResponse({
      message: 'Recommendations computed successfully',
      total_users: activeUsers.length,
      computed: computedCount,
      total_deals: deals.length,
      time_slot: timeSlot,
      config_version: configRow.version,
    });
  } catch (error) {
    console.error('compute-recommendations error:', error);
    return jsonResponse({ error: (error as Error).message }, 500);
  }
});
