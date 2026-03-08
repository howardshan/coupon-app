// =============================================================
// DealJoy Edge Function: merchant-deals
// 处理商家 Deal 的完整 CRUD：列表、创建、更新、上下架、删除、图片
//
// 路由规则（通过 URL 路径和 HTTP Method 区分）:
//   GET    /merchant-deals              -> 获取商家所有 deals（支持 ?status= 筛选）
//   POST   /merchant-deals              -> 创建新 deal（状态默认 pending）
//   PATCH  /merchant-deals/:id          -> 更新 deal（修改后重置为 pending）
//   PATCH  /merchant-deals/:id/status   -> 上下架切换
//   DELETE /merchant-deals/:id          -> 删除（仅 inactive 状态）
//   POST   /merchant-deals/:id/images   -> 添加图片记录
// =============================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { resolveAuth, requirePermission } from "../_shared/auth.ts";

// CORS 响应头
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-merchant-id",
  "Access-Control-Allow-Methods": "GET, POST, PATCH, PUT, DELETE, OPTIONS",
};

// 统一 JSON 响应
function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// 错误响应
function errorResponse(message: string, status = 400): Response {
  return jsonResponse({ error: message }, status);
}

// =============================================================
// 主入口
// =============================================================
Deno.serve(async (req: Request) => {
  // 处理 CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  // 初始化 Supabase 管理员客户端（绕过 RLS）
  const supabaseAdmin = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    { auth: { persistSession: false } }
  );

  // 使用用户 JWT 初始化客户端
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return errorResponse("Missing authorization header", 401);
  }

  const supabaseUser = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false },
    }
  );

  // 验证 JWT
  const {
    data: { user },
    error: authError,
  } = await supabaseUser.auth.getUser();

  if (authError || !user) {
    return errorResponse("Unauthorized", 401);
  }

  // 统一鉴权：支持门店 owner / 品牌管理员 / manager
  let auth;
  try {
    auth = await resolveAuth(supabaseAdmin, user.id, req.headers);
  } catch (e) {
    return errorResponse((e as Error).message, 403);
  }
  requirePermission(auth, "deals");

  const merchantId: string = auth.merchantId;

  // 解析 URL 路径，提取 deal_id 和子路径
  const url = new URL(req.url);
  const pathParts = url.pathname.replace(/^\/merchant-deals\/?/, "").split("/").filter(Boolean);
  // pathParts[0] = deal_id（可能为空）
  // pathParts[1] = 子路径（如 "status" 或 "images"）
  const dealId = pathParts[0] ?? null;
  const subPath = pathParts[1] ?? null;

  // =============================================================
  // 路由分发
  // =============================================================

  try {
    // ----------------------------------------------------------
    // GET /merchant-deals — 获取商家所有 deals
    // ----------------------------------------------------------
    if (req.method === "GET" && !dealId) {
      return await handleGetDeals(supabaseAdmin, merchantId, url);
    }

    // ----------------------------------------------------------
    // POST /merchant-deals — 创建新 deal
    // ----------------------------------------------------------
    if (req.method === "POST" && !dealId) {
      const body = await req.json();
      return await handleCreateDeal(supabaseAdmin, merchantId, body);
    }

    // ----------------------------------------------------------
    // PATCH /merchant-deals/:id/status — 上下架切换
    // ----------------------------------------------------------
    if (req.method === "PATCH" && dealId && subPath === "status") {
      const body = await req.json();
      return await handleToggleStatus(supabaseAdmin, merchantId, dealId, body);
    }

    // ----------------------------------------------------------
    // PATCH /merchant-deals/:id — 更新 deal
    // ----------------------------------------------------------
    if (req.method === "PATCH" && dealId && !subPath) {
      const body = await req.json();
      return await handleUpdateDeal(supabaseAdmin, merchantId, dealId, body);
    }

    // ----------------------------------------------------------
    // DELETE /merchant-deals/:id — 删除 deal（仅 inactive）
    // ----------------------------------------------------------
    if (req.method === "DELETE" && dealId && !subPath) {
      return await handleDeleteDeal(supabaseAdmin, merchantId, dealId);
    }

    // ----------------------------------------------------------
    // POST /merchant-deals/:id/images — 添加图片记录
    // ----------------------------------------------------------
    if (req.method === "POST" && dealId && subPath === "images") {
      const body = await req.json();
      return await handleAddImage(supabaseAdmin, merchantId, dealId, body);
    }

    return errorResponse("Not Found", 404);
  } catch (err) {
    console.error("merchant-deals error:", err);
    const message = err instanceof Error ? err.message : "Internal server error";
    return errorResponse(message, 500);
  }
});

