// =============================================================
// Edge Function: merchant-ad-reports
// 商家广告数据报告查询 API
//
// 支持的 action（POST body: { action, ...params }）：
//   overview        — 广告总览（今日消耗、累计消耗、余额等）
//   campaign_stats  — 单个 Campaign 统计（汇总 + 每日明细）
//   daily_trend     — 所有 Campaign 按日趋势聚合
//   top_campaigns   — 消费排行 Top 10
//
// 鉴权：需要 analytics 权限
// =============================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2?target=deno';
import { resolveAuth, requirePermission } from '../_shared/auth.ts';

// 使用 service role 创建 Supabase 客户端，绕过 RLS 直接操作数据
const supabase = createClient(
  Deno.env.get('SUPABASE_URL') ?? '',
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
);

// CORS 响应头（支持 Flutter App 跨域调用）
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, x-merchant-id',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

// 统一 JSON 响应工具函数
const jsonResponse = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });

// 错误响应工具函数
const errorResponse = (error: string, message: string, status = 400) =>
  jsonResponse({ error, message }, status);

// =============================================================
// Deno.serve 主入口
// =============================================================
Deno.serve(async (req: Request) => {
  // OPTIONS 预检请求直接返回
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  // 只允许 POST 方法
  if (req.method !== 'POST') {
    return errorResponse('method_not_allowed', 'Only POST is supported', 405);
  }

  // 校验 Authorization header
  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    return errorResponse('unauthorized', 'Missing Authorization header', 401);
  }

  try {
    // 从 JWT 获取当前用户
    const token = authHeader.replace('Bearer ', '');
    const { data: { user }, error: userError } = await supabase.auth.getUser(token);
    if (userError || !user) {
      return errorResponse('unauthorized', 'Invalid or expired token', 401);
    }

    // 解析鉴权信息并校验 analytics 权限
    const auth = await resolveAuth(supabase, user.id, req.headers);
    requirePermission(auth, 'analytics');
    const merchantId = auth.merchantId;

    // 解析请求体
    let body: Record<string, unknown>;
    try {
      body = await req.json();
    } catch {
      return errorResponse('invalid_json', 'Request body must be valid JSON', 400);
    }

    const action = body.action as string;
    if (!action) {
      return errorResponse('missing_action', 'action field is required', 400);
    }

    // 路由分发
    switch (action) {
      case 'overview':
        return await handleOverview(merchantId);

      case 'campaign_stats':
        return await handleCampaignStats(
          merchantId,
          body.campaign_id as string,
          body.start_date as string | undefined,
          body.end_date as string | undefined,
        );

      case 'daily_trend':
        return await handleDailyTrend(
          merchantId,
          body.start_date as string | undefined,
          body.end_date as string | undefined,
          body.campaign_id as string | undefined,
        );

      case 'top_campaigns':
        return await handleTopCampaigns(
          merchantId,
          (body.period as string) ?? '7d',
        );

      default:
        return errorResponse('unknown_action', `Unknown action: ${action}`, 400);
    }
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);

    // 权限不足
    if (message.startsWith('Forbidden:')) {
      return errorResponse('forbidden', message, 403);
    }
    // 商家未找到
    if (message.includes('No merchant found')) {
      return errorResponse('merchant_not_found', message, 404);
    }
    // 跨商家访问
    if (message.startsWith('Unauthorized:')) {
      return errorResponse('unauthorized', message, 403);
    }

    console.error('[merchant-ad-reports] Unexpected error:', err);
    return errorResponse('internal_error', 'Internal server error', 500);
  }
});

