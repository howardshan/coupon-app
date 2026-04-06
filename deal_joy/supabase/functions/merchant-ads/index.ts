// ============================================================
// Edge Function: merchant-ads
// 模块: 广告管理（Ads Management）
// 功能: Campaign CRUD + 广告账户余额 + 充值记录 + 广告位配置
//
// 支持的 action:
//   get_account          — 获取广告账户信息（余额 + 活跃 campaign 数）
//   list_campaigns       — 获取 Campaign 列表（支持分页和状态过滤）
//   get_campaign         — 获取单个 Campaign 详情
//   create_campaign      — 创建 Campaign（含出价/余额/目标对象校验）
//   update_campaign      — 更新 Campaign（已消费则只能改日预算和时段；splash 字段始终可改）
//   pause_campaign       — 暂停 Campaign
//   resume_campaign      — 恢复 Campaign（仅 paused 状态可恢复）
//   delete_campaign      — 删除 Campaign（仅 paused/ended 状态可删除）
//   list_recharges       — 充值记录（支持分页）
//   get_placement_config — 获取广告位配置（min_bid / is_enabled 等）
//   get_splash_estimate  — 获取 splash 广告预估覆盖用户数
// ============================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2?target=deno';
import { resolveAuth, requirePermission } from "../_shared/auth.ts";

// ---------- Supabase 客户端（使用 service role，绕过 RLS） ----------
const supabase = createClient(
  Deno.env.get('SUPABASE_URL') ?? '',
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
);

// ---------- 通用 CORS 响应头 ----------
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-merchant-id',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

// ---------- 统一 JSON 响应 ----------
function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

// ---------- 错误响应 ----------
function errorResponse(message: string, status = 400): Response {
  return jsonResponse({ error: message }, status);
}

// ============================================================
// action: get_account — 获取广告账户信息
// 返回 ad_accounts 记录 + 活跃 campaign 数量
// ============================================================
async function handleGetAccount(merchantId: string): Promise<Response> {
  // 查询广告账户信息
  const { data: account, error: accountError } = await supabase
    .from('ad_accounts')
    .select('*')
    .eq('merchant_id', merchantId)
    .maybeSingle();

  if (accountError) {
    console.error('[get_account] 查询 ad_accounts 失败:', accountError);
    return errorResponse('Failed to fetch ad account', 500);
  }

  if (!account) {
    // 账户不存在时返回空账户（正常情况不会发生，trigger 会自动创建）
    return jsonResponse({
      account: null,
      active_campaign_count: 0,
    });
  }

  // 查询活跃 campaign 数量
  const { count: activeCampaignCount, error: countError } = await supabase
    .from('ad_campaigns')
    .select('id', { count: 'exact', head: true })
    .eq('merchant_id', merchantId)
    .eq('status', 'active');

  if (countError) {
    console.error('[get_account] 查询活跃 campaign 数量失败:', countError);
    return errorResponse('Failed to count active campaigns', 500);
  }

  return jsonResponse({
    account,
    active_campaign_count: activeCampaignCount ?? 0,
  });
}

// ============================================================
// action: list_campaigns — 获取 Campaign 列表
// 参数: { status?: string, page?: number, page_size?: number }
// ============================================================
async function handleListCampaigns(
  merchantId: string,
  params: Record<string, unknown>
): Promise<Response> {
  const page = Math.max(1, Number(params.page ?? 1));
  const pageSize = Math.min(50, Math.max(1, Number(params.page_size ?? 20)));
  const offset = (page - 1) * pageSize;
  const statusFilter = params.status as string | undefined;

  let query = supabase
    .from('ad_campaigns')
    .select('*', { count: 'exact' })
    .eq('merchant_id', merchantId)
    .order('created_at', { ascending: false })
    .range(offset, offset + pageSize - 1);

  // 按状态过滤（不传则返回全部）
  if (statusFilter) {
    query = query.eq('status', statusFilter);
  }

  const { data: campaigns, error, count } = await query;

  if (error) {
    console.error('[list_campaigns] 查询失败:', error);
    return errorResponse('Failed to fetch campaigns', 500);
  }

  return jsonResponse({
    campaigns: campaigns ?? [],
    total: count ?? 0,
    page,
    page_size: pageSize,
    total_pages: Math.ceil((count ?? 0) / pageSize),
  });
}