// =============================================================
// GET /merchant-deals
// 获取商家所有 deals，支持 ?status= 筛选
// =============================================================
async function handleGetDeals(
  admin: ReturnType<typeof createClient>,
  merchantId: string,
  url: URL
): Promise<Response> {
  const statusFilter = url.searchParams.get("status");

  // 构建查询：deals + deal_images（获取图片列表）
  let query = admin
    .from("deals")
    .select(`
      id,
      title,
      description,
      category,
      original_price,
      discount_price,
      discount_percent,
      stock_limit,
      total_sold,
      rating,
      review_count,
      is_active,
      is_featured,
      deal_status,
      package_contents,
      usage_notes,
      usage_days,
      max_per_person,
      is_stackable,
      validity_type,
      validity_days,
      expires_at,
      review_notes,
      published_at,
      created_at,
      updated_at,
      deal_images (
        id,
        image_url,
        sort_order,
        is_primary
      )
    `)
    .eq("merchant_id", merchantId)
    .order("created_at", { ascending: false });

  // 按状态筛选
  if (statusFilter && ["pending", "active", "inactive", "rejected"].includes(statusFilter)) {
    query = query.eq("deal_status", statusFilter);
  }

  const { data, error } = await query;

  if (error) {
    return errorResponse(error.message, 500);
  }

  return jsonResponse({ deals: data ?? [] });
}

// =============================================================
// POST /merchant-deals
// 创建新 deal，状态默认 pending（需平台审核）
// =============================================================
async function handleCreateDeal(
  admin: ReturnType<typeof createClient>,
  merchantId: string,
  body: Record<string, unknown>
): Promise<Response> {
  // 校验必填字段
  const required = ["title", "description", "category", "original_price", "discount_price"];
  for (const field of required) {
    if (!body[field]) {
      return errorResponse(`Missing required field: ${field}`, 400);
    }
  }

  const originalPrice = Number(body.original_price);
  const discountPrice = Number(body.discount_price);

  // 校验价格逻辑: 现价 < 原价
  if (discountPrice >= originalPrice) {
    return errorResponse("Deal price must be less than original price", 400);
  }

  if (originalPrice <= 0 || discountPrice <= 0) {
    return errorResponse("Prices must be greater than 0", 400);
  }

  // 校验库存
  const stockLimit = body.stock_limit !== undefined ? Number(body.stock_limit) : 100;
  if (stockLimit !== -1 && stockLimit < 1) {
    return errorResponse("Stock limit must be at least 1 (or -1 for unlimited)", 400);
  }

  // 校验有效期
  const validityType = (body.validity_type as string) ?? "fixed_date";
  if (!["fixed_date", "days_after_purchase"].includes(validityType)) {
    return errorResponse("Invalid validity_type", 400);
  }

  let expiresAt: string;
  if (validityType === "fixed_date") {
    if (!body.expires_at) {
      return errorResponse("expires_at is required for fixed_date validity", 400);
    }
    expiresAt = body.expires_at as string;
  } else {
    // days_after_purchase: 设置一个远期过期时间，实际过期逻辑在购买后计算
    const daysAfter = Number(body.validity_days ?? 30);
    const farFuture = new Date();
    farFuture.setFullYear(farFuture.getFullYear() + 2);
    expiresAt = farFuture.toISOString();
  }

  // 构建插入数据
  const dealData = {
    merchant_id:      merchantId,
    title:            String(body.title),
    description:      String(body.description),
    category:         String(body.category),
    original_price:   originalPrice,
    discount_price:   discountPrice,
    stock_limit:      stockLimit,
    expires_at:       expiresAt,
    is_active:        false,          // 新建 deal 默认不上架，等审核通过后上架
    deal_status:      "pending",
    package_contents: String(body.package_contents ?? ""),
    usage_notes:      String(body.usage_notes ?? ""),
    usage_days:       (body.usage_days as string[]) ?? [],
    max_per_person:   body.max_per_person ? Number(body.max_per_person) : null,
    is_stackable:     body.is_stackable !== undefined ? Boolean(body.is_stackable) : true,
    validity_type:    validityType,
    validity_days:    body.validity_days ? Number(body.validity_days) : null,
    discount_label:   body.discount_label ? String(body.discount_label) : "",
    refund_policy:    body.refund_policy
      ? String(body.refund_policy)
      : "Risk-Free Refund within 7 days",
    image_urls:       (body.image_urls as string[]) ?? [],
    dishes:           body.dishes ?? [],
    deal_category_id: body.deal_category_id ?? null,
    deal_type:        body.deal_type ? String(body.deal_type) : "regular",
    badge_text:       body.badge_text ? String(body.badge_text) : null,
  };

  const { data: deal, error } = await admin
    .from("deals")
    .insert(dealData)
    .select()
    .single();

  if (error) {
    return errorResponse(error.message, 500);
  }

  return jsonResponse({ deal }, 201);
}