// =============================================================
// handleOverview — 广告总览
// 返回：今日消耗、今日展示/点击、历史总消费、活跃 Campaign 数、账户余额
// =============================================================
async function handleOverview(merchantId: string): Promise<Response> {
  // 查询广告账户余额和累计消费
  const { data: account, error: accountError } = await supabase
    .from('ad_accounts')
    .select('balance, total_spent, total_recharged')
    .eq('merchant_id', merchantId)
    .maybeSingle();

  if (accountError) {
    console.error('[handleOverview] 查询广告账户失败:', accountError);
    return errorResponse('db_error', accountError.message, 500);
  }

  // 查询所有 active 状态的 Campaign，汇总今日数据
  const { data: campaigns, error: campaignError } = await supabase
    .from('ad_campaigns')
    .select(
      'id, status, today_spend, today_impressions, today_clicks, total_spend, placement, target_type'
    )
    .eq('merchant_id', merchantId)
    .in('status', ['active', 'paused', 'exhausted', 'admin_paused']);

  if (campaignError) {
    console.error('[handleOverview] 查询 campaigns 失败:', campaignError);
    return errorResponse('db_error', campaignError.message, 500);
  }

  const allCampaigns = campaigns ?? [];

  // 汇总今日数据（仅 active 状态的 campaign 有今日数据意义，但全部汇总）
  const todaySpend = allCampaigns.reduce(
    (sum, c) => sum + (Number(c.today_spend) ?? 0), 0
  );
  const todayImpressions = allCampaigns.reduce(
    (sum, c) => sum + (Number(c.today_impressions) ?? 0), 0
  );
  const todayClicks = allCampaigns.reduce(
    (sum, c) => sum + (Number(c.today_clicks) ?? 0), 0
  );

  // 活跃中的 Campaign 数量（status = active）
  const activeCampaignsCount = allCampaigns.filter(
    (c) => c.status === 'active'
  ).length;

  return jsonResponse({
    today_spend: Math.round(todaySpend * 100) / 100,
    today_impressions: todayImpressions,
    today_clicks: todayClicks,
    total_spend: Math.round(Number(account?.total_spent ?? 0) * 100) / 100,
    active_campaigns_count: activeCampaignsCount,
    account_balance: Math.round(Number(account?.balance ?? 0) * 100) / 100,
  });
}

// =============================================================
// handleCampaignStats — 单个 Campaign 统计
// 参数：campaign_id（必填）、start_date、end_date（可选，默认最近7天）
// 返回：汇总数据 + 每日明细 + 今日实时数据
// =============================================================
async function handleCampaignStats(
  merchantId: string,
  campaignId: string | undefined,
  startDate: string | undefined,
  endDate: string | undefined,
): Promise<Response> {
  // 校验必填参数
  if (!campaignId) {
    return errorResponse('missing_param', 'campaign_id is required', 400);
  }

  // 查询 Campaign，同时校验归属当前商家（安全隔离）
  const { data: campaign, error: campaignError } = await supabase
    .from('ad_campaigns')
    .select(
      'id, merchant_id, placement, target_type, target_id, status, ' +
      'today_spend, today_impressions, today_clicks, ' +
      'total_spend, total_impressions, total_clicks, ' +
      'bid_price, daily_budget, quality_score, ad_score, ' +
      'start_at, end_at, created_at'
    )
    .eq('id', campaignId)
    .eq('merchant_id', merchantId)  // 严格过滤，不允许跨商家查询
    .maybeSingle();

  if (campaignError) {
    console.error('[handleCampaignStats] 查询 campaign 失败:', campaignError);
    return errorResponse('db_error', campaignError.message, 500);
  }

  if (!campaign) {
    return errorResponse('not_found', 'Campaign not found or access denied', 404);
  }

  // 计算日期范围（默认最近7天）
  const now = new Date();
  const defaultEnd = now.toISOString().split('T')[0];
  const defaultStart = new Date(now.setDate(now.getDate() - 6))
    .toISOString()
    .split('T')[0];

  const queryStart = startDate ?? defaultStart;
  const queryEnd = endDate ?? defaultEnd;

  // 从 ad_daily_stats 查询每日明细，按日期升序排序
  const { data: dailyStats, error: statsError } = await supabase
    .from('ad_daily_stats')
    .select('date, impressions, clicks, spend, conversions, avg_position')
    .eq('campaign_id', campaignId)
    .eq('merchant_id', merchantId)  // 双重过滤保障安全
    .gte('date', queryStart)
    .lte('date', queryEnd)
    .order('date', { ascending: true });

  if (statsError) {
    console.error('[handleCampaignStats] 查询每日统计失败:', statsError);
    return errorResponse('db_error', statsError.message, 500);
  }

  const stats = dailyStats ?? [];

  // 计算时间范围内的汇总数据
  const totalImpressions = stats.reduce(
    (sum, s) => sum + (Number(s.impressions) ?? 0), 0
  );
  const totalClicks = stats.reduce(
    (sum, s) => sum + (Number(s.clicks) ?? 0), 0
  );
  const totalSpend = stats.reduce(
    (sum, s) => sum + (Number(s.spend) ?? 0), 0
  );
  // 平均 CTR = 总点击 / 总展示（避免除零）
  const avgCtr = totalImpressions > 0
    ? Math.round((totalClicks / totalImpressions) * 10000) / 100  // 转为百分比，保留2位
    : 0;

  return jsonResponse({
    campaign: {
      id: campaign.id,
      placement: campaign.placement,
      target_type: campaign.target_type,
      target_id: campaign.target_id,
      status: campaign.status,
      bid_price: Number(campaign.bid_price),
      daily_budget: Number(campaign.daily_budget),
      quality_score: Number(campaign.quality_score),
      ad_score: Number(campaign.ad_score),
      start_at: campaign.start_at,
      end_at: campaign.end_at,
      created_at: campaign.created_at,
    },
    // 查询时间段内的汇总数据
    summary: {
      period_start: queryStart,
      period_end: queryEnd,
      total_impressions: totalImpressions,
      total_clicks: totalClicks,
      total_spend: Math.round(totalSpend * 100) / 100,
      avg_ctr: avgCtr,
    },
    // 每日明细
    daily: stats.map((s) => ({
      date: s.date,
      impressions: Number(s.impressions) ?? 0,
      clicks: Number(s.clicks) ?? 0,
      spend: Math.round(Number(s.spend) * 100) / 100,
      ctr: (Number(s.impressions) ?? 0) > 0
        ? Math.round((Number(s.clicks) / Number(s.impressions)) * 10000) / 100
        : 0,
      conversions: Number(s.conversions) ?? 0,
      avg_position: s.avg_position != null ? Number(s.avg_position) : null,
    })),
    // 今日实时数据（直接从 ad_campaigns 字段读取）
    today: {
      spend: Math.round(Number(campaign.today_spend) * 100) / 100,
      impressions: Number(campaign.today_impressions) ?? 0,
      clicks: Number(campaign.today_clicks) ?? 0,
    },
  });
}

