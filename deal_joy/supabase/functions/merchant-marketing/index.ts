// ============================================================
// Edge Function: merchant-marketing
// 模块: 11. 营销工具（Marketing Tools）
// 优先级: P2/V2 — 当前为骨架，业务逻辑在 V2 实现
//
// 路由设计:
//   GET    /merchant-marketing/flash-deals
//   POST   /merchant-marketing/flash-deals
//   DELETE /merchant-marketing/flash-deals/:id
//   GET    /merchant-marketing/new-customer-offers
//   POST   /merchant-marketing/new-customer-offers
//   DELETE /merchant-marketing/new-customer-offers/:id
//   GET    /merchant-marketing/promotions
//   POST   /merchant-marketing/promotions
//   DELETE /merchant-marketing/promotions/:id
// ============================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// ---------- 通用 CORS 响应头 ----------
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS",
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

  // 从请求头获取 Authorization Token，构建 Supabase 客户端（以调用者身份执行）
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
  const url = new URL(req.url);
  // pathname 示例: /merchant-marketing/flash-deals 或 /merchant-marketing/flash-deals/uuid
  const pathParts = url.pathname.replace(/^\/merchant-marketing\/?/, "").split("/").filter(Boolean);
  const resource = pathParts[0]; // flash-deals | new-customer-offers | promotions
  const resourceId = pathParts[1]; // uuid（DELETE 时使用）

  // 路由分发
  switch (resource) {
    case "flash-deals":
      return handleFlashDeals(req, supabaseClient, resourceId);
    case "new-customer-offers":
      return handleNewCustomerOffers(req, supabaseClient, resourceId);
    case "promotions":
      return handlePromotions(req, supabaseClient, resourceId);
    default:
      return errorResponse(`Unknown resource: ${resource}`, 404);
  }
});

// ============================================================
// Flash Deals 处理器
// ============================================================
async function handleFlashDeals(
  req: Request,
  // deno-lint-ignore no-explicit-any
  supabase: any,
  id?: string,
): Promise<Response> {
  switch (req.method) {
    case "GET":
      return getFlashDeals(supabase);
    case "POST":
      return createFlashDeal(req, supabase);
    case "DELETE":
      if (!id) return errorResponse("Missing flash deal id", 400);
      return deleteFlashDeal(supabase, id);
    default:
      return errorResponse(`Method ${req.method} not allowed`, 405);
  }
}

/**
 * GET /merchant-marketing/flash-deals
 * 获取当前商家的所有限时折扣活动
 * TODO: V2 — 实现完整业务逻辑
 */
async function getFlashDeals(
  // deno-lint-ignore no-explicit-any
  supabase: any,
): Promise<Response> {
  // TODO: V2 实现以下逻辑:
  // 1. 从 auth.uid() 获取当前用户
  // 2. 查询 merchants 表获取 merchant_id
  // 3. 查询 flash_deals WHERE merchant_id = ? ORDER BY created_at DESC
  // 4. JOIN deals 表获取 deal 基本信息
  // 5. 返回列表（包括已过期的，前端可筛选）
  return jsonResponse({
    data: [],
    message: "TODO: V2 — implement flash deals list",
  });
}

/**
 * POST /merchant-marketing/flash-deals
 * 创建限时折扣活动
 * TODO: V2 — 实现完整业务逻辑
 *
 * Request body:
 *   deal_id: string (uuid)
 *   discount_percentage: number (1-99)
 *   start_time: string (ISO 8601)
 *   end_time: string (ISO 8601)
 */
async function createFlashDeal(
  req: Request,
  // deno-lint-ignore no-explicit-any
  supabase: any,
): Promise<Response> {
  // TODO: V2 实现以下逻辑:
  // 1. 解析请求体，验证必填字段
  // 2. 验证 discount_percentage 范围 (1-99)
  // 3. 验证 end_time > start_time
  // 4. 验证 deal_id 属于当前商家
  // 5. 检查该 deal 是否已有有效的闪购活动（is_active = true）
  // 6. 插入 flash_deals 表
  // 7. 返回创建的记录
  const _body = await req.json().catch(() => ({}));
  return jsonResponse({
    data: null,
    message: "TODO: V2 — implement create flash deal",
  }, 201);
}

/**
 * DELETE /merchant-marketing/flash-deals/:id
 * 关闭（软删除）限时折扣活动：将 is_active 置为 false
 * TODO: V2 — 实现完整业务逻辑
 */
async function deleteFlashDeal(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  id: string,
): Promise<Response> {
  // TODO: V2 实现以下逻辑:
  // 1. 验证该 flash_deal 属于当前商家
  // 2. UPDATE flash_deals SET is_active = false WHERE id = ?
  // 3. 返回 204 No Content
  return jsonResponse({
    data: { id },
    message: "TODO: V2 — implement deactivate flash deal",
  });
}

// ============================================================
// New Customer Offers 处理器
// ============================================================
async function handleNewCustomerOffers(
  req: Request,
  // deno-lint-ignore no-explicit-any
  supabase: any,
  id?: string,
): Promise<Response> {
  switch (req.method) {
    case "GET":
      return getNewCustomerOffers(supabase);
    case "POST":
      return createNewCustomerOffer(req, supabase);
    case "DELETE":
      if (!id) return errorResponse("Missing new customer offer id", 400);
      return deleteNewCustomerOffer(supabase, id);
    default:
      return errorResponse(`Method ${req.method} not allowed`, 405);
  }
}