// ============================================================
// action: get_campaign — 获取单个 Campaign 详情
// 参数: { campaign_id: string }
// ============================================================
async function handleGetCampaign(
  merchantId: string,
  params: Record<string, unknown>
): Promise<Response> {
  const campaignId = params.campaign_id as string;
  if (!campaignId) {
    return errorResponse('campaign_id is required');
  }

  const { data: campaign, error } = await supabase
    .from('ad_campaigns')
    .select('*')
    .eq('id', campaignId)
    .maybeSingle();

  if (error) {
    console.error('[get_campaign] 查询失败:', error);
    return errorResponse('Failed to fetch campaign', 500);
  }

  if (!campaign) {
    return errorResponse('Campaign not found', 404);
  }

  // 安全校验：确保 campaign 属于当前商家
  if (campaign.merchant_id !== merchantId) {
    return errorResponse('Unauthorized: campaign does not belong to this merchant', 403);
  }

  return jsonResponse({ campaign });
}

// splash 广告位合法半径列表（单位：米）
const SPLASH_VALID_RADII = [8047, 16093, 24140, 40234];

// ============================================================
// action: create_campaign — 创建 Campaign
// 参数（通用）: { target_type, target_id, placement, category_id?, bid_price,
//               daily_budget, schedule_hours?, start_at?, end_at? }
// 参数（splash 专属）: { creative_url, splash_link_type,
//               splash_link_value?, splash_radius_meters? }
// splash 广告位会自动填充 target_type='store', target_id=merchantId
// ============================================================
async function handleCreateCampaign(
  merchantId: string,
  params: Record<string, unknown>
): Promise<Response> {
  const {
    placement,
    category_id,
    bid_price,
    daily_budget,
    schedule_hours,
    start_at,
    end_at,
    // splash 专属字段
    creative_url,
    splash_link_type,
    splash_link_value,
    splash_radius_meters,
  } = params;

  // splash 广告位特殊处理：自动填充 target_type / target_id，无需前端传入
  const isSplash = placement === 'splash';
  let target_type = params.target_type;
  let target_id = params.target_id;

  if (isSplash) {
    // splash 广告自动绑定到当前商家门店，绕过 NOT NULL 约束
    target_type = 'store';
    target_id = merchantId;
  }

  // 参数完整性校验（splash 时 target_type / target_id 由服务端填充，不强制要求前端传入）
  if (!placement || bid_price == null || daily_budget == null) {
    return errorResponse('Missing required fields: placement, bid_price, daily_budget');
  }
  if (!isSplash && (!target_type || !target_id)) {
    return errorResponse('Missing required fields: target_type, target_id');
  }

  // splash 专属必填校验
  if (isSplash) {
    if (!creative_url || String(creative_url).trim() === '') {
      return errorResponse('creative_url is required for splash placement');
    }
    const validLinkTypes = ['deal', 'merchant', 'external', 'none'];
    if (!splash_link_type || !validLinkTypes.includes(String(splash_link_type))) {
      return errorResponse(
        `splash_link_type is required and must be one of: ${validLinkTypes.join(', ')}`
      );
    }
    // 校验半径合法性（不传则使用默认值 16093）
    if (splash_radius_meters != null && !SPLASH_VALID_RADII.includes(Number(splash_radius_meters))) {
      return errorResponse(
        `splash_radius_meters must be one of: ${SPLASH_VALID_RADII.join(', ')}`
      );
    }
  }

  const bidPriceNum = Number(bid_price);
  const dailyBudgetNum = Number(daily_budget);

  if (isNaN(bidPriceNum) || bidPriceNum <= 0) {
    return errorResponse('bid_price must be a positive number');
  }

  if (isNaN(dailyBudgetNum) || dailyBudgetNum < 10) {
    return errorResponse('daily_budget must be >= 10');
  }

  // 1. 查询广告位配置，校验 min_bid
  const { data: placementConfig, error: configError } = await supabase
    .from('ad_placement_config')
    .select('min_bid')
    .eq('placement', placement)
    .maybeSingle();

  if (configError) {
    console.error('[create_campaign] 查询广告位配置失败:', configError);
    return errorResponse('Failed to fetch placement config', 500);
  }

  if (!placementConfig) {
    return errorResponse(`Invalid placement: ${placement}`);
  }

  if (bidPriceNum < Number(placementConfig.min_bid)) {
    return errorResponse(
      `bid_price must be >= min_bid (${placementConfig.min_bid}) for placement '${placement}'`
    );
  }

  // 2. 校验 target_id 是否属于当前商家
  if (target_type === 'deal') {
    const { data: deal, error: dealError } = await supabase
      .from('deals')
      .select('id, merchant_id')
      .eq('id', target_id as string)
      .maybeSingle();

    if (dealError || !deal) {
      return errorResponse('Deal not found or query failed');
    }

    if (deal.merchant_id !== merchantId) {
      return errorResponse('Unauthorized: deal does not belong to this merchant', 403);
    }
  } else if (target_type === 'store') {
    // store 类型：target_id 必须是该商家自己的 merchant_id
    if ((target_id as string) !== merchantId) {
      return errorResponse('Unauthorized: store target_id must be your own merchant_id', 403);
    }
  } else {
    return errorResponse('Invalid target_type: must be "deal" or "store"');
  }

  // 3. 如果提供了 category_id，校验分类是否存在
  if (category_id != null) {
    const { data: category, error: catError } = await supabase
      .from('categories')
      .select('id')
      .eq('id', Number(category_id))
      .maybeSingle();

    if (catError || !category) {
      return errorResponse(`Category with id ${category_id} not found`);
    }
  }

  // 4. 查询广告账户，校验余额
  const { data: account, error: accountError } = await supabase
    .from('ad_accounts')
    .select('id, balance')
    .eq('merchant_id', merchantId)
    .maybeSingle();

  if (accountError || !account) {
    console.error('[create_campaign] 查询广告账户失败:', accountError);
    return errorResponse('Ad account not found', 500);
  }

  if (Number(account.balance) < dailyBudgetNum) {
    return errorResponse(
      `Insufficient balance: current balance (${account.balance}) must be >= daily_budget (${dailyBudgetNum})`
    );
  }

  // 5. 计算初始 ad_score = bid_price × 0.7（默认 quality_score）
  const initialAdScore = bidPriceNum * 0.7;

  // 6. 构建插入对象（splash 广告额外写入专属字段）
  const insertPayload: Record<string, unknown> = {
    merchant_id:    merchantId,
    ad_account_id:  account.id,
    target_type:    target_type as string,
    target_id:      target_id as string,
    placement:      placement as string,
    category_id:    category_id != null ? Number(category_id) : null,
    bid_price:      bidPriceNum,
    daily_budget:   dailyBudgetNum,
    schedule_hours: schedule_hours ?? null,
    start_at:       start_at ?? new Date().toISOString(),
    end_at:         end_at ?? null,
    status:         'active',
    quality_score:  0.700,
    ad_score:       initialAdScore,
  };

  if (isSplash) {
    // 写入 splash 专属字段
    insertPayload.creative_url = String(creative_url).trim();
    insertPayload.splash_link_type = String(splash_link_type);
    insertPayload.splash_link_value = splash_link_value ?? null;
    // 未传时使用默认半径 16093 米（约 10 英里）
    insertPayload.splash_radius_meters = splash_radius_meters != null
      ? Number(splash_radius_meters)
      : 16093;
  }

  // 7. 插入 ad_campaigns
  const { data: newCampaign, error: insertError } = await supabase
    .from('ad_campaigns')
    .insert(insertPayload)
    .select()
    .single();

  if (insertError) {
    console.error('[create_campaign] 插入失败:', insertError);
    // 同广告位已有活跃 campaign 时会触发唯一索引冲突
    if (insertError.code === '23505') {
      return errorResponse(
        `You already have an active or admin-paused campaign for placement '${placement}'`
      );
    }
    return errorResponse('Failed to create campaign', 500);
  }

  return jsonResponse({ campaign: newCampaign }, 201);
}

