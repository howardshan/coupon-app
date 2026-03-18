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
    // PATCH /merchant-deals/reorder — 批量更新 sort_order
    // ----------------------------------------------------------
    if (req.method === "PATCH" && dealId === "reorder" && !subPath) {
      const body = await req.json();
      return await handleBatchReorder(supabaseAdmin, merchantId, body);
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

    // ----------------------------------------------------------
    // PATCH /merchant-deals/:id/store-confirm — 门店 Accept/Decline/Remove
    // ----------------------------------------------------------
    if (req.method === "PATCH" && dealId && subPath === "store-confirm") {
      const body = await req.json();
      return await handleStoreConfirm(supabaseAdmin, merchantId, dealId, user.id, body);
    }

    // ==========================================================
    // V2.2 Deal 模板路由
    // ==========================================================

    // GET /merchant-deals/templates — 获取品牌模板列表
    if (req.method === "GET" && dealId === "templates" && !subPath) {
      if (!auth.isBrandAdmin || !auth.brandId) {
        return errorResponse("Brand admin access required", 403);
      }
      return await handleGetTemplates(supabaseAdmin, auth.brandId);
    }

    // POST /merchant-deals/templates — 创建品牌模板
    if (req.method === "POST" && dealId === "templates" && !subPath) {
      if (!auth.isBrandAdmin || !auth.brandId) {
        return errorResponse("Brand admin access required", 403);
      }
      const body = await req.json();
      return await handleCreateTemplate(supabaseAdmin, auth.brandId, user.id, body);
    }

    // PATCH /merchant-deals/templates/:templateId — 更新模板
    if (req.method === "PATCH" && dealId === "templates" && subPath) {
      if (!auth.isBrandAdmin || !auth.brandId) {
        return errorResponse("Brand admin access required", 403);
      }
      const body = await req.json();
      return await handleUpdateTemplate(supabaseAdmin, auth.brandId, subPath, body);
    }

    // POST /merchant-deals/templates/:templateId/publish — 发布到选中门店
    if (req.method === "POST" && dealId === "templates" && subPath) {
      // subPath 可能是 "templateId/publish" — 需要进一步解析
      // 实际上 pathParts 已经拆分好了
      // 重新解析：pathParts = ["templates", templateId, "publish"]
      const tplPathParts = url.pathname.replace(/^\/merchant-deals\/?/, "").split("/").filter(Boolean);
      const tplId = tplPathParts[1] ?? null;
      const tplAction = tplPathParts[2] ?? null;

      if (!auth.isBrandAdmin || !auth.brandId) {
        return errorResponse("Brand admin access required", 403);
      }

      if (tplAction === "publish" && tplId) {
        const body = await req.json();
        return await handlePublishTemplate(supabaseAdmin, auth.brandId, tplId, body, auth.merchantIds);
      }

      if (tplAction === "sync" && tplId) {
        return await handleSyncTemplate(supabaseAdmin, auth.brandId, tplId);
      }
    }

    // DELETE /merchant-deals/templates/:templateId — 删除模板
    if (req.method === "DELETE" && dealId === "templates" && subPath) {
      if (!auth.isBrandAdmin || !auth.brandId) {
        return errorResponse("Brand admin access required", 403);
      }
      return await handleDeleteTemplate(supabaseAdmin, auth.brandId, subPath);
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
// 包含两类 deal：
//   1. 本店创建的 deal（merchant_id = merchantId）
//   2. 通过 deal_applicable_stores 关联的品牌 deal（status = active）
// =============================================================
async function handleGetDeals(
  admin: ReturnType<typeof createClient>,
  merchantId: string,
  url: URL
): Promise<Response> {
  const statusFilter = url.searchParams.get("status");

  const selectFields = `
    id,
    merchant_id,
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
    usage_note_images,
    usage_days,
    max_per_person,
    is_stackable,
    validity_type,
    validity_days,
    expires_at,
    review_notes,
    rejection_reason,
    published_at,
    created_at,
    updated_at,
    applicable_merchant_ids,
    deal_images (
      id,
      image_url,
      sort_order,
      is_primary
    ),
    deal_option_groups (
      id,
      name,
      select_min,
      select_max,
      sort_order,
      deal_option_items (
        id,
        name,
        price,
        sort_order
      )
    )
  `;

  // 1. 本店创建的 deal
  let ownQuery = admin
    .from("deals")
    .select(selectFields)
    .eq("merchant_id", merchantId)
    .order("created_at", { ascending: false });

  if (statusFilter && ["pending", "active", "inactive", "rejected"].includes(statusFilter)) {
    ownQuery = ownQuery.eq("deal_status", statusFilter);
  }

  const { data: ownDeals, error: ownError } = await ownQuery;
  if (ownError) {
    return errorResponse(ownError.message, 500);
  }

  // 2. 通过 deal_applicable_stores 关联的品牌 deal（非本店创建但本店已接受）
  const { data: dasRecords } = await admin
    .from("deal_applicable_stores")
    .select("deal_id, status")
    .eq("store_id", merchantId)
    .eq("status", "active");

  let associatedDeals: typeof ownDeals = [];
  if (dasRecords && dasRecords.length > 0) {
    // 排除本店自己创建的 deal（避免重复）
    const ownDealIds = new Set((ownDeals ?? []).map((d: { id: string }) => d.id));
    const extraDealIds = dasRecords
      .map((r: { deal_id: string }) => r.deal_id)
      .filter((id: string) => !ownDealIds.has(id));

    if (extraDealIds.length > 0) {
      let assocQuery = admin
        .from("deals")
        .select(selectFields)
        .in("id", extraDealIds)
        .order("created_at", { ascending: false });

      if (statusFilter && ["pending", "active", "inactive", "rejected"].includes(statusFilter)) {
        assocQuery = assocQuery.eq("deal_status", statusFilter);
      }

      const { data: assocData } = await assocQuery;
      associatedDeals = assocData ?? [];
    }
  }

  // 合并两类 deal，按 created_at 降序排列
  const allDeals = [...(ownDeals ?? []), ...associatedDeals];
  allDeals.sort((a: { created_at: string }, b: { created_at: string }) =>
    b.created_at.localeCompare(a.created_at)
  );

  return jsonResponse({ deals: allDeals });
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
  let validityType = (body.validity_type as string) ?? "fixed_date";
  // 向后兼容旧值：旧版商家端仍可能发送 days_after_purchase
  if (validityType === "days_after_purchase") validityType = "long_after_purchase";
  if (!["fixed_date", "short_after_purchase", "long_after_purchase"].includes(validityType)) {
    return errorResponse("Invalid validity_type", 400);
  }

  let expiresAt: string;
  if (validityType === "fixed_date") {
    if (!body.expires_at) {
      return errorResponse("expires_at is required for fixed_date validity", 400);
    }
    expiresAt = body.expires_at as string;
  } else {
    // short_after_purchase / long_after_purchase: 设置远期占位，购买后计算实际到期
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
    usage_note_images: (body.usage_note_images as string[]) ?? [],
    usage_days:       (body.usage_days as string[]) ?? [],
    max_per_person:   body.max_per_person ? Number(body.max_per_person) : null,
    is_stackable:     body.is_stackable !== undefined ? Boolean(body.is_stackable) : true,
    validity_type:    validityType,
    validity_days:    body.validity_days ? Number(body.validity_days) : null,
    discount_label:   body.discount_label ? String(body.discount_label) : "",
    refund_policy:    body.refund_policy
      ? String(body.refund_policy)
      : "Refund anytime before use, refund when expired",
    image_urls:       (body.image_urls as string[]) ?? [],
    dishes:           body.dishes ?? [],
    detail_images:    (body.detail_images as string[]) ?? [],
    deal_category_id: body.deal_category_id ?? null,
    deal_type:        body.deal_type ? String(body.deal_type) : "regular",
    badge_text:       body.badge_text ? String(body.badge_text) : null,
    short_name:       body.short_name ? String(body.short_name).slice(0, 10) : null,
    // 多店通用：保持向后兼容，同时支持新的 store_confirmations 格式
    applicable_merchant_ids: body.applicable_merchant_ids ?? null,
    // 门店预确认列表，格式：[{ store_id, pre_confirmed }]
    // store_only deal 传 null，触发器会自动写一条 active 记录
    // brand_multi_store deal 传确认列表，审核通过后触发器按此写入 deal_applicable_stores
    store_confirmations: deriveStoreConfirmations(body),
  };

  const { data: deal, error } = await admin
    .from("deals")
    .insert(dealData)
    .select()
    .single();

  if (error) {
    return errorResponse(error.message, 500);
  }

  // 插入选项组和选项项
  if (body.option_groups && Array.isArray(body.option_groups)) {
    await insertOptionGroups(admin, deal.id, body.option_groups as OptionGroupInput[]);
  }

  return jsonResponse({ deal }, 201);
}

// =============================================================
// PATCH /merchant-deals/:id
// 编辑 deal：仅修改库存时原地更新，其他修改视为克隆（新建 deal + 旧 deal 下架）
// =============================================================
async function handleUpdateDeal(
  admin: ReturnType<typeof createClient>,
  merchantId: string,
  dealId: string,
  body: Record<string, unknown>
): Promise<Response> {
  // 验证所有权，读取旧 deal 完整信息
  const { data: existing, error: fetchError } = await admin
    .from("deals")
    .select("*")
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

  const updatableFields = [
    "title", "description", "category", "original_price", "discount_price",
    "stock_limit", "expires_at", "package_contents", "usage_notes", "usage_note_images",
    "usage_days", "max_per_person", "is_stackable", "validity_type",
    "validity_days", "discount_label", "refund_policy", "image_urls", "dishes",
    "deal_category_id", "deal_type", "badge_text", "short_name", "sort_order",
    "applicable_merchant_ids", "detail_images",
  ];

  // sort_order 或 short_name 变更：原地更新，不克隆不重审
  if (body.sort_order_only === true) {
    const updatePayload: Record<string, unknown> = { updated_at: new Date().toISOString() };
    if (body.sort_order !== undefined) updatePayload.sort_order = Number(body.sort_order);
    if (body.short_name !== undefined) updatePayload.short_name = body.short_name ? String(body.short_name).slice(0, 10) : null;

    const { data: deal, error } = await admin
      .from("deals")
      .update(updatePayload)
      .eq("id", dealId)
      .select()
      .single();

    if (error) return errorResponse(error.message, 500);
    return jsonResponse({ deal });
  }

  // 前端显式传 stock_only=true 表示仅修改库存，原地更新不克隆不重审
  if (body.stock_only === true) {
    const { data: deal, error } = await admin
      .from("deals")
      .update({
        stock_limit: body.stock_limit !== undefined ? Number(body.stock_limit) : existing.stock_limit,
        updated_at:  new Date().toISOString(),
      })
      .eq("id", dealId)
      .select()
      .single();

    if (error) return errorResponse(error.message, 500);
    return jsonResponse({ deal });
  }

  // 非仅库存修改：克隆新 deal，旧 deal 下架
  // 1. 构建新 deal 数据（从旧 deal 复制，应用修改）
  const cloneFields = [
    "merchant_id", "title", "description", "category",
    "original_price", "discount_price", "image_urls",
    "stock_limit", "discount_label", "dishes", "merchant_hours",
    "usage_days", "max_per_person", "is_stackable", "validity_type",
    "validity_days", "refund_policy", "package_contents", "usage_notes", "usage_note_images",
    "deal_category_id", "deal_type", "badge_text",
    "applicable_merchant_ids", "store_confirmations",
    "lat", "lng", "address", "expires_at", "sort_order", "short_name",
    "detail_images",
  ];

  const newDealData: Record<string, unknown> = {
    deal_status: "pending",
    is_active:   false,
    created_at:  new Date().toISOString(),
    updated_at:  new Date().toISOString(),
  };

  // 先从旧 deal 复制所有可克隆字段
  for (const field of cloneFields) {
    if (existing[field] !== undefined && existing[field] !== null) {
      newDealData[field] = existing[field];
    }
  }

  // 再应用用户传入的修改（覆盖旧值）
  for (const field of updatableFields) {
    if (body[field] !== undefined) {
      newDealData[field] = body[field];
    }
  }

  // 2. 插入新 deal
  const { data: newDeal, error: insertError } = await admin
    .from("deals")
    .insert(newDealData)
    .select()
    .single();

  if (insertError) {
    return errorResponse(insertError.message, 500);
  }

  // 3. 复制 deal_images 到新 deal
  const { data: oldImages } = await admin
    .from("deal_images")
    .select("image_url, sort_order, is_primary")
    .eq("deal_id", dealId);

  if (oldImages && oldImages.length > 0) {
    const newImages = oldImages.map((img: { image_url: string; sort_order: number; is_primary: boolean }) => ({
      deal_id:    newDeal.id,
      image_url:  img.image_url,
      sort_order: img.sort_order,
      is_primary: img.is_primary,
    }));
    await admin.from("deal_images").insert(newImages);
  }

  // 4. 复制 deal_applicable_stores 到新 deal（保留门店确认状态）
  const { data: oldStores } = await admin
    .from("deal_applicable_stores")
    .select("store_id, status, menu_item_id, store_original_price, confirmed_by, confirmed_at")
    .eq("deal_id", dealId);

  if (oldStores && oldStores.length > 0) {
    const newStores = oldStores.map((s: Record<string, unknown>) => ({
      deal_id:              newDeal.id,
      store_id:             s.store_id,
      status:               s.status,
      menu_item_id:         s.menu_item_id,
      store_original_price: s.store_original_price,
      confirmed_by:         s.confirmed_by,
      confirmed_at:         s.confirmed_at,
    }));
    await admin.from("deal_applicable_stores").insert(newStores);
  }

  // 5. 复制或更新选项组到新 deal
  if (body.option_groups && Array.isArray(body.option_groups)) {
    // 前端传了新的选项组，直接使用
    await insertOptionGroups(admin, newDeal.id, body.option_groups as OptionGroupInput[]);
  } else {
    // 没传选项组，从旧 deal 复制
    await cloneOptionGroups(admin, dealId, newDeal.id);
  }

  // 6. 旧 deal 下架标记为 inactive
  await admin
    .from("deals")
    .update({
      is_active:   false,
      deal_status: "inactive",
      updated_at:  new Date().toISOString(),
    })
    .eq("id", dealId);

  return jsonResponse({ deal: newDeal });
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
// PATCH /merchant-deals/reorder — 批量更新 sort_order
// body: { items: [{ id: string, sort_order: number }] }
// =============================================================
async function handleBatchReorder(
  admin: ReturnType<typeof createClient>,
  merchantId: string,
  body: { items?: { id: string; sort_order: number }[] }
): Promise<Response> {
  const items = body.items;
  if (!items || !Array.isArray(items) || items.length === 0) {
    return errorResponse("items array is required", 400);
  }

  // 验证所有 deal 都属于该商家
  const dealIds = items.map((i) => i.id);
  const { data: deals } = await admin
    .from("deals")
    .select("id")
    .eq("merchant_id", merchantId)
    .in("id", dealIds);

  const ownedIds = new Set((deals ?? []).map((d: { id: string }) => d.id));
  const unauthorized = dealIds.filter((id) => !ownedIds.has(id));
  if (unauthorized.length > 0) {
    return errorResponse(`Access denied for deals: ${unauthorized.join(", ")}`, 403);
  }

  // 逐个更新 sort_order
  const now = new Date().toISOString();
  for (const item of items) {
    await admin
      .from("deals")
      .update({ sort_order: item.sort_order, updated_at: now })
      .eq("id", item.id);
  }

  return jsonResponse({ updated: items.length });
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
// 辅助：将请求体中的门店信息标准化为 store_confirmations 格式
// 支持两种传参方式（向后兼容）：
//   1. store_confirmations: [{ store_id, pre_confirmed }]  ← 新格式
//   2. applicable_merchant_ids: string[]                   ← 旧格式（视为全部预确认）
// =============================================================
function deriveStoreConfirmations(
  body: Record<string, unknown>
): Array<{ store_id: string; pre_confirmed: boolean }> | null {
  // 新格式：优先使用
  if (body.store_confirmations) {
    return body.store_confirmations as Array<{ store_id: string; pre_confirmed: boolean }>;
  }
  // 旧格式兼容：applicable_merchant_ids 里的门店全部视为预确认
  if (Array.isArray(body.applicable_merchant_ids) && body.applicable_merchant_ids.length > 0) {
    return (body.applicable_merchant_ids as string[]).map(id => ({
      store_id: id,
      pre_confirmed: true,
    }));
  }
  // 没有多店信息 → store_only deal，触发器自动处理
  return null;
}

// =============================================================
// PATCH /merchant-deals/:id/store-confirm
// 门店老板/店长 Accept / Decline / Remove 某个 brand_multi_store Deal
// =============================================================
async function handleStoreConfirm(
  admin: ReturnType<typeof createClient>,
  merchantId: string,
  dealId: string,
  userId: string,
  body: Record<string, unknown>
): Promise<Response> {
  const action = body.action as string;
  if (!["accept", "decline", "remove"].includes(action)) {
    return errorResponse("Invalid action. Must be 'accept', 'decline', or 'remove'.", 400);
  }

  // 验证该门店有此 deal_applicable_stores 记录
  const { data: storeRecord, error: fetchError } = await admin
    .from("deal_applicable_stores")
    .select("id, status, deal_scope")
    .eq("deal_id", dealId)
    .eq("store_id", merchantId)
    .single();

  if (fetchError || !storeRecord) {
    return errorResponse("No pending confirmation found for this store and deal.", 404);
  }

  if (action === "accept") {
    // accept 允许从 pending_store_confirmation 或 declined 状态执行（支持重新 approve）
    if (!["pending_store_confirmation", "declined"].includes(storeRecord.status)) {
      return errorResponse("This deal cannot be accepted in its current state.", 400);
    }

    const menuItemId = body.menu_item_id as string | null ?? null;
    let storeOriginalPrice: number | null = null;

    // 如果关联了菜品，读取菜品单价
    if (menuItemId) {
      const { data: menuItem } = await admin
        .from("menu_items")
        .select("price")
        .eq("id", menuItemId)
        .eq("merchant_id", merchantId)
        .single();

      if (menuItem?.price) {
        storeOriginalPrice = Number(menuItem.price);
      }
    }

    const { error } = await admin.rpc("accept_deal_store", {
      p_deal_id:              dealId,
      p_store_id:             merchantId,
      p_user_id:              userId,
      p_menu_item_id:         menuItemId,
      p_store_original_price: storeOriginalPrice,
    });

    if (error) return errorResponse(error.message, 500);
    return jsonResponse({ success: true, action: "accepted" });
  }

  if (action === "decline") {
    // 允许从 pending_store_confirmation 或 active 状态 decline（门店退出）
    if (!["pending_store_confirmation", "active"].includes(storeRecord.status)) {
      return errorResponse("This deal cannot be declined in its current state.", 400);
    }

    const { error } = await admin.rpc("decline_deal_store", {
      p_deal_id:  dealId,
      p_store_id: merchantId,
      p_user_id:  userId,
    });

    if (error) return errorResponse(error.message, 500);
    return jsonResponse({ success: true, action: "declined" });
  }

  if (action === "remove") {
    // remove 可对 active 或 pending 状态执行（主动退出）
    if (!["active", "pending_store_confirmation"].includes(storeRecord.status)) {
      return errorResponse("Cannot remove: store is not active or pending for this deal.", 400);
    }

    const { data: activeCount, error } = await admin.rpc("remove_deal_store", {
      p_deal_id:  dealId,
      p_store_id: merchantId,
      p_user_id:  userId,
    });

    if (error) return errorResponse(error.message, 500);
    return jsonResponse({
      success: true,
      action: "removed",
      remaining_active_stores: activeCount,
    });
  }

  return errorResponse("Internal error", 500);
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

// =============================================================
// V2.2 Deal 模板处理函数
// =============================================================

// 模板字段列表（从请求体提取）
const TEMPLATE_FIELDS = [
  "title", "description", "category", "original_price", "discount_price",
  "discount_label", "stock_limit", "package_contents", "usage_notes", "usage_note_images",
  "usage_days", "max_per_person", "is_stackable", "validity_type",
  "validity_days", "refund_policy", "image_urls", "dishes",
  "deal_type", "badge_text", "deal_category_id",
];

// 从模板数据构建 Deal 插入数据
function templateToDealPayload(
  template: Record<string, unknown>,
  merchantId: string,
  templateId: string,
): Record<string, unknown> {
  // 过期时间：根据 validity_type 计算
  let expiresAt: string;
  if (template.validity_type === "short_after_purchase" || template.validity_type === "long_after_purchase") {
    // 购买后 N 天有效 — 设置一个远期占位日期（购买时再计算实际到期）
    const future = new Date();
    future.setFullYear(future.getFullYear() + 2);
    expiresAt = future.toISOString();
  } else {
    // 固定日期 — 默认30天后过期
    const defaultExpiry = new Date();
    defaultExpiry.setDate(defaultExpiry.getDate() + 30);
    expiresAt = (template.expires_at as string) ?? defaultExpiry.toISOString();
  }

  return {
    merchant_id: merchantId,
    deal_template_id: templateId,
    title: template.title ?? "",
    description: template.description ?? "",
    category: template.category ?? "",
    original_price: template.original_price ?? 0,
    discount_price: template.discount_price ?? 0,
    discount_label: template.discount_label ?? "",
    stock_limit: template.stock_limit ?? 100,
    package_contents: template.package_contents ?? "",
    usage_notes: template.usage_notes ?? "",
    usage_note_images: template.usage_note_images ?? [],
    usage_days: template.usage_days ?? [],
    max_per_person: template.max_per_person ?? null,
    is_stackable: template.is_stackable ?? true,
    validity_type: template.validity_type ?? "fixed_date",
    validity_days: template.validity_days ?? 30,
    refund_policy: template.refund_policy ?? "Refund anytime before use, refund when expired",
    image_urls: template.image_urls ?? [],
    dishes: template.dishes ?? [],
    deal_type: template.deal_type ?? "regular",
    badge_text: template.badge_text ?? null,
    deal_category_id: template.deal_category_id ?? null,
    expires_at: expiresAt,
    is_active: false,
    deal_status: "pending",
  };
}

// GET /merchant-deals/templates — 获取品牌模板列表
async function handleGetTemplates(
  admin: ReturnType<typeof createClient>,
  brandId: string,
): Promise<Response> {
  const { data: templates, error } = await admin
    .from("deal_templates")
    .select("*, deal_template_stores(id, merchant_id, deal_id, is_customized)")
    .eq("brand_id", brandId)
    .order("created_at", { ascending: false });

  if (error) {
    return errorResponse(error.message, 500);
  }

  return jsonResponse({ templates: templates ?? [] });
}

// POST /merchant-deals/templates — 创建品牌模板
async function handleCreateTemplate(
  admin: ReturnType<typeof createClient>,
  brandId: string,
  userId: string,
  body: Record<string, unknown>,
): Promise<Response> {
  if (!body.title) {
    return errorResponse("Missing required field: title", 400);
  }

  // 提取模板字段
  const payload: Record<string, unknown> = {
    brand_id: brandId,
    created_by: userId,
  };
  for (const field of TEMPLATE_FIELDS) {
    if (body[field] !== undefined) {
      payload[field] = body[field];
    }
  }

  const { data: template, error } = await admin
    .from("deal_templates")
    .insert(payload)
    .select()
    .single();

  if (error) {
    return errorResponse(error.message, 500);
  }

  return jsonResponse({ template }, 201);
}

// PATCH /merchant-deals/templates/:templateId — 更新模板
async function handleUpdateTemplate(
  admin: ReturnType<typeof createClient>,
  brandId: string,
  templateId: string,
  body: Record<string, unknown>,
): Promise<Response> {
  // 校验模板属于该品牌
  const { data: existing, error: fetchError } = await admin
    .from("deal_templates")
    .select("id, brand_id")
    .eq("id", templateId)
    .single();

  if (fetchError || !existing) {
    return errorResponse("Template not found", 404);
  }
  if (existing.brand_id !== brandId) {
    return errorResponse("Access denied: template not in your brand", 403);
  }

  // 提取可更新字段
  const updatePayload: Record<string, unknown> = {
    updated_at: new Date().toISOString(),
  };
  for (const field of TEMPLATE_FIELDS) {
    if (body[field] !== undefined) {
      updatePayload[field] = body[field];
    }
  }

  const { data: template, error } = await admin
    .from("deal_templates")
    .update(updatePayload)
    .eq("id", templateId)
    .select()
    .single();

  if (error) {
    return errorResponse(error.message, 500);
  }

  return jsonResponse({ template });
}

// POST /merchant-deals/templates/:templateId/publish — 发布到选中门店
async function handlePublishTemplate(
  admin: ReturnType<typeof createClient>,
  brandId: string,
  templateId: string,
  body: Record<string, unknown>,
  authorizedMerchantIds: string[],
): Promise<Response> {
  // 校验模板
  const { data: template, error: tplError } = await admin
    .from("deal_templates")
    .select("*")
    .eq("id", templateId)
    .eq("brand_id", brandId)
    .single();

  if (tplError || !template) {
    return errorResponse("Template not found", 404);
  }

  // 获取要发布的门店 ID 列表
  const merchantIds = body.merchant_ids as string[] ?? [];
  if (merchantIds.length === 0) {
    return errorResponse("merchant_ids is required", 400);
  }

  // 校验门店都在品牌下
  const { data: brandStores } = await admin
    .from("merchants")
    .select("id")
    .eq("brand_id", brandId)
    .in("id", merchantIds);

  const validIds = (brandStores ?? []).map((s: { id: string }) => s.id);
  const invalidIds = merchantIds.filter(id => !validIds.includes(id));
  if (invalidIds.length > 0) {
    return errorResponse(`Stores not in brand: ${invalidIds.join(", ")}`, 400);
  }

  // 查询已发布的门店，避免重复
  const { data: existingStores } = await admin
    .from("deal_template_stores")
    .select("merchant_id")
    .eq("template_id", templateId);

  const alreadyPublished = new Set(
    (existingStores ?? []).map((s: { merchant_id: string }) => s.merchant_id)
  );

  const newMerchantIds = merchantIds.filter(id => !alreadyPublished.has(id));

  if (newMerchantIds.length === 0) {
    return jsonResponse({
      message: "All selected stores already have this deal",
      published: 0,
    });
  }

  // 为每家新门店创建 Deal 记录
  const createdDeals: { merchantId: string; dealId: string }[] = [];

  for (const mid of newMerchantIds) {
    const dealPayload = templateToDealPayload(template, mid, templateId);

    const { data: deal, error: dealError } = await admin
      .from("deals")
      .insert(dealPayload)
      .select("id")
      .single();

    if (dealError) {
      console.error(`[template-publish] Failed for merchant ${mid}:`, dealError);
      continue;
    }

    // 记录模板-门店关联
    await admin
      .from("deal_template_stores")
      .insert({
        template_id: templateId,
        merchant_id: mid,
        deal_id: deal.id,
        is_customized: false,
      });

    createdDeals.push({ merchantId: mid, dealId: deal.id });
  }

  return jsonResponse({
    message: `Published to ${createdDeals.length} stores`,
    published: createdDeals.length,
    deals: createdDeals,
  });
}

// POST /merchant-deals/templates/:templateId/sync — 同步模板更新到未自定义的门店
async function handleSyncTemplate(
  admin: ReturnType<typeof createClient>,
  brandId: string,
  templateId: string,
): Promise<Response> {
  // 获取模板
  const { data: template, error: tplError } = await admin
    .from("deal_templates")
    .select("*")
    .eq("id", templateId)
    .eq("brand_id", brandId)
    .single();

  if (tplError || !template) {
    return errorResponse("Template not found", 404);
  }

  // 获取未自定义的关联门店
  const { data: linkedStores } = await admin
    .from("deal_template_stores")
    .select("merchant_id, deal_id")
    .eq("template_id", templateId)
    .eq("is_customized", false);

  if (!linkedStores || linkedStores.length === 0) {
    return jsonResponse({ message: "No stores to sync", synced: 0 });
  }

  // 构建同步更新的字段
  const syncFields: Record<string, unknown> = {
    updated_at: new Date().toISOString(),
    deal_status: "pending",
    is_active: false,
  };
  for (const field of TEMPLATE_FIELDS) {
    if (template[field] !== undefined) {
      syncFields[field] = template[field];
    }
  }

  let synced = 0;
  for (const store of linkedStores) {
    if (!store.deal_id) continue;

    const { error: updateError } = await admin
      .from("deals")
      .update(syncFields)
      .eq("id", store.deal_id);

    if (!updateError) synced++;
  }

  return jsonResponse({
    message: `Synced ${synced} stores`,
    synced,
    total: linkedStores.length,
  });
}

// DELETE /merchant-deals/templates/:templateId — 删除模板
async function handleDeleteTemplate(
  admin: ReturnType<typeof createClient>,
  brandId: string,
  templateId: string,
): Promise<Response> {
  // 校验模板属于该品牌
  const { data: existing, error: fetchError } = await admin
    .from("deal_templates")
    .select("id, brand_id")
    .eq("id", templateId)
    .single();

  if (fetchError || !existing) {
    return errorResponse("Template not found", 404);
  }
  if (existing.brand_id !== brandId) {
    return errorResponse("Access denied: template not in your brand", 403);
  }

  // 删除模板（CASCADE 会删除 deal_template_stores，deals.deal_template_id 会置 NULL）
  const { error } = await admin
    .from("deal_templates")
    .delete()
    .eq("id", templateId);

  if (error) {
    return errorResponse(error.message, 500);
  }

  return jsonResponse({ success: true, deleted_id: templateId });
}

// =============================================================
// 选项组辅助函数
// =============================================================

// 选项组输入类型
interface OptionItemInput {
  name: string;
  price: number;
  sort_order?: number;
}

interface OptionGroupInput {
  name: string;
  select_min: number;
  select_max: number;
  sort_order?: number;
  items?: OptionItemInput[];
}

// 插入选项组和选项项
async function insertOptionGroups(
  admin: ReturnType<typeof createClient>,
  dealId: string,
  groups: OptionGroupInput[],
) {
  for (let gi = 0; gi < groups.length; gi++) {
    const g = groups[gi];
    const { data: group, error: groupErr } = await admin
      .from("deal_option_groups")
      .insert({
        deal_id:    dealId,
        name:       g.name,
        select_min: g.select_min ?? 1,
        select_max: g.select_max ?? 1,
        sort_order: g.sort_order ?? gi,
      })
      .select("id")
      .single();

    if (groupErr || !group) continue;

    if (g.items && g.items.length > 0) {
      const itemRows = g.items.map((item, ii) => ({
        group_id:   group.id,
        name:       item.name,
        price:      item.price ?? 0,
        sort_order: item.sort_order ?? ii,
      }));
      await admin.from("deal_option_items").insert(itemRows);
    }
  }
}

// 克隆选项组从旧 deal 到新 deal
async function cloneOptionGroups(
  admin: ReturnType<typeof createClient>,
  oldDealId: string,
  newDealId: string,
) {
  const { data: oldGroups } = await admin
    .from("deal_option_groups")
    .select("name, select_min, select_max, sort_order, deal_option_items(name, price, sort_order)")
    .eq("deal_id", oldDealId);

  if (!oldGroups || oldGroups.length === 0) return;

  for (const og of oldGroups) {
    const { data: newGroup } = await admin
      .from("deal_option_groups")
      .insert({
        deal_id:    newDealId,
        name:       og.name,
        select_min: og.select_min,
        select_max: og.select_max,
        sort_order: og.sort_order,
      })
      .select("id")
      .single();

    if (!newGroup) continue;

    const items = (og as Record<string, unknown>).deal_option_items as Array<Record<string, unknown>> | undefined;
    if (items && items.length > 0) {
      const newItems = items.map((item) => ({
        group_id:   newGroup.id,
        name:       item.name,
        price:      item.price,
        sort_order: item.sort_order,
      }));
      await admin.from("deal_option_items").insert(newItems);
    }
  }
}