// =============================================================
// handleDailyTrend — 所有 Campaign 按日趋势
// 参数：start_date、end_date（可选，默认最近30天）、campaign_id（可选过滤）
// 从 ad_daily_stats 按 date 聚合，返回每日汇总
// =============================================================
async function handleDailyTrend(
  merchantId: string,
  startDate: string | undefined,
  endDate: string | undefined,
  campaignId: string | undefined,
): Promise<Response> {
  // 计算默认日期范围（最近30天）
  const now = new Date();
  const defaultEnd = now.toISOString().split('T')[0];
  const defaultStart = new Date(
    new Date().setDate(now.getDate() - 29)
  ).toISOString().split('T')[0];

  const queryStart = startDate ?? defaultStart;
  const queryEnd = endDate ?? defaultEnd;

  // 构建查询
  let query = supabase
    .from('ad_daily_stats')
    .select('date, impressions, clicks, spend')
    .eq('merchant_id', merchantId)  // 严格限制只查当前商家数据
    .gte('date', queryStart)
    .lte('date', queryEnd)
    .order('date', { ascending: true });

  // 可选按单个 Campaign 过滤
  if (campaignId) {
    query = query.eq('campaign_id', campaignId);
  }

  const { data: rows, error } = await query;

  if (error) {
    console.error('[handleDailyTrend] 查询每日趋势失败:', error);
    return errorResponse('db_error', error.message, 500);
  }

  // 按日期聚合（同一天可能有多个 Campaign 的数据）
  const aggregated: Record<
    string,
    { date: string; impressions: number; clicks: number; spend: number }
  > = {};

  for (const row of (rows ?? [])) {
    const date = row.date as string;
    if (!aggregated[date]) {
      aggregated[date] = { date, impressions: 0, clicks: 0, spend: 0 };
    }
    aggregated[date].impressions += Number(row.impressions) ?? 0;
    aggregated[date].clicks += Number(row.clicks) ?? 0;
    aggregated[date].spend += Number(row.spend) ?? 0;
  }

  // 转为升序数组并计算每日 CTR
  const trend = Object.values(aggregated)
    .sort((a, b) => a.date.localeCompare(b.date))
    .map((d) => ({
      date: d.date,
      impressions: d.impressions,
      clicks: d.clicks,
      spend: Math.round(d.spend * 100) / 100,
      ctr: d.impressions > 0
        ? Math.round((d.clicks / d.impressions) * 10000) / 100
        : 0,
    }));

  return jsonResponse({
    period_start: queryStart,
    period_end: queryEnd,
    data: trend,
  });
}