// ============================================================
// action: update_campaign — 更新 Campaign
// 参数: { campaign_id, daily_budget?, schedule_hours?, bid_price?,
//         placement?, target_id?, target_type?, category_id?,
//         start_at?, end_at? }
// 规则: total_spend > 0 时只能改 daily_budget 和 schedule_hours
// ============================================================
async function handleUpdateCampaign(
  merchantId: string,
  params: Record<string, unknown>
): Promise<Response> {
  const campaignId = params.campaign_id as string;
  if (!campaignId) {
    return errorResponse('campaign_id is required');
  }

  // 查询当前 campaign
  const { data: campaign, error: fetchError } = await supabase
    .from('ad_campaigns')
    .select('*')
    .eq('id', campaignId)
    .maybeSingle();

  if (fetchError) {
    console.error('[update_campaign] 查询失败:', fetchError);
    return errorResponse('Failed to fetch campaign', 500);
  }

  if (!campaign) {
    return errorResponse('Campaign not found', 404);
  }

  // 安全校验：campaign 属于当前商家
  if (campaign.merchant_id !== merchantId) {
    return errorResponse('Unauthorized: campaign does not belong to this merchant', 403);
  }

  // admin_paused 状态禁止商家修改
  if (campaign.status === 'admin_paused') {
    return errorResponse('Cannot modify an admin-paused campaign');
  }

  const hasSpend = Number(campaign.total_spend) > 0;
  const isSplash = campaign.placement === 'splash';

  // 构建更新字段
  const updates: Record<string, unknown> = {};

  // ---- splash 专属字段：无论是否有消费记录，始终允许编辑 ----
  // creative_url：不可设为 null 或空字符串
  if (params.creative_url !== undefined) {
    if (!isSplash) {
      return errorResponse('creative_url is only applicable to splash placement');
    }
    if (!params.creative_url || String(params.creative_url).trim() === '') {
      return errorResponse('creative_url cannot be set to null or empty');
    }
    updates.creative_url = String(params.creative_url).trim();
  }

  // splash_link_type：合法值校验
  if (params.splash_link_type !== undefined) {
    if (!isSplash) {
      return errorResponse('splash_link_type is only applicable to splash placement');
    }
    const validLinkTypes = ['deal', 'merchant', 'external', 'none'];
    if (!validLinkTypes.includes(String(params.splash_link_type))) {
      return errorResponse(
        `splash_link_type must be one of: ${validLinkTypes.join(', ')}`
      );
    }
    updates.splash_link_type = String(params.splash_link_type);
  }

  // splash_link_value：可为 null
  if (params.splash_link_value !== undefined) {
    if (!isSplash) {
      return errorResponse('splash_link_value is only applicable to splash placement');
    }
    updates.splash_link_value = params.splash_link_value ?? null;
  }

  // splash_radius_meters：只允许合法值
  if (params.splash_radius_meters !== undefined) {
    if (!isSplash) {
      return errorResponse('splash_radius_meters is only applicable to splash placement');
    }
    if (!SPLASH_VALID_RADII.includes(Number(params.splash_radius_meters))) {
      return errorResponse(
        `splash_radius_meters must be one of: ${SPLASH_VALID_RADII.join(', ')}`
      );
    }
    updates.splash_radius_meters = Number(params.splash_radius_meters);
  }

  if (hasSpend) {
    // 已有消费：只允许修改 daily_budget、schedule_hours 和 splash 专属字段
    if (params.daily_budget != null) {
      const dailyBudgetNum = Number(params.daily_budget);
      if (isNaN(dailyBudgetNum) || dailyBudgetNum < 10) {
        return errorResponse('daily_budget must be >= 10');
      }
      updates.daily_budget = dailyBudgetNum;
    }

    if (params.schedule_hours !== undefined) {
      updates.schedule_hours = params.schedule_hours ?? null;
    }

    // 其他受限字段被传入时给出明确错误提示
    const restrictedFields = ['bid_price', 'placement', 'target_id', 'target_type', 'category_id', 'start_at', 'end_at'];
    for (const field of restrictedFields) {
      if (params[field] !== undefined) {
        return errorResponse(
          `Cannot modify '${field}' after campaign has spend. Only daily_budget and schedule_hours are editable.`
        );
      }
    }
  } else {
    // 未消费：允许修改更多字段
    if (params.daily_budget != null) {
      const dailyBudgetNum = Number(params.daily_budget);
      if (isNaN(dailyBudgetNum) || dailyBudgetNum < 10) {
        return errorResponse('daily_budget must be >= 10');
      }
      updates.daily_budget = dailyBudgetNum;
    }

    if (params.schedule_hours !== undefined) {
      updates.schedule_hours = params.schedule_hours ?? null;
    }

    if (params.bid_price != null) {
      const bidPriceNum = Number(params.bid_price);
      if (isNaN(bidPriceNum) || bidPriceNum <= 0) {
        return errorResponse('bid_price must be a positive number');
      }

      // 校验新出价 >= min_bid
      const checkPlacement = (params.placement as string) ?? campaign.placement;
      const { data: config } = await supabase
        .from('ad_placement_config')
        .select('min_bid')
        .eq('placement', checkPlacement)
        .maybeSingle();

      if (config && bidPriceNum < Number(config.min_bid)) {
        return errorResponse(
          `bid_price must be >= min_bid (${config.min_bid}) for placement '${checkPlacement}'`
        );
      }

      updates.bid_price = bidPriceNum;
      // 重新计算 ad_score
      updates.ad_score = bidPriceNum * Number(campaign.quality_score);
    }

    if (params.placement != null) {
      // 验证广告位合法性
      const { data: config } = await supabase
        .from('ad_placement_config')
        .select('min_bid')
        .eq('placement', params.placement as string)
        .maybeSingle();
      if (!config) {
        return errorResponse(`Invalid placement: ${params.placement}`);
      }
      updates.placement = params.placement;
    }

    if (params.target_type != null) {
      if (!['deal', 'store'].includes(params.target_type as string)) {
        return errorResponse('Invalid target_type: must be "deal" or "store"');
      }
      updates.target_type = params.target_type;
    }

    if (params.target_id != null) {
      // 校验新 target_id 属于当前商家
      const newTargetType = (params.target_type as string) ?? campaign.target_type;
      if (newTargetType === 'deal') {
        const { data: deal } = await supabase
          .from('deals')
          .select('merchant_id')
          .eq('id', params.target_id as string)
          .maybeSingle();
        if (!deal || deal.merchant_id !== merchantId) {
          return errorResponse('Unauthorized: deal does not belong to this merchant', 403);
        }
      } else if (newTargetType === 'store') {
        if ((params.target_id as string) !== merchantId) {
          return errorResponse('Unauthorized: store target_id must be your own merchant_id', 403);
        }
      }
      updates.target_id = params.target_id;
    }

    if (params.category_id !== undefined) {
      if (params.category_id != null) {
        const { data: cat } = await supabase
          .from('categories')
          .select('id')
          .eq('id', Number(params.category_id))
          .maybeSingle();
        if (!cat) {
          return errorResponse(`Category with id ${params.category_id} not found`);
        }
        updates.category_id = Number(params.category_id);
      } else {
        updates.category_id = null;
      }
    }

    if (params.start_at !== undefined) {
      updates.start_at = params.start_at;
    }

    if (params.end_at !== undefined) {
      updates.end_at = params.end_at ?? null;
    }
  }

  // 没有任何字段需要更新
  if (Object.keys(updates).length === 0) {
    return errorResponse('No updatable fields provided');
  }

  const { data: updatedCampaign, error: updateError } = await supabase
    .from('ad_campaigns')
    .update(updates)
    .eq('id', campaignId)
    .select()
    .single();

  if (updateError) {
    console.error('[update_campaign] 更新失败:', updateError);
    // 同广告位已有活跃 campaign 时会触发唯一索引冲突
    if (updateError.code === '23505') {
      return errorResponse(
        `Another active or admin-paused campaign already exists for this placement`
      );
    }
    return errorResponse('Failed to update campaign', 500);
  }

  return jsonResponse({ campaign: updatedCampaign });
}

