// ============================================================
// Edge Function: merchant-influencer
// 模块: 12. Influencer 合作
// 优先级: P2/V2 — 当前为骨架，业务逻辑在 V2 实现
//
// 路由设计:
//   GET    /merchant-influencer/campaigns                        获取 Campaign 列表
//   POST   /merchant-influencer/campaigns                        创建 Campaign
//   PATCH  /merchant-influencer/campaigns/:id                    更新 Campaign
//   DELETE /merchant-influencer/campaigns/:id                    删除草稿 Campaign
//   GET    /merchant-influencer/campaigns/:id/applications       获取申请列表
//   PATCH  /merchant-influencer/applications/:id/approve         审批通过
//   PATCH  /merchant-influencer/applications/:id/reject          拒绝申请
//   GET    /merchant-influencer/performance                       获取效果数据
// ============================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// ---------- 通用 CORS 响应头 ----------
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, PATCH, DELETE, OPTIONS",
};

// ---------- 统一 JSON 响应 ----------
function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// ---------- 错误响应 ----------
function errorResponse(message: string, status = 400): Response {
  return jsonResponse({ error: message }, status);
}

// ============================================================
// 主入口
// ============================================================
serve(async (req: Request) => {
  // 处理 CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  // 从请求头获取 Authorization Token，构建 Supabase 客户端
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return errorResponse("Missing Authorization header", 401);
  }

  const supabaseClient = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    {
      global: { headers: { Authorization: authHeader } },
    },
  );

  // 解析 URL 路径，去掉 function 前缀
  // 示例路径:
  //   /merchant-influencer/campaigns
  //   /merchant-influencer/campaigns/uuid
  //   /merchant-influencer/campaigns/uuid/applications
  //   /merchant-influencer/applications/uuid/approve
  //   /merchant-influencer/applications/uuid/reject
  //   /merchant-influencer/performance
  const url = new URL(req.url);
  const pathParts = url.pathname
    .replace(/^\/merchant-influencer\/?/, "")
    .split("/")
    .filter(Boolean);

  const resource   = pathParts[0]; // campaigns | applications | performance
  const resourceId = pathParts[1]; // uuid
  const subAction  = pathParts[2]; // applications | approve | reject

  // 路由分发
  switch (resource) {
    case "campaigns":
      // /campaigns/:id/applications → 获取 Campaign 下的申请列表
      if (resourceId && subAction === "applications") {
        return getCampaignApplications(supabaseClient, resourceId);
      }
      return handleCampaigns(req, supabaseClient, resourceId);

    case "applications":
      // /applications/:id/approve 或 /applications/:id/reject
      if (!resourceId) return errorResponse("Missing application id", 400);
      if (subAction === "approve") {
        return approveApplication(req, supabaseClient, resourceId);
      }
      if (subAction === "reject") {
        return rejectApplication(req, supabaseClient, resourceId);
      }
      return errorResponse(`Unknown action: ${subAction}`, 404);

    case "performance":
      return getPerformance(req, supabaseClient, url);

    default:
      return errorResponse(`Unknown resource: ${resource}`, 404);
  }
});

// ============================================================
// Campaigns 处理器
// ============================================================
async function handleCampaigns(
  req: Request,
  // deno-lint-ignore no-explicit-any
  supabase: any,
  id?: string,
): Promise<Response> {
  switch (req.method) {
    case "GET":
      return getCampaigns(req, supabase);
    case "POST":
      return createCampaign(req, supabase);
    case "PATCH":
      if (!id) return errorResponse("Missing campaign id", 400);
      return updateCampaign(req, supabase, id);
    case "DELETE":
      if (!id) return errorResponse("Missing campaign id", 400);
      return deleteCampaign(supabase, id);
    default:
      return errorResponse(`Method ${req.method} not allowed`, 405);
  }
}

/**
 * GET /merchant-influencer/campaigns
 * 获取当前商家的 Campaign 列表，支持 ?status=draft|active|completed 筛选
 * TODO: V2 — 实现完整业务逻辑
 */