/**
 * GET /merchant-marketing/new-customer-offers
 * 获取当前商家的新客特惠列表
 * TODO: V2 — 实现完整业务逻辑
 */
async function getNewCustomerOffers(
  // deno-lint-ignore no-explicit-any
  supabase: any,
): Promise<Response> {
  // TODO: V2 实现以下逻辑:
  // 1. 从 auth.uid() 获取当前商家
  // 2. 查询 new_customer_offers WHERE merchant_id = ?
  // 3. JOIN deals 表获取 deal 基本信息（包括原价，方便展示折扣幅度）
  // 4. 返回列表
  return jsonResponse({
    data: [],
    message: "TODO: V2 — implement new customer offers list",
  });
}

/**
 * POST /merchant-marketing/new-customer-offers
 * 为指定 Deal 创建新客特惠
 * TODO: V2 — 实现完整业务逻辑
 *
 * Request body:
 *   deal_id: string (uuid)
 *   special_price: number (> 0, < deal 原价)
 */
async function createNewCustomerOffer(
  req: Request,
  // deno-lint-ignore no-explicit-any
  supabase: any,
): Promise<Response> {
  // TODO: V2 实现以下逻辑:
  // 1. 解析请求体，验证 deal_id 和 special_price
  // 2. 验证 deal_id 属于当前商家
  // 3. 查询 deals.price，确保 special_price < deals.price
  // 4. 检查该 deal 是否已有有效的新客特惠
  // 5. 插入 new_customer_offers 表
  // 6. 返回创建的记录
  const _body = await req.json().catch(() => ({}));
  return jsonResponse({
    data: null,
    message: "TODO: V2 — implement create new customer offer",
  }, 201);
}

/**
 * DELETE /merchant-marketing/new-customer-offers/:id
 * 关闭新客特惠：将 is_active 置为 false
 * TODO: V2 — 实现完整业务逻辑
 */
async function deleteNewCustomerOffer(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  id: string,
): Promise<Response> {
  // TODO: V2 实现以下逻辑:
  // 1. 验证该 offer 属于当前商家
  // 2. UPDATE new_customer_offers SET is_active = false WHERE id = ?
  // 3. 返回 204 No Content
  return jsonResponse({
    data: { id },
    message: "TODO: V2 — implement deactivate new customer offer",
  });
}

// ============================================================
// Promotions 处理器
// ============================================================
async function handlePromotions(
  req: Request,
  // deno-lint-ignore no-explicit-any
  supabase: any,
  id?: string,
): Promise<Response> {
  switch (req.method) {
    case "GET":
      return getPromotions(supabase);
    case "POST":
      return createPromotion(req, supabase);
    case "DELETE":
      if (!id) return errorResponse("Missing promotion id", 400);
      return deletePromotion(supabase, id);
    default:
      return errorResponse(`Method ${req.method} not allowed`, 405);
  }
}

/**
 * GET /merchant-marketing/promotions
 * 获取当前商家的满减活动列表
 * TODO: V2 — 实现完整业务逻辑
 */
async function getPromotions(
  // deno-lint-ignore no-explicit-any
  supabase: any,
): Promise<Response> {
  // TODO: V2 实现以下逻辑:
  // 1. 从 auth.uid() 获取当前商家
  // 2. 查询 promotions WHERE merchant_id = ? ORDER BY created_at DESC
  // 3. 如果有 deal_id，JOIN deals 获取 deal 信息
  // 4. 返回列表（包含状态：active/expired/upcoming）
  return jsonResponse({
    data: [],
    message: "TODO: V2 — implement promotions list",
  });
}

/**
 * POST /merchant-marketing/promotions
 * 创建满减活动
 * TODO: V2 — 实现完整业务逻辑
 *
 * Request body:
 *   min_spend: number (> 0)
 *   discount_amount: number (> 0, < min_spend)
 *   deal_id?: string (uuid, 可选，为 null 表示全店通用)
 *   title?: string
 *   description?: string
 *   start_time?: string (ISO 8601)
 *   end_time?: string (ISO 8601)
 */
async function createPromotion(
  req: Request,
  // deno-lint-ignore no-explicit-any
  supabase: any,
): Promise<Response> {
  // TODO: V2 实现以下逻辑:
  // 1. 解析请求体，验证必填字段
  // 2. 验证 min_spend > 0
  // 3. 验证 discount_amount > 0 且 < min_spend
  // 4. 如果提供了 deal_id，验证 deal 属于当前商家
  // 5. 如果提供了 end_time，验证 end_time > start_time（或当前时间）
  // 6. 自动生成 title（若未提供）：如 "Spend $30 Get $5 Off"
  // 7. 插入 promotions 表
  // 8. 返回创建的记录
  const _body = await req.json().catch(() => ({}));
  return jsonResponse({
    data: null,
    message: "TODO: V2 — implement create promotion",
  }, 201);
}

/**
 * DELETE /merchant-marketing/promotions/:id
 * 关闭满减活动：将 is_active 置为 false
 * TODO: V2 — 实现完整业务逻辑
 */
async function deletePromotion(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  id: string,
): Promise<Response> {
  // TODO: V2 实现以下逻辑:
  // 1. 验证该 promotion 属于当前商家
  // 2. UPDATE promotions SET is_active = false WHERE id = ?
  // 3. 返回 204 No Content
  return jsonResponse({
    data: { id },
    message: "TODO: V2 — implement deactivate promotion",
  });
}