// =============================================================
// PATCH /merchant-deals/:id
// 更新 deal，修改后状态重置为 pending（需重新审核）
// =============================================================
async function handleUpdateDeal(
  admin: ReturnType<typeof createClient>,
  merchantId: string,
  dealId: string,
  body: Record<string, unknown>
): Promise<Response> {
  // 验证所有权
  const { data: existing, error: fetchError } = await admin
    .from("deals")
    .select("id, merchant_id, deal_status")
    .eq("id", dealId)
    .single();

  if (fetchError || !existing) {
    return errorResponse("Deal not found", 404);
  }

  if (existing.merchant_id !== merchantId) {
    return errorResponse("Access denied: not your deal", 403);
  }

  // pending 状态的 deal 不允许编辑（审核中）
  if (existing.deal_status === "pending") {
    return errorResponse("Cannot edit deal while under review", 400);
  }

  // 价格校验
  if (body.original_price !== undefined && body.discount_price !== undefined) {
    const originalPrice = Number(body.original_price);
    const discountPrice = Number(body.discount_price);
    if (discountPrice >= originalPrice) {
      return errorResponse("Deal price must be less than original price", 400);
    }
  }

  // 构建更新数据（只更新传入的字段）
  const updateData: Record<string, unknown> = {
    deal_status: "pending",  // 修改后重置为待审核
    is_active:   false,      // 下架，等重新审核通过
    updated_at:  new Date().toISOString(),
  };

  const updatableFields = [
    "title", "description", "category", "original_price", "discount_price",
    "stock_limit", "expires_at", "package_contents", "usage_notes",
    "usage_days", "max_per_person", "is_stackable", "validity_type",
    "validity_days", "discount_label", "refund_policy", "image_urls", "dishes",
    "deal_category_id", "deal_type", "badge_text",
  ];

  for (const field of updatableFields) {
    if (body[field] !== undefined) {
      updateData[field] = body[field];
    }
  }

  const { data: deal, error } = await admin
    .from("deals")
    .update(updateData)
    .eq("id", dealId)
    .select()
    .single();

  if (error) {
    return errorResponse(error.message, 500);
  }

  return jsonResponse({ deal });
}

// =============================================================
// PATCH /merchant-deals/:id/status
// 手动上下架切换
// =============================================================
async function handleToggleStatus(
  admin: ReturnType<typeof createClient>,
  merchantId: string,
  dealId: string,
  body: Record<string, unknown>
): Promise<Response> {
  if (body.is_active === undefined) {
    return errorResponse("Missing required field: is_active", 400);
  }

  const isActive = Boolean(body.is_active);

  // 调用 toggle_deal_status 函数（内含所有权验证）
  // 注意: RPC 函数使用 SECURITY DEFINER，内部调用 auth.uid()
  // 但我们在 Edge Function 层用 admin client 调用，需手动验证所有权
  const { data: existing, error: fetchError } = await admin
    .from("deals")
    .select("id, merchant_id, deal_status")
    .eq("id", dealId)
    .single();

  if (fetchError || !existing) {
    return errorResponse("Deal not found", 404);
  }

  if (existing.merchant_id !== merchantId) {
    return errorResponse("Access denied: not your deal", 403);
  }

  // pending / rejected 状态不允许商家上架
  if (isActive && ["pending", "rejected"].includes(existing.deal_status)) {
    return errorResponse(
      `Cannot activate deal with status: ${existing.deal_status}. Wait for review approval.`,
      400
    );
  }

  const newStatus = isActive ? "active" : "inactive";

  const updatePayload: Record<string, unknown> = {
    deal_status: newStatus,
    is_active:   isActive,
    updated_at:  new Date().toISOString(),
  };

  // 首次上架时记录 published_at
  if (isActive && !existing.deal_status) {
    updatePayload.published_at = new Date().toISOString();
  }

  const { data: deal, error } = await admin
    .from("deals")
    .update(updatePayload)
    .eq("id", dealId)
    .select("id, deal_status, is_active, published_at")
    .single();

  if (error) {
    return errorResponse(error.message, 500);
  }

  return jsonResponse({ deal, new_status: newStatus });
}

