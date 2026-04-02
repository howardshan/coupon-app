// =============================================================
// Edge Function: get-recommendations
// App 首页调用：读取预计算缓存 + 实时位置/时段微调
// 路由：
//   POST /get-recommendations — 获取个性化推荐列表
//     body: { lat?, lng?, limit? }
//     返回: { deals, timeSlot, cached }
// 认证：Bearer JWT（用户）或 SERVICE_ROLE_KEY
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

function errorResponse(message: string, status = 400): Response {
  return jsonResponse({ error: message }, status);
}

function getTimeSlot(hour: number): string {
  if (hour >= 6 && hour < 10) return 'breakfast';
  if (hour >= 11 && hour < 14) return 'lunch';
  if (hour >= 14 && hour < 17) return 'afternoon';
  if (hour >= 17 && hour < 21) return 'dinner';
  if (hour >= 21 || hour < 2) return 'late_night';
  return 'other';
}

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

function getDistanceScore(distKm: number): number {
  if (distKm <= 1) return 1.0;
  if (distKm <= 3) return 0.9;
  if (distKm <= 5) return 0.75;
  if (distKm <= 10) return 0.5;
  if (distKm <= 20) return 0.3;
  return 0.1;
}

function computeTimeSlotScore(mealType: string | null, currentSlot: string, category: string | null): number {
  const nonFoodCategories = ['beauty', 'entertainment', 'fitness', 'spa', 'SpaAndMassage', 'HairAndBeauty'];
  if (category && nonFoodCategories.some(c => category.toLowerCase().includes(c.toLowerCase()))) {
    return 0.5;
  }
  if (!mealType || mealType === 'n/a') return 0.5;
  if (mealType === 'all_day') return 0.6;

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

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

    // 用 service_role 读缓存和配置
    const supabase = createClient(supabaseUrl, serviceRoleKey);

    // 从 JWT 获取用户 ID
    const authHeader = req.headers.get('Authorization') ?? '';
    let userId: string | null = null;

    if (authHeader.startsWith('Bearer ')) {
      const token = authHeader.replace('Bearer ', '');
      // 尝试获取用户信息
      const userClient = createClient(supabaseUrl, Deno.env.get('SUPABASE_ANON_KEY')!, {
        global: { headers: { Authorization: `Bearer ${token}` } },
      });
      const { data: { user } } = await userClient.auth.getUser();
      userId = user?.id ?? null;
    }

    const body = await req.json().catch(() => ({}));
    const lat = body.lat as number | undefined;
    const lng = body.lng as number | undefined;
    const limit = Math.min(body.limit ?? 20, 50);

    // Dallas 时区的当前时段
    const dallasHour = new Date().toLocaleString('en-US', {
      timeZone: 'America/Chicago',
      hour: 'numeric',
      hour12: false,
    });
    const currentHour = parseInt(dallasHour, 10);
    const timeSlot = getTimeSlot(currentHour);

    // 1. 尝试读取个人推荐缓存
    let cachedDealIds: string[] = [];
    let cachedScores: Record<string, number> = {};
    let isCached = false;

    if (userId) {
      const { data: cache } = await supabase
        .from('recommendation_cache')
        .select('deal_ids, scores')
        .eq('user_id', userId)
        .single();

      if (cache && cache.deal_ids?.length > 0) {
        cachedDealIds = cache.deal_ids;
        cachedScores = (cache.scores as Record<string, number>) ?? {};
        isCached = true;
      }
    }

    // 2. 冷启动：无缓存或新用户，用全局热门
    if (cachedDealIds.length === 0) {
      const { data: globalCache } = await supabase
        .from('recommendation_global_cache')
        .select('deal_ids')
        .eq('time_slot', timeSlot)
        .order('computed_at', { ascending: false })
        .limit(1)
        .single();

      if (globalCache) {
        cachedDealIds = globalCache.deal_ids;
      } else {
        // 回退到 'all' 时段
        const { data: allCache } = await supabase
          .from('recommendation_global_cache')
          .select('deal_ids')
          .eq('time_slot', 'all')
          .order('computed_at', { ascending: false })
          .limit(1)
          .single();

        if (allCache) {
          cachedDealIds = allCache.deal_ids;
        }
      }
    }

    // 3. 如果依然没有推荐（系统刚启动），直接查活跃 deals
    if (cachedDealIds.length === 0) {
      const { data: fallbackDeals } = await supabase
        .from('deals')
        .select(`
          id, title, description, original_price, discount_price, discount_percent,
          image_urls, category, merchant_id, is_featured, rating, review_count,
          total_sold, created_at, expires_at, meal_type,
          merchants!inner(id, name, logo_url, phone, lat, lng, avg_rating, category)
        `)
        .eq('is_active', true)
        .order('is_featured', { ascending: false })
        .order('total_sold', { ascending: false })
        .limit(limit);

      return jsonResponse({
        deals: fallbackDeals ?? [],
        timeSlot,
        cached: false,
        source: 'fallback',
      });
    }

    // 4. 取前50条候选，查询完整 deal 信息
    const candidateIds = cachedDealIds.slice(0, 50);
    const { data: deals } = await supabase
      .from('deals')
      .select(`
        id, title, description, original_price, discount_price, discount_percent,
        image_urls, category, merchant_id, is_featured, rating, review_count,
        total_sold, created_at, expires_at, meal_type, tags,
        discount_label, dishes, merchant_hours, lat, lng, address,
        deal_type, badge_text, sort_order,
        merchants!inner(id, name, logo_url, phone, lat, lng, avg_rating, review_count, category,
                        homepage_cover_url, brand_id, brand_name, brand_logo_url)
      `)
      .in('id', candidateIds)
      .eq('is_active', true);

    if (!deals || deals.length === 0) {
      return jsonResponse({ deals: [], timeSlot, cached: false, source: 'empty' });
    }

    // 5. 读取活跃配置
    const { data: configRow } = await supabase
      .from('recommendation_config')
      .select('weights')
      .eq('is_active', true)
      .single();

    const config = configRow?.weights as { weights: Record<string, number> } | null;
    const wDistance = config?.weights?.w_distance ?? 0.20;
    const wTimeSlot = config?.weights?.w_time_slot ?? 0.05;

    // 6. 实时微调：位置和时段
    const reranked = deals.map(deal => {
      let score = cachedScores[deal.id] ?? 0.5;

      // 实时位置调整
      if (lat && lng && deal.merchants?.lat && deal.merchants?.lng) {
        const distKm = haversineDistance(lat, lng, deal.merchants.lat, deal.merchants.lng);
        const distScore = getDistanceScore(distKm);
        score = score * 0.8 + wDistance * distScore * 0.2;
      }

      // 实时时段调整
      const timeScore = computeTimeSlotScore(deal.meal_type, timeSlot, deal.category);
      score = score * 0.9 + wTimeSlot * timeScore * 0.1;

      return { ...deal, _finalScore: score };
    });

    // 7. 动态广告注入（实时查询活跃广告，替代旧的 is_sponsored 固定置顶）
    const maxSponsorBoost = (config?.weights as Record<string, number>)?.max_sponsor_boost ?? 200;

    // 查询首页 Deal 广告位的活跃广告
    const { data: activeAds } = await supabase.rpc('get_active_ads', {
      p_placement: 'home_deal_top',
      p_category_id: null,
      p_limit: 3,
    });

    // 构建广告 deal 映射：target_id → campaign 信息
    const adMap = new Map<string, { campaignId: string; adScore: number }>();
    if (activeAds) {
      for (const ad of activeAds) {
        if (ad.target_type === 'deal') {
          adMap.set(ad.target_id, {
            campaignId: ad.campaign_id,
            adScore: Math.min(ad.ad_score, maxSponsorBoost),
          });
        }
      }
    }

    // 按分数排序，广告 deal 加上 ad_score boost
    const finalRanked = reranked.map(deal => {
      const adInfo = adMap.get(deal.id);
      return {
        ...deal,
        _finalScore: deal._finalScore + (adInfo?.adScore ?? 0),
        isSponsored: !!adInfo,
        campaignId: adInfo?.campaignId ?? null,
      };
    }).sort((a, b) => b._finalScore - a._finalScore);

    // 取 top N
    const result = finalRanked.slice(0, limit);

    // 移除内部评分字段，保留 isSponsored 和 campaignId
    const cleanResult = result.map(({ _finalScore, ...rest }) => rest);

    // 异步记录广告 impression（不阻塞响应）
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const svcKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    for (const deal of cleanResult) {
      if (deal.isSponsored && deal.campaignId) {
        fetch(`${supabaseUrl}/functions/v1/record-ad-event`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${svcKey}`,
          },
          body: JSON.stringify({
            campaign_id: deal.campaignId,
            event_type: 'impression',
            user_id: userId,
          }),
        }).catch(err => console.error('记录 impression 失败:', err));
      }
    }

    return jsonResponse({
      deals: cleanResult,
      timeSlot,
      cached: isCached,
      source: isCached ? 'personalized' : 'global',
    });
  } catch (error) {
    console.error('get-recommendations error:', error);
    return errorResponse((error as Error).message, 500);
  }
});