// ============================================================
// action: pause_campaign — 暂停 Campaign
// 参数: { campaign_id }
// 只有 active 或 exhausted 状态可暂停
// ============================================================
async function handlePauseCampaign(
  merchantId: string,
  params: Record<string, unknown>
): Promise<Response> {
  const campaignId = params.campaign_id as string;
  if (!campaignId) {
    return errorResponse('campaign_id is required');
  }

  const { data: campaign, error: fetchError } = await supabase
    .from('ad_campaigns')
    .select('id, merchant_id, status')
    .eq('id', campaignId)
    .maybeSingle();

  if (fetchError || !campaign) {
    return errorResponse('Campaign not found', 404);
  }

  if (campaign.merchant_id !== merchantId) {
    return errorResponse('Unauthorized: campaign does not belong to this merchant', 403);
  }

  // admin_paused 不允许商家操作
  if (campaign.status === 'admin_paused') {
    return errorResponse('Cannot pause an admin-paused campaign');
  }

  if (!['active', 'exhausted'].includes(campaign.status)) {
    return errorResponse(
      `Cannot pause campaign with status '${campaign.status}'. Only active or exhausted campaigns can be paused.`
    );
  }

  const { data: updatedCampaign, error: updateError } = await supabase
    .from('ad_campaigns')
    .update({ status: 'paused' })
    .eq('id', campaignId)
    .select()
    .single();

  if (updateError) {
    console.error('[pause_campaign] 更新失败:', updateError);
    return errorResponse('Failed to pause campaign', 500);
  }

  return jsonResponse({ campaign: updatedCampaign });
}