// =============================================================
// DELETE /merchant-deals/:id
// 删除 deal（仅限 inactive 状态）
// =============================================================
async function handleDeleteDeal(
  admin: ReturnType<typeof createClient>,
  merchantId: string,
  dealId: string
): Promise<Response> {
  // 验证所有权和状态
  const { data: existing, error: fetchError } = await admin
    .from("deals")
    .select("id, merchant_id, deal_status")
    .eq("id", dealId)
    .single();

  if (fetchError || !existing) {
    return errorResponse("Deal not found", 404);
  }

  if (existing.merchant_id !== merchantId) {
    return errorResponse("Access denied: not your deal", 403);
  }

  if (existing.deal_status !== "inactive") {
    return errorResponse(
      "Only inactive deals can be deleted. Please deactivate first.",
      400
    );
  }

  const { error } = await admin
    .from("deals")
    .delete()
    .eq("id", dealId);

  if (error) {
    return errorResponse(error.message, 500);
  }

  return jsonResponse({ success: true, deleted_id: dealId });
}

// =============================================================
// POST /merchant-deals/:id/images
// 添加图片记录（图片文件已由前端上传到 Storage）
// =============================================================
async function handleAddImage(
  admin: ReturnType<typeof createClient>,
  merchantId: string,
  dealId: string,
  body: Record<string, unknown>
): Promise<Response> {
  if (!body.image_url) {
    return errorResponse("Missing required field: image_url", 400);
  }

  // 验证 deal 所有权
  const { data: existing, error: fetchError } = await admin
    .from("deals")
    .select("id, merchant_id")
    .eq("id", dealId)
    .single();

  if (fetchError || !existing) {
    return errorResponse("Deal not found", 404);
  }

  if (existing.merchant_id !== merchantId) {
    return errorResponse("Access denied: not your deal", 403);
  }

  // 查询当前图片数量
  const { count } = await admin
    .from("deal_images")
    .select("id", { count: "exact", head: true })
    .eq("deal_id", dealId);

  if ((count ?? 0) >= 5) {
    return errorResponse("Maximum 5 images per deal", 400);
  }

  const isPrimary = Boolean(body.is_primary) || (count ?? 0) === 0;

  // 若设为主图，先将其他图片的 is_primary 设为 false
  if (isPrimary) {
    await admin
      .from("deal_images")
      .update({ is_primary: false })
      .eq("deal_id", dealId);
  }

  const { data: image, error } = await admin
    .from("deal_images")
    .insert({
      deal_id:    dealId,
      image_url:  String(body.image_url),
      sort_order: Number(body.sort_order ?? count ?? 0),
      is_primary: isPrimary,
    })
    .select()
    .single();

  if (error) {
    return errorResponse(error.message, 500);
  }

  // 同步 deal_images 的 URL 到 deals.image_urls，供用户端直接读取
  await syncDealImageUrls(admin, dealId);

  return jsonResponse({ image }, 201);
}

// =============================================================
// 辅助：同步 deal_images 表的 URL 到 deals.image_urls 字段
// =============================================================
async function syncDealImageUrls(
  admin: ReturnType<typeof createClient>,
  dealId: string
): Promise<void> {
  const { data: images } = await admin
    .from("deal_images")
    .select("image_url")
    .eq("deal_id", dealId)
    .order("sort_order");

  const urls = (images ?? []).map((img: { image_url: string }) => img.image_url);

  await admin
    .from("deals")
    .update({ image_urls: urls })
    .eq("id", dealId);
}