// =============================================================
// handleTopCampaigns — 消费排行 Top 10
// 参数：period（'7d' | '30d' | 'all'，默认 '7d'）
// 按 spend DESC 返回消费最高的 10 个 Campaign
// =============================================================
async function handleTopCampaigns(
  merchantId: string,
  period: string,
): Promise<Response> {
  // 校验 period 参数
  if (!['7d', '30d', 'all'].includes(period)) {
    return errorResponse(
      'invalid_param',
      "period must be '7d', '30d', or 'all'",
      400
    );
  }

  // 根据 period 计算起始日期
  let sinceDate: string | null = null;
  if (period !== 'all') {
    const days = period === '7d' ? 7 : 30;
    const since = new Date();
    since.setDate(since.getDate() - (days - 1));
    sinceDate = since.toISOString().split('T')[0];
  }

  if (period === 'all') {
    // all 模式：直接查 ad_campaigns 的累计字段（total_spend, total_clicks, total_impressions）
    const { data: campaigns, error } = await supabase
      .from('ad_campaigns')
      .select(
        'id, placement, target_type, target_id, status, ' +
        'total_spend, total_impressions, total_clicks, bid_price, created_at'
      )
      .eq('merchant_id', merchantId)  // 严格过滤当前商家
      .order('total_spend', { ascending: false })
      .limit(10);

    if (error) {
      console.error('[handleTopCampaigns] 查询 campaigns 失败:', error);
      return errorResponse('db_error', error.message, 500);
    }

    const result = (campaigns ?? []).map((c, index) => ({
      rank: index + 1,
      campaign_id: c.id,
      placement: c.placement,
      target_type: c.target_type,
      target_id: c.target_id,
      status: c.status,
      total_spend: Math.round(Number(c.total_spend) * 100) / 100,
      total_clicks: Number(c.total_impressions) ?? 0,
      ctr: (Number(c.total_impressions) ?? 0) > 0
        ? Math.round(
            (Number(c.total_clicks) / Number(c.total_impressions)) * 10000
          ) / 100
        : 0,
      bid_price: Number(c.bid_price),
      created_at: c.created_at,
    }));

    return jsonResponse({ period, data: result });
  }

  // 7d / 30d 模式：从 ad_daily_stats 聚合指定时间段内的消费
  const { data: stats, error: statsError } = await supabase
    .from('ad_daily_stats')
    .select('campaign_id, impressions, clicks, spend')
    .eq('merchant_id', merchantId)  // 严格过滤当前商家
    .gte('date', sinceDate!);

  if (statsError) {
    console.error('[handleTopCampaigns] 查询 ad_daily_stats 失败:', statsError);
    return errorResponse('db_error', statsError.message, 500);
  }

  // 按 campaign_id 聚合
  const campaignAgg: Record<
    string,
    { impressions: number; clicks: number; spend: number }
  > = {};

  for (const row of (stats ?? [])) {
    const cid = row.campaign_id as string;
    if (!campaignAgg[cid]) {
      campaignAgg[cid] = { impressions: 0, clicks: 0, spend: 0 };
    }
    campaignAgg[cid].impressions += Number(row.impressions) ?? 0;
    campaignAgg[cid].clicks += Number(row.clicks) ?? 0;
    campaignAgg[cid].spend += Number(row.spend) ?? 0;
  }

  if (Object.keys(campaignAgg).length === 0) {
    return jsonResponse({ period, data: [] });
  }

  // 按 spend DESC 取 Top 10
  const topCampaignIds = Object.entries(campaignAgg)
    .sort(([, a], [, b]) => b.spend - a.spend)
    .slice(0, 10)
    .map(([id]) => id);

  // 批量查询 Campaign 基本信息（placement, target_type 等）
  const { data: campaigns, error: campaignError } = await supabase
    .from('ad_campaigns')
    .select('id, placement, target_type, target_id, status, bid_price')
    .in('id', topCampaignIds)
    .eq('merchant_id', merchantId);  // 再次过滤，确保跨商家安全

  if (campaignError) {
    console.error('[handleTopCampaigns] 查询 campaign 详情失败:', campaignError);
    return errorResponse('db_error', campaignError.message, 500);
  }

  // 合并聚合数据和 Campaign 基本信息，按 spend 降序排列
  const campaignMap = new Map(
    (campaigns ?? []).map((c) => [c.id, c])
  );

  const result = topCampaignIds
    .map((cid, index) => {
      const agg = campaignAgg[cid];
      const info = campaignMap.get(cid);
      if (!info) return null;

      return {
        rank: index + 1,
        campaign_id: cid,
        placement: info.placement,
        target_type: info.target_type,
        target_id: info.target_id,
        status: info.status,
        total_spend: Math.round(agg.spend * 100) / 100,
        total_clicks: agg.clicks,
        ctr: agg.impressions > 0
          ? Math.round((agg.clicks / agg.impressions) * 10000) / 100
          : 0,
        bid_price: Number(info.bid_price),
      };
    })
    .filter(Boolean);

  return jsonResponse({ period, data: result });
}