// ============================================================
// action: resume_campaign — 恢复 Campaign
// 参数: { campaign_id }
// 只有 paused 状态可恢复（admin_paused 不行）
// ============================================================
async function handleResumeCampaign(
  merchantId: string,
  params: Record<string, unknown>
): Promise<Response> {
  const campaignId = params.campaign_id as string;
  if (!campaignId) {
    return errorResponse('campaign_id is required');
  }

  const { data: campaign, error: fetchError } = await supabase
    .from('ad_campaigns')
    .select('id, merchant_id, status, daily_budget')
    .eq('id', campaignId)
    .maybeSingle();

  if (fetchError || !campaign) {
    return errorResponse('Campaign not found', 404);
  }

  if (campaign.merchant_id !== merchantId) {
    return errorResponse('Unauthorized: campaign does not belong to this merchant', 403);
  }

  if (campaign.status === 'admin_paused') {
    return errorResponse('Cannot resume an admin-paused campaign. Contact support.');
  }

  if (campaign.status !== 'paused') {
    return errorResponse(
      `Cannot resume campaign with status '${campaign.status}'. Only paused campaigns can be resumed.`
    );
  }

  // 恢复前检查余额是否足够（至少够一天的日预算）
  const { data: account } = await supabase
    .from('ad_accounts')
    .select('balance')
    .eq('merchant_id', merchantId)
    .maybeSingle();

  if (!account || Number(account.balance) < Number(campaign.daily_budget)) {
    return errorResponse(
      `Insufficient balance to resume. Balance (${account?.balance ?? 0}) must be >= daily_budget (${campaign.daily_budget})`
    );
  }

  const { data: updatedCampaign, error: updateError } = await supabase
    .from('ad_campaigns')
    .update({ status: 'active' })
    .eq('id', campaignId)
    .select()
    .single();

  if (updateError) {
    console.error('[resume_campaign] 更新失败:', updateError);
    // 唯一索引冲突：同广告位已存在活跃 campaign
    if (updateError.code === '23505') {
      return errorResponse(
        'Another active campaign already exists for this placement. Pause it first.'
      );
    }
    return errorResponse('Failed to resume campaign', 500);
  }

  return jsonResponse({ campaign: updatedCampaign });
}