async function getCampaigns(
  req: Request,
  // deno-lint-ignore no-explicit-any
  supabase: any,
): Promise<Response> {
  // TODO: V2 实现以下逻辑:
  // 1. 从 auth.uid() 获取当前用户
  // 2. 查询 merchants 表获取 merchant_id
  // 3. 查询 influencer_campaigns WHERE merchant_id = ?
  // 4. 若 URL 包含 ?status= 参数，追加 AND status = ?
  // 5. JOIN deals 表获取 deal 基本信息（title, cover_image）
  // 6. 按 created_at DESC 排序，返回列表
  const _url = new URL(req.url);
  return jsonResponse({
    data: [],
    message: "TODO: V2 — implement campaigns list",
  });
}

/**
 * POST /merchant-influencer/campaigns
 * 创建新 Campaign
 * TODO: V2 — 实现完整业务逻辑
 *
 * Request body:
 *   title: string (required)
 *   deal_id?: string (uuid)
 *   requirements?: string
 *   compensation_type: 'fixed' | 'per_redemption' | 'revenue_share' (required)
 *   compensation_amount: number > 0 (required)
 *   budget: number >= compensation_amount (required)
 *   status?: 'draft' | 'active' (default 'draft')
 */
async function createCampaign(
  req: Request,
  // deno-lint-ignore no-explicit-any
  supabase: any,
): Promise<Response> {
  // TODO: V2 实现以下逻辑:
  // 1. 解析请求体，验证必填字段（title, compensation_type, compensation_amount, budget）
  // 2. 验证 compensation_type 合法值
  // 3. 验证 compensation_amount > 0
  // 4. 验证 budget >= compensation_amount
  // 5. 若提供了 deal_id，验证该 Deal 属于当前商家
  // 6. 获取当前商家的 merchant_id（通过 auth.uid()）
  // 7. 插入 influencer_campaigns 表
  // 8. 返回 201 + 创建的记录
  const _body = await req.json().catch(() => ({}));
  return jsonResponse({
    data: null,
    message: "TODO: V2 — implement create campaign",
  }, 201);
}

/**
 * PATCH /merchant-influencer/campaigns/:id
 * 更新 Campaign（修改内容或切换状态）
 * TODO: V2 — 实现完整业务逻辑
 *
 * Request body: 任意 InfluencerCampaign 字段（部分更新）
 */
async function updateCampaign(
  req: Request,
  // deno-lint-ignore no-explicit-any
  supabase: any,
  id: string,
): Promise<Response> {
  // TODO: V2 实现以下逻辑:
  // 1. 验证 Campaign 存在且属于当前商家
  // 2. 解析请求体（允许部分字段更新）
  // 3. 状态流转校验: draft→active, active→completed（不允许逆向）
  // 4. UPDATE influencer_campaigns SET ... WHERE id = ?
  // 5. 返回更新后的记录
  const _body = await req.json().catch(() => ({}));
  return jsonResponse({
    data: { id },
    message: "TODO: V2 — implement update campaign",
  });
}

/**
 * DELETE /merchant-influencer/campaigns/:id
 * 删除草稿 Campaign（只允许删除 draft 状态）
 * TODO: V2 — 实现完整业务逻辑
 */
async function deleteCampaign(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  id: string,
): Promise<Response> {
  // TODO: V2 实现以下逻辑:
  // 1. 验证 Campaign 存在且属于当前商家
  // 2. 验证 status = 'draft'（非草稿不允许删除）
  // 3. DELETE FROM influencer_campaigns WHERE id = ?
  // 4. 级联删除 influencer_applications（由外键 ON DELETE CASCADE 自动处理）
  // 5. 返回 204 No Content
  return jsonResponse({
    data: { id },
    message: "TODO: V2 — implement delete campaign (draft only)",
  });
}

// ============================================================
// Applications 处理器
// ============================================================

/**
 * GET /merchant-influencer/campaigns/:id/applications
 * 获取指定 Campaign 下的所有申请列表
 * TODO: V2 — 实现完整业务逻辑
 */
async function getCampaignApplications(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  campaignId: string,
): Promise<Response> {
  // TODO: V2 实现以下逻辑:
  // 1. 验证 Campaign 属于当前商家（RLS 保护，此处可直接查询）
  // 2. 查询 influencer_applications WHERE campaign_id = ?
  // 3. 通过 influencer_user_id 查询 profiles/users 表获取达人信息
  // 4. 按 applied_at DESC 排序，返回列表（含 pending/approved/rejected）
  return jsonResponse({
    data: [],
    campaignId,
    message: "TODO: V2 — implement campaign applications list",
  });
}

