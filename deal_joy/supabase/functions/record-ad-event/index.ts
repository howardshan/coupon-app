// =============================================================
// Edge Function: record-ad-event
// 记录广告事件（impression / click / skip），并调用 charge_ad_account RPC 扣费
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
  // skip 是新增事件类型，用于记录用户跳过开屏广告的行为（不扣费）
  if (!eventType || !['impression', 'click', 'skip'].includes(eventType)) {
    return errorResponse('invalid_param', 'event_type must be "impression", "click", or "skip"');
  }
  // click 事件需要提供 user_id（已登录用户用于去重；未登录用户也允许，跳过去重）
  // impression / skip 事件无需 user_id

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
    if (eventType === 'impression' || eventType === 'skip') {
      // CPC 模式下 impression / skip 不扣费，但仍需写库以更新今日展示计数器
      // p_cost = 0 表示不扣余额，charge_ad_account 内部 CASE WHEN 会根据 event_type 更新对应计数器
      const { data: recordResult, error: recordError } = await supabase.rpc(
        'charge_ad_account',
        {
          p_campaign_id: campaignId,
          p_merchant_id: campaign.merchant_id,
          p_cost: 0,
          p_event_type: eventType,
          p_user_id: userId ?? null,
        },
      );

      if (recordError) {
        console.error('[record-ad-event] charge_ad_account RPC error (cpc impression/skip):', recordError.message);
        return errorResponse('record_failed', 'Failed to record ad event', 500);
      }

      // charge_ad_account 返回 jsonb，impression/skip 路径只需取 status 字段用于日志
      const recordResultJson = recordResult as { status: string; balance_after: number };
      const recordStatus = recordResultJson?.status ?? String(recordResult);
      // impression/skip 写库不做余额判断，RPC 返回任意状态都视为成功
      console.log(`[record-ad-event] cpc ${eventType} recorded, rpc status: ${recordStatus}`);
      return jsonResponse({
        success: true,
        charged: false,
        reason: eventType === 'impression' ? 'cpc_impression_recorded' : 'cpc_skip_recorded',
      });
    }
    // CPC 模式下点击扣费
    cost = Number(campaign.bid_price);
  } else {
    // CPM 模式：只有展示才扣费，点击 / skip 不扣费
    if (eventType === 'click' || eventType === 'skip') {
      return jsonResponse({ success: true, charged: false, reason: 'cpm_no_click_charge' });
    }
    cost = Number(campaign.bid_price) / 1000;
  }

  // -------------------------------------------------------
  // 5. CPC 点击去重：30 秒内同 user_id + campaign_id 防重复
  // -------------------------------------------------------
  // CPC 点击去重：仅在 userId 存在时检查 30 秒内是否重复点击
  // 未登录用户（userId 为空）跳过去重，直接走扣费流程
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
  // 7. 根据 RPC 返回的 jsonb 决定响应
  //    charge_ad_account 现在返回 { status: string; balance_after: number }
  // -------------------------------------------------------
  const chargeResultJson = chargeResult as { status: string; balance_after: number };
  const chargeStatus = chargeResultJson?.status ?? String(chargeResult);
  const balanceAfter = chargeResultJson?.balance_after ?? 0;

  if (chargeStatus === 'ok') {
    // CPC 点击扣费成功，写入 click_charged 日志（fire-and-forget）
    if (billingType === 'cpc' && eventType === 'click') {
      try {
        await supabase.from('ad_campaign_logs').insert({
          campaign_id: campaignId,
          merchant_id: campaign.merchant_id,
          actor_type: 'system',
          event_type: 'click_charged',
          detail: { cost: cost, balance_after: balanceAfter, user_id: userId ?? null },
        });
      } catch (_) {
        // 日志写入失败不阻塞主流程
      }
    }
    return jsonResponse({ success: true, charged: true });
  }

  if (chargeStatus === 'ok_low_balance') {
    // CPC 点击扣费成功但余额偏低，写入 click_charged 日志（fire-and-forget）
    if (billingType === 'cpc' && eventType === 'click') {
      try {
        await supabase.from('ad_campaign_logs').insert({
          campaign_id: campaignId,
          merchant_id: campaign.merchant_id,
          actor_type: 'system',
          event_type: 'click_charged',
          detail: { cost: cost, balance_after: balanceAfter, user_id: userId ?? null },
        });
      } catch (_) {
        // 日志写入失败不阻塞主流程
      }
    }
    // 余额已低，异步触发低余额通知（不阻塞响应）
    triggerLowBalanceNotification(campaign.merchant_id);
    return jsonResponse({ success: true, charged: true });
  }

  if (chargeStatus === 'insufficient_balance') {
    return jsonResponse({ success: true, charged: false, reason: 'insufficient_balance' });
  }

  if (chargeStatus === 'daily_budget_exceeded') {
    // exhausted 日志已由 charge_ad_account SQL 函数内部写入，此处不重复写入（R22）
    return jsonResponse({ success: true, charged: false, reason: 'daily_budget_exceeded' });
  }

  // 未知状态码兜底
  console.error('[record-ad-event] unexpected charge status:', chargeStatus);
  return errorResponse('unexpected_status', `Unexpected charge result: ${chargeStatus}`, 500);
});