// ============================================================
// action: delete_campaign — 删除 Campaign
// 参数: { campaign_id }
// 只有 paused 或 ended 状态可删除
// ============================================================
async function handleDeleteCampaign(
  merchantId: string,
  params: Record<string, unknown>
): Promise<Response> {
  const campaignId = params.campaign_id as string;
  if (!campaignId) {
    return errorResponse('campaign_id is required');
  }

  const { data: campaign, error: fetchError } = await supabase
    .from('ad_campaigns')
    .select('id, merchant_id, status')
    .eq('id', campaignId)
    .maybeSingle();

  if (fetchError || !campaign) {
    return errorResponse('Campaign not found', 404);
  }

  if (campaign.merchant_id !== merchantId) {
    return errorResponse('Unauthorized: campaign does not belong to this merchant', 403);
  }

  if (!['paused', 'ended'].includes(campaign.status)) {
    return errorResponse(
      `Cannot delete campaign with status '${campaign.status}'. Only paused or ended campaigns can be deleted. Pause active campaigns first.`
    );
  }

  const { error: deleteError } = await supabase
    .from('ad_campaigns')
    .delete()
    .eq('id', campaignId);

  if (deleteError) {
    console.error('[delete_campaign] 删除失败:', deleteError);
    return errorResponse('Failed to delete campaign', 500);
  }

  return jsonResponse({ success: true, deleted_campaign_id: campaignId });
}