/**
 * PATCH /merchant-influencer/applications/:id/approve
 * 审批通过申请，自动生成专属推广链接
 * TODO: V2 — 实现完整业务逻辑
 *
 * 生成推广链接格式: https://crunchyplum.app/ref/{short_code}
 * short_code 使用 UUID 前 8 位（唯一性由 DB unique index 保证）
 */
async function approveApplication(
  req: Request,
  // deno-lint-ignore no-explicit-any
  supabase: any,
  applicationId: string,
): Promise<Response> {
  // TODO: V2 实现以下逻辑:
  // 1. 查询申请记录，验证 status = 'pending'
  // 2. 验证关联 Campaign 属于当前商家
  // 3. 生成唯一 short_code（UUID 前 8 位或 nanoid）
  // 4. 构造 promo_link: `https://crunchyplum.app/ref/${short_code}`
  // 5. UPDATE influencer_applications
  //      SET status = 'approved', promo_link = ?, reviewed_at = now()
  //      WHERE id = ?
  // 6. 创建或更新 influencer_performance 记录（初始化 clicks=0 etc.）
  // 7. V2.1: 触发推送通知给 Influencer（审批通过）
  // 8. 返回更新后的申请记录（含 promo_link）
  const _body = await req.json().catch(() => ({}));
  return jsonResponse({
    data: {
      id: applicationId,
      status: "approved",
      promo_link: `https://crunchyplum.app/ref/TODO_V2`,
    },
    message: "TODO: V2 — implement approve application with promo link generation",
  });
}

/**
 * PATCH /merchant-influencer/applications/:id/reject
 * 拒绝申请
 * TODO: V2 — 实现完整业务逻辑
 *
 * Request body:
 *   rejection_reason?: string (可选)
 */
async function rejectApplication(
  req: Request,
  // deno-lint-ignore no-explicit-any
  supabase: any,
  applicationId: string,
): Promise<Response> {
  // TODO: V2 实现以下逻辑:
  // 1. 查询申请记录，验证 status = 'pending'
  // 2. 验证关联 Campaign 属于当前商家
  // 3. 解析请求体获取 rejection_reason（可选）
  // 4. UPDATE influencer_applications
  //      SET status = 'rejected', rejection_reason = ?, reviewed_at = now()
  //      WHERE id = ?
  // 5. V2.1: 触发推送通知给 Influencer（含拒绝原因）
  // 6. 返回更新后的申请记录
  const _body = await req.json().catch(() => ({}));
  return jsonResponse({
    data: {
      id: applicationId,
      status: "rejected",
    },
    message: "TODO: V2 — implement reject application",
  });
}

// ============================================================
// Performance 处理器
// ============================================================

/**
 * GET /merchant-influencer/performance
 * 获取效果追踪数据，支持 ?campaign_id= 筛选
 * TODO: V2 — 实现完整业务逻辑
 */
async function getPerformance(
  req: Request,
  // deno-lint-ignore no-explicit-any
  supabase: any,
  url: URL,
): Promise<Response> {
  // TODO: V2 实现以下逻辑:
  // 1. 从 auth.uid() 获取当前商家
  // 2. 查询 influencer_performance
  //      WHERE campaign_id IN (SELECT id FROM influencer_campaigns WHERE merchant_id = ?)
  // 3. 若 URL 包含 ?campaign_id= 参数，追加 AND campaign_id = ?
  // 4. JOIN influencer_campaigns 获取 Campaign 标题
  // 5. 通过 influencer_user_id 查询 profiles/users 获取达人昵称、头像
  // 6. 计算转化率: conversion_rate = purchases / NULLIF(clicks, 0)
  // 7. 按 redemptions DESC 排序
  // 8. 返回列表（包含 campaign_title, influencer_name, 各项指标）
  const campaignId = url.searchParams.get("campaign_id");
  return jsonResponse({
    data: [],
    campaignId,
    message: "TODO: V2 — implement performance tracking",
  });
}
