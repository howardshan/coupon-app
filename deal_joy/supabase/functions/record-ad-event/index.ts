// =============================================================
// Edge Function: record-ad-event
// 记录广告事件（impression / click），并调用 charge_ad_account RPC 扣费
//
// POST /record-ad-event
// Body: { campaign_id, event_type, user_id? }
// =============================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2?target=deno';

// 使用 service role 以便绕过 RLS 写入 ad_events
const supabase = createClient(
  Deno.env.get('SUPABASE_URL') ?? '',
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
);

// CORS 响应头
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

// 统一 JSON 响应工具
const jsonResponse = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });

// 错误响应工具
const errorResponse = (error: string, message: string, status = 400) =>
  jsonResponse({ error, message }, status);

// =============================================================
// 低余额通知（异步，不阻塞主流程）
// =============================================================
function triggerLowBalanceNotification(merchantId: string) {
  // 查询商家 owner 的 user_id，然后发送推送通知
  // 整个过程 fire-and-forget，不 await，不影响主响应
  (async () => {
    try {
      // 查询商家信息
      const { data: merchant } = await supabase
        .from('merchants')
        .select('user_id, name')
        .eq('id', merchantId)
        .single();

      if (!merchant?.user_id) return;

      // 调用推送通知 Edge Function（不 await）
      fetch(`${Deno.env.get('SUPABASE_URL')}/functions/v1/send-push-notification`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`,
        },
        body: JSON.stringify({
          user_id: merchant.user_id,
          type: 'transaction',
          title: 'Low Ad Balance',
          body: `Your ad account balance is running low. Recharge to keep your campaigns active.`,
          data: { type: 'ad_low_balance', merchant_id: merchantId },
        }),
      });
    } catch (_err) {
      // 通知失败不影响主流程，静默处理
    }
  })();
}

// =============================================================
// Deno.serve 主入口
// =============================================================
Deno.serve(async (req: Request) => {
  // OPTIONS 预检请求直接返回
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  // 只允许 POST
  if (req.method !== 'POST') {
    return errorResponse('method_not_allowed', 'Only POST is allowed', 405);
  }

  // -------------------------------------------------------
  // 1. 解析请求体
  // -------------------------------------------------------
  let body: {
    campaign_id?: string;
    event_type?: string;
    user_id?: string;
  };

  try {
    body = await req.json();
  } catch (_err) {
    return errorResponse('invalid_json', 'Request body must be valid JSON');
  }

  const { campaign_id: campaignId, event_type: eventType, user_id: userId } = body;

  // 参数校验
  if (!campaignId) {
    return errorResponse('missing_param', 'campaign_id is required');
  }
  if (!eventType || !['impression', 'click'].includes(eventType)) {
    return errorResponse('invalid_param', 'event_type must be "impression" or "click"');
  }
  // click 事件需要提供 user_id（用于去重）
  if (eventType === 'click' && !userId) {
    return errorResponse('missing_param', 'user_id is required for click events');
  }

  // -------------------------------------------------------
  // 2. 查询 ad_campaigns 获取 campaign 基本信息
  // -------------------------------------------------------
  const { data: campaign, error: campaignError } = await supabase
    .from('ad_campaigns')
    .select('id, merchant_id, bid_price, placement, status, daily_budget, today_spend')
    .eq('id', campaignId)
    .single();

  if (campaignError || !campaign) {
    return errorResponse('campaign_not_found', 'Campaign not found or access denied', 404);
  }

  // 只处理活跃的 campaign
  if (campaign.status !== 'active') {
    return jsonResponse({ success: true, charged: false, reason: 'campaign_not_active' });
  }

  // -------------------------------------------------------
  // 3. 查询 ad_placement_config 获取计费类型
  // -------------------------------------------------------
  const { data: placementConfig, error: placementError } = await supabase
    .from('ad_placement_config')
    .select('billing_type')
    .eq('placement', campaign.placement)
    .single();

  if (placementError || !placementConfig) {
    return errorResponse('placement_not_found', 'Placement config not found', 404);
  }

  const billingType = placementConfig.billing_type; // 'cpm' | 'cpc'

  // -------------------------------------------------------
  // 4. 计算本次事件的费用
  //    - CPC: 每次点击扣 bid_price，impression 不扣费
  //    - CPM: 每次展示扣 bid_price / 1000，click 不扣费
  // -------------------------------------------------------
  let cost: number;

  if (billingType === 'cpc') {
    // CPC 模式：只有点击才扣费，展示不扣费
    if (eventType === 'impression') {
      return jsonResponse({ success: true, charged: false, reason: 'cpc_no_impression_charge' });
    }
    cost = Number(campaign.bid_price);
  } else {
    // CPM 模式：只有展示才扣费，点击不扣费
    if (eventType === 'click') {
      return jsonResponse({ success: true, charged: false, reason: 'cpm_no_click_charge' });
    }
    cost = Number(campaign.bid_price) / 1000;
  }

  // -------------------------------------------------------
  // 5. CPC 点击去重：30 秒内同 user_id + campaign_id 防重复
  // -------------------------------------------------------
  if (billingType === 'cpc' && eventType === 'click' && userId) {
    const { data: recentClick } = await supabase
      .from('ad_events')
      .select('id')
      .eq('campaign_id', campaignId)
      .eq('user_id', userId)
      .eq('event_type', 'click')
      .gt('occurred_at', new Date(Date.now() - 30 * 1000).toISOString())
      .limit(1)
      .maybeSingle();

    if (recentClick) {
      // 30 秒内已有点击记录，视为重复点击，不扣费
      return jsonResponse({ success: true, charged: false, reason: 'duplicate' });
    }
  }

  // -------------------------------------------------------
  // 6. 调用 charge_ad_account RPC 执行扣费事务
  //    RPC 内部完成：余额检查、日预算检查、扣费、写 ad_events、更新统计
  // -------------------------------------------------------
  const { data: chargeResult, error: chargeError } = await supabase.rpc(
    'charge_ad_account',
    {
      p_campaign_id: campaignId,
      p_merchant_id: campaign.merchant_id,
      p_cost: cost,
      p_event_type: eventType,
      p_user_id: userId ?? null,
    },
  );

  if (chargeError) {
    console.error('[record-ad-event] charge_ad_account RPC error:', chargeError.message);
    return errorResponse('charge_failed', 'Failed to charge ad account', 500);
  }

  // -------------------------------------------------------
  // 7. 根据 RPC 返回状态码决定响应
  // -------------------------------------------------------
  const status = chargeResult as string;

  if (status === 'ok') {
    return jsonResponse({ success: true, charged: true });
  }

  if (status === 'ok_low_balance') {
    // 余额已低，异步触发低余额通知（不阻塞响应）
    triggerLowBalanceNotification(campaign.merchant_id);
    return jsonResponse({ success: true, charged: true });
  }

  if (status === 'insufficient_balance') {
    return jsonResponse({ success: true, charged: false, reason: 'insufficient_balance' });
  }

  if (status === 'daily_budget_exceeded') {
    return jsonResponse({ success: true, charged: false, reason: 'daily_budget_exceeded' });
  }

  // 未知状态码兜底
  console.error('[record-ad-event] unexpected charge status:', status);
  return errorResponse('unexpected_status', `Unexpected charge result: ${status}`, 500);
});