// ============================================================
// action: list_recharges — 充值记录
// 参数: { page?: number, page_size?: number }
// ============================================================
async function handleListRecharges(
  merchantId: string,
  params: Record<string, unknown>
): Promise<Response> {
  const page = Math.max(1, Number(params.page ?? 1));
  const pageSize = Math.min(50, Math.max(1, Number(params.page_size ?? 20)));
  const offset = (page - 1) * pageSize;

  const { data: recharges, error, count } = await supabase
    .from('ad_recharges')
    .select('*', { count: 'exact' })
    .eq('merchant_id', merchantId)
    .order('created_at', { ascending: false })
    .range(offset, offset + pageSize - 1);

  if (error) {
    console.error('[list_recharges] 查询失败:', error);
    return errorResponse('Failed to fetch recharges', 500);
  }

  return jsonResponse({
    recharges: recharges ?? [],
    total: count ?? 0,
    page,
    page_size: pageSize,
    total_pages: Math.ceil((count ?? 0) / pageSize),
  });
}

// ============================================================
// action: get_placement_config — 获取广告位配置
// 无需额外参数，返回所有广告位的 min_bid / max_slots / billing_type / is_enabled 等字段
// ============================================================
async function handleGetPlacementConfig(): Promise<Response> {
  // select('*') 已包含 is_enabled，无需额外指定
  const { data: configs, error } = await supabase
    .from('ad_placement_config')
    .select('*')
    .order('min_bid', { ascending: false });

  if (error) {
    console.error('[get_placement_config] 查询失败:', error);
    return errorResponse('Failed to fetch placement config', 500);
  }

  return jsonResponse({ configs: configs ?? [] });
}

// ============================================================
// action: get_splash_estimate — 获取 splash 广告预估覆盖用户数
// 参数: { lat: number, lng: number, radius_meters: number }
// 调用 RPC get_splash_ad_estimate(lat, lng, radius_meters)
// 返回 { estimate: number }
// ============================================================
async function handleGetSplashEstimate(
  params: Record<string, unknown>
): Promise<Response> {
  const { lat, lng, radius_meters } = params;

  // 参数校验
  if (lat == null || lng == null || radius_meters == null) {
    return errorResponse('Missing required fields: lat, lng, radius_meters');
  }

  const latNum = Number(lat);
  const lngNum = Number(lng);
  const radiusNum = Number(radius_meters);

  if (isNaN(latNum) || isNaN(lngNum)) {
    return errorResponse('lat and lng must be valid numbers');
  }

  if (!SPLASH_VALID_RADII.includes(radiusNum)) {
    return errorResponse(
      `radius_meters must be one of: ${SPLASH_VALID_RADII.join(', ')}`
    );
  }

  // 调用 RPC 函数获取预估用户数
  const { data, error } = await supabase.rpc('get_splash_ad_estimate', {
    p_lat: latNum,
    p_lng: lngNum,
    p_radius_meters: radiusNum,
  });

  if (error) {
    console.error('[get_splash_estimate] RPC 调用失败:', error);
    return errorResponse('Failed to get splash estimate', 500);
  }

  return jsonResponse({ estimate: data ?? 0 });
}

// ============================================================
// 主入口
// ============================================================
Deno.serve(async (req: Request) => {
  // 处理 CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  // 只接受 POST 请求
  if (req.method !== 'POST') {
    return errorResponse('Method not allowed', 405);
  }

  // 鉴权：获取 JWT token
  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    return errorResponse('Missing Authorization header', 401);
  }

  const token = authHeader.replace('Bearer ', '');

  let user;
  try {
    const { data, error } = await supabase.auth.getUser(token);
    if (error || !data?.user) {
      return errorResponse('Invalid or expired token', 401);
    }
    user = data.user;
  } catch (e) {
    console.error('[merchant-ads] 鉴权失败:', e);
    return errorResponse('Authentication failed', 401);
  }

  // 解析用户角色和权限（支持 X-Merchant-Id header 门店切换）
  let auth;
  try {
    auth = await resolveAuth(supabase, user.id, req.headers);
    requirePermission(auth, 'marketing'); // 需要 marketing 权限
  } catch (e) {
    const msg = e instanceof Error ? e.message : 'Authorization failed';
    return errorResponse(msg, 403);
  }

  const merchantId = auth.merchantId;

  // 解析请求体
  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return errorResponse('Invalid JSON body');
  }

  const { action, ...params } = body;

  if (!action || typeof action !== 'string') {
    return errorResponse('Missing or invalid "action" field');
  }

  // 路由分发
  try {
    switch (action) {
      case 'get_account':
        return await handleGetAccount(merchantId);

      case 'list_campaigns':
        return await handleListCampaigns(merchantId, params);

      case 'get_campaign':
        return await handleGetCampaign(merchantId, params);

      case 'create_campaign':
        return await handleCreateCampaign(merchantId, params);

      case 'update_campaign':
        return await handleUpdateCampaign(merchantId, params);

      case 'pause_campaign':
        return await handlePauseCampaign(merchantId, params);

      case 'resume_campaign':
        return await handleResumeCampaign(merchantId, params);

      case 'delete_campaign':
        return await handleDeleteCampaign(merchantId, params);

      case 'list_recharges':
        return await handleListRecharges(merchantId, params);

      case 'get_placement_config':
        return await handleGetPlacementConfig();

      case 'get_splash_estimate':
        return await handleGetSplashEstimate(params);

      default:
        return errorResponse(`Unknown action: ${action}`, 400);
    }
  } catch (e) {
    console.error(`[merchant-ads] action=${action} 发生未预期错误:`, e);
    const msg = e instanceof Error ? e.message : 'Internal server error';
    return errorResponse(msg, 500);
  }
});
