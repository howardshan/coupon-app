// =============================================================
// Crunchy Plum Edge Function: merchant-store
// 处理门店信息的 CRUD：基本信息、照片记录、营业时间
// =============================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { resolveAuth, requirePermission } from "../_shared/auth.ts";

// CORS 响应头（允许跨域调用）
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-merchant-id",
  "Access-Control-Allow-Methods": "GET, POST, PATCH, PUT, DELETE, OPTIONS",
};

// 统一 JSON 响应帮助函数
function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// 错误响应帮助函数
function errorResponse(message: string, status = 400): Response {
  return jsonResponse({ error: message }, status);
}

// =============================================================
// 主入口
// =============================================================
Deno.serve(async (req: Request) => {
  // 处理 CORS preflight 请求
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  // 初始化 Supabase 客户端（service_role 绕过 RLS，鉴权在函数内部完成）
  const supabaseAdmin = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    { auth: { persistSession: false } }
  );

  // 使用用户 JWT 初始化客户端（用于获取当前用户信息）
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

  // 验证 JWT，获取当前用户 ID
  const {
    data: { user },
    error: authError,
  } = await supabaseUser.auth.getUser();

  if (authError || !user) {
    return errorResponse("Unauthorized", 401);
  }

  // 解析 URL 路径
  const url = new URL(req.url);
  const pathSegments = url.pathname
    .replace(/\/merchant-store\/?/, "")
    .split("/")
    .filter(Boolean);

  // 统一鉴权：支持门店 owner / 品牌管理员 / manager / 员工
  let auth;
  try {
    auth = await resolveAuth(supabaseAdmin, user.id, req.headers);
  } catch (e) {
    return errorResponse((e as Error).message, 403);
  }

  const merchantId = auth.merchantId;

  // 调试日志：确认 resolveAuth 返回值
  console.log(`[merchant-store] user=${user.id}, role=${auth.role}, isBrandAdmin=${auth.isBrandAdmin}, brandId=${auth.brandId}, merchantId=${merchantId}, merchantIds=${auth.merchantIds.join(',')}`);

  // 路由分发
  try {
    // --- GET /merchant-store ---
    // 获取完整门店信息：基本信息 + 照片列表 + 营业时间 + 品牌信息 + 全局分类
    if (req.method === "GET" && pathSegments.length === 0) {
      return await handleGetStore(supabaseAdmin, merchantId, auth);
    }

    // --- GET /merchant-store/categories ---
    // 获取所有全局分类列表（供商家选择）
    if (req.method === "GET" && pathSegments[0] === "categories" && pathSegments.length === 1) {
      return await handleGetCategories(supabaseAdmin, merchantId);
    }

    // --- PUT /merchant-store/categories ---
    // 设置商家的全局分类（整体替换）
    if (req.method === "PUT" && pathSegments[0] === "categories" && pathSegments.length === 1) {
      requirePermission(auth, "store");
      const body = await req.json();
      return await handlePutCategories(supabaseAdmin, merchantId, body);
    }

    // --- GET /merchant-store/stores-list ---
    // 品牌管理员获取旗下所有门店列表
    if (req.method === "GET" && pathSegments[0] === "stores-list") {
      if (!auth.isBrandAdmin || !auth.brandId) {
        return errorResponse("Only brand admins can list stores", 403);
      }
      const { data: stores } = await supabaseAdmin
        .from("merchants")
        .select("id, name, address, city, status, logo_url, phone")
        .eq("brand_id", auth.brandId)
        .order("created_at");
      return jsonResponse({ stores: stores ?? [] });
    }

    // --- PATCH /merchant-store ---
    // 更新基本信息（店名、简介、电话、地址、标签）
    if (req.method === "PATCH" && pathSegments.length === 0) {
      requirePermission(auth, "store");
      const body = await req.json();
      return await handlePatchStore(supabaseAdmin, merchantId, body);
    }

    // --- PUT /merchant-store/hours ---
    // 批量更新 7 天营业时间
    if (
      req.method === "PUT" &&
      pathSegments[0] === "hours" &&
      pathSegments.length === 1
    ) {
      const body = await req.json();
      return await handlePutHours(supabaseAdmin, merchantId, body);
    }

    // --- POST /merchant-store/photos ---
    // 插入照片记录（文件本体通过 Supabase Storage 上传）
    if (
      req.method === "POST" &&
      pathSegments[0] === "photos" &&
      pathSegments.length === 1
    ) {
      const body = await req.json();
      return await handlePostPhoto(supabaseAdmin, merchantId, body);
    }

    // --- PATCH /merchant-store/photos/reorder ---
    // 批量更新照片排序
    if (
      req.method === "PATCH" &&
      pathSegments[0] === "photos" &&
      pathSegments[1] === "reorder" &&
      pathSegments.length === 2
    ) {
      const body = await req.json();
      return await handleReorderPhotos(supabaseAdmin, merchantId, body);
    }

    // --- DELETE /merchant-store/photos/:id ---
    // 删除照片记录
    if (
      req.method === "DELETE" &&
      pathSegments[0] === "photos" &&
      pathSegments.length === 2
    ) {
      const photoId = pathSegments[1];
      return await handleDeletePhoto(supabaseAdmin, merchantId, photoId);
    }

    // -------------------------------------------------------
    // POST /merchant-store/close — 闭店
    // 仅 store_owner 可操作，流程：
    // 1. 标记门店 status = 'closed'
    // 2. 下架所有 active deals
    // 3. 自动退款所有未核销的券（异步处理）
    // -------------------------------------------------------
    if (
      req.method === "POST" &&
      pathSegments[0] === "close" &&
      pathSegments.length === 1
    ) {
      if (auth.role !== "store_owner" && auth.role !== "brand_owner") {
        return errorResponse("Only store owner can close a store", 403);
      }

      // 1. 更新门店状态为 closed
      const { error: closeErr } = await supabaseAdmin
        .from("merchants")
        .update({
          status: "closed",
          is_online: false,
        })
        .eq("id", merchantId);

      if (closeErr) {
        return errorResponse(`Failed to close store: ${closeErr.message}`);
      }

      // 2. 下架所有该门店的 active deals
      await supabaseAdmin
        .from("deals")
        .update({
          is_active: false,
          deal_status: "inactive",
        })
        .eq("merchant_id", merchantId)
        .eq("is_active", true);

      // 3. 查找该门店所有 unused 订单并标记为待退款
      const { data: unusedOrders } = await supabaseAdmin
        .from("orders")
        .select("id")
        .in(
          "deal_id",
          (
            await supabaseAdmin
              .from("deals")
              .select("id")
              .eq("merchant_id", merchantId)
          ).data?.map((d: { id: string }) => d.id) ?? []
        )
        .eq("status", "unused");

      const pendingCount = unusedOrders?.length ?? 0;

      // 标记所有 unused 订单为 refund_requested（由 auto-refund cron 处理）
      if (pendingCount > 0) {
        const now = new Date().toISOString();
        const orderIds = unusedOrders!.map((o: { id: string }) => o.id);
        await supabaseAdmin
          .from("orders")
          .update({
            status: "refund_requested",
            refund_reason: "store_closed",
            refund_requested_at: now,
            updated_at: now,
          })
          .in("id", orderIds);

        // 同步更新 coupons 状态
        await supabaseAdmin
          .from("coupons")
          .update({ status: "refund_requested" })
          .in("order_id", orderIds);
      }

      // 4. 如果是连锁店，从多店 deal 的 applicable_merchant_ids 中移除
      const { data: multiDeals } = await supabaseAdmin
        .from("deals")
        .select("id, applicable_merchant_ids")
        .contains("applicable_merchant_ids", [merchantId]);

      if (multiDeals && multiDeals.length > 0) {
        for (const deal of multiDeals) {
          const updated = (deal.applicable_merchant_ids as string[]).filter(
            (id: string) => id !== merchantId
          );
          await supabaseAdmin
            .from("deals")
            .update({ applicable_merchant_ids: updated })
            .eq("id", deal.id);
        }
      }

      return jsonResponse({
        success: true,
        message: "Store has been closed successfully",
        pending_refund_count: pendingCount,
      });
    }

    // -------------------------------------------------------
    // POST /merchant-store/leave-brand — 解除品牌合作
    // 仅 store_owner 可操作
    // -------------------------------------------------------
    if (
      req.method === "POST" &&
      pathSegments[0] === "leave-brand" &&
      pathSegments.length === 1
    ) {
      if (auth.role !== "store_owner") {
        return errorResponse("Only store owner can leave a brand", 403);
      }

      // 检查门店是否关联品牌
      const { data: merchant } = await supabaseAdmin
        .from("merchants")
        .select("brand_id")
        .eq("id", merchantId)
        .single();

      if (!merchant?.brand_id) {
        return errorResponse("This store is not associated with any brand");
      }

      // 清除品牌关联
      const { error: leaveErr } = await supabaseAdmin
        .from("merchants")
        .update({ brand_id: null })
        .eq("id", merchantId);

      if (leaveErr) {
        return errorResponse(`Failed to leave brand: ${leaveErr.message}`);
      }

      const brandId = merchant.brand_id;

      // 更新多店通用 Deal 中的 applicable_merchant_ids
      // 从所有包含此门店 ID 的 Deal 中移除
      const { data: affectedDeals } = await supabaseAdmin
        .from("deals")
        .select("id, applicable_merchant_ids, merchant_id")
        .contains("applicable_merchant_ids", [merchantId]);

      let deactivatedDeals = 0;
      if (affectedDeals && affectedDeals.length > 0) {
        for (const deal of affectedDeals) {
          const updatedIds = (deal.applicable_merchant_ids || [])
            .filter((id: string) => id !== merchantId);
          await supabaseAdmin
            .from("deals")
            .update({
              applicable_merchant_ids: updatedIds.length > 0 ? updatedIds : null,
            })
            .eq("id", deal.id);

          // 如果 deal 原属于该门店且无其他可用门店，停用并退款
          if (deal.merchant_id === merchantId && updatedIds.length === 0) {
            await supabaseAdmin
              .from("deals")
              .update({ is_active: false, deal_status: "inactive" })
              .eq("id", deal.id);
            deactivatedDeals++;

            // 标记相关未使用订单为待退款
            const { data: unusedOrders } = await supabaseAdmin
              .from("orders")
              .select("id")
              .eq("deal_id", deal.id)
              .eq("status", "unused");
            if (unusedOrders && unusedOrders.length > 0) {
              const now = new Date().toISOString();
              await supabaseAdmin
                .from("orders")
                .update({
                  status: "refund_requested",
                  refund_reason: "store_left_brand",
                  refund_requested_at: now,
                  updated_at: now,
                })
                .in("id", unusedOrders.map((o: { id: string }) => o.id));
            }
          }
        }
      }

      // 通知品牌管理员
      try {
        const { data: storeName } = await supabaseAdmin
          .from("merchants")
          .select("name")
          .eq("id", merchantId)
          .single();

        // 查找品牌下其他门店，发通知
        const { data: brandStores } = await supabaseAdmin
          .from("merchants")
          .select("id")
          .eq("brand_id", brandId)
          .neq("id", merchantId)
          .limit(10);

        if (brandStores) {
          const notifications = brandStores.map((s: { id: string }) => ({
            merchant_id: s.id,
            type: "system",
            title: "Store Left Brand",
            body: `"${storeName?.name ?? 'A store'}" has left the brand.`,
            is_read: false,
          }));
          if (notifications.length > 0) {
            await supabaseAdmin.from("merchant_notifications").insert(notifications);
          }
        }
      } catch (_) {
        // 通知失败不阻断
      }

      return jsonResponse({
        success: true,
        message: "Successfully left the brand",
        deactivated_deals: deactivatedDeals,
      });
    }

    return errorResponse("Route not found", 404);
  } catch (err) {
    console.error("merchant-store error:", err);
    return errorResponse("Internal server error", 500);
  }
});

// =============================================================
// Handler: GET /merchant-store
// 返回完整门店信息（基本信息 + 照片 + 营业时间）
// =============================================================
async function handleGetStore(
  supabase: ReturnType<typeof createClient>,
  merchantId: string,
  auth: { role: string; isBrandAdmin: boolean; brandId: string | null; permissions: string[] }
): Promise<Response> {
  // 获取基本信息 + 品牌信息（如果有）
  const { data: storeData, error: storeError } = await supabase
    .from("merchants")
    .select(
      "id, name, description, phone, address, lat, lng, category, tags, is_online, status, homepage_cover_url, header_photo_style, header_photos, brand_id, brands(id, name, logo_url, description, commission_rate, stripe_account_id, stripe_account_email, stripe_account_status)"
    )
    .eq("id", merchantId)
    .single();

  if (storeError || !storeData) {
    return errorResponse("Failed to fetch store info", 500);
  }

  // 获取照片列表（按类型和排序）
  const { data: photos, error: photosError } = await supabase
    .from("merchant_photos")
    .select("id, photo_url, photo_type, sort_order, created_at")
    .eq("merchant_id", merchantId)
    .order("photo_type")
    .order("sort_order");

  if (photosError) {
    return errorResponse("Failed to fetch photos", 500);
  }

  // 获取营业时间（7 天）
  const { data: hours, error: hoursError } = await supabase
    .from("merchant_hours")
    .select("id, day_of_week, open_time, close_time, is_closed")
    .eq("merchant_id", merchantId)
    .order("day_of_week");

  if (hoursError) {
    return errorResponse("Failed to fetch business hours", 500);
  }

  // 如果有品牌关联，动态计算旗下门店数量
  if (storeData.brands && storeData.brand_id) {
    const { count } = await supabase
      .from("merchants")
      .select("id", { count: "exact", head: true })
      .eq("brand_id", storeData.brand_id);
    storeData.brands.store_count = count ?? 0;
  }

  // 获取商家关联的全局分类
  const { data: merchantCategories } = await supabase
    .from("merchant_categories")
    .select("category_id, categories(id, name, icon)")
    .eq("merchant_id", merchantId);

  const globalCategories = (merchantCategories ?? []).map(
    (mc: { categories: { id: number; name: string; icon: string | null } }) => mc.categories
  );

  return jsonResponse({
    store: storeData,
    photos: photos ?? [],
    hours: hours ?? [],
    global_categories: globalCategories,
    // 权限信息：前端据此控制 UI 显隐
    role: auth.role,
    is_brand_admin: auth.isBrandAdmin,
    permissions: auth.permissions,
  });
}

// =============================================================
// Handler: PATCH /merchant-store
// 更新门店基本信息（部分字段更新）
// =============================================================
async function handlePatchStore(
  supabase: ReturnType<typeof createClient>,
  merchantId: string,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  body: Record<string, any>
): Promise<Response> {
  // 只允许更新白名单字段，防止恶意修改 status/user_id 等敏感字段
  const allowedFields = ["name", "description", "phone", "address", "city", "lat", "lng", "tags", "homepage_cover_url", "header_photo_style", "header_photos"];
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const updateData: Record<string, any> = { updated_at: new Date().toISOString() };

  for (const field of allowedFields) {
    if (body[field] !== undefined) {
      updateData[field] = body[field];
    }
  }

  // 必须有至少一个字段
  if (Object.keys(updateData).length === 1) {
    return errorResponse("No valid fields to update", 400);
  }

  // 校验 tags 是数组且不超过 10 个
  if (updateData.tags !== undefined) {
    if (!Array.isArray(updateData.tags)) {
      return errorResponse("tags must be an array", 400);
    }
    if (updateData.tags.length > 10) {
      return errorResponse("Maximum 10 tags allowed", 400);
    }
  }

  const { data, error } = await supabase
    .from("merchants")
    .update(updateData)
    .eq("id", merchantId)
    .select("id, name, description, phone, address, lat, lng, tags, updated_at")
    .single();

  if (error) {
    return errorResponse(`Failed to update store: ${error.message}`, 500);
  }

  return jsonResponse({ success: true, store: data });
}

// =============================================================
// Handler: PUT /merchant-store/hours
// 批量更新 7 天营业时间（upsert）
// =============================================================
async function handlePutHours(
  supabase: ReturnType<typeof createClient>,
  merchantId: string,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  body: Record<string, any>
): Promise<Response> {
  const { hours } = body;

  if (!Array.isArray(hours) || hours.length === 0) {
    return errorResponse("hours must be a non-empty array", 400);
  }

  if (hours.length > 7) {
    return errorResponse("Maximum 7 days allowed", 400);
  }

  // 验证每条记录的合法性
  for (const h of hours) {
    if (typeof h.day_of_week !== "number" || h.day_of_week < 0 || h.day_of_week > 6) {
      return errorResponse(`Invalid day_of_week: ${h.day_of_week}`, 400);
    }
    if (!h.is_closed && (!h.open_time || !h.close_time)) {
      return errorResponse(
        `day_of_week ${h.day_of_week}: open_time and close_time required when not closed`,
        400
      );
    }
  }

  // 构造 upsert 数据（加上 merchant_id）
  const upsertData = hours.map((h) => ({
    merchant_id: merchantId,
    day_of_week: h.day_of_week,
    open_time: h.is_closed ? null : h.open_time,
    close_time: h.is_closed ? null : h.close_time,
    is_closed: h.is_closed ?? false,
  }));

  const { data, error } = await supabase
    .from("merchant_hours")
    .upsert(upsertData, { onConflict: "merchant_id,day_of_week" })
    .select("id, day_of_week, open_time, close_time, is_closed");

  if (error) {
    return errorResponse(`Failed to update hours: ${error.message}`, 500);
  }

  return jsonResponse({ success: true, hours: data });
}

// =============================================================
// Handler: POST /merchant-store/photos
// 插入照片记录（文件本体已由客户端上传到 Storage）
// =============================================================
async function handlePostPhoto(
  supabase: ReturnType<typeof createClient>,
  merchantId: string,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  body: Record<string, any>
): Promise<Response> {
  const { photo_url, photo_type, sort_order } = body;

  if (!photo_url || typeof photo_url !== "string") {
    return errorResponse("photo_url is required", 400);
  }

  const validTypes = ["storefront", "environment", "product", "cover"];
  if (!validTypes.includes(photo_type)) {
    return errorResponse(`photo_type must be one of: ${validTypes.join(", ")}`, 400);
  }

  // 各类型照片数量上限
  const maxPhotos: Record<string, number> = {
    cover: 5,
    storefront: 3,
    environment: 10,
    product: 10,
  };

  // 检查当前类型已有数量
  {
    const limit = maxPhotos[photo_type];
    const { count, error: countError } = await supabase
      .from("merchant_photos")
      .select("id", { count: "exact", head: true })
      .eq("merchant_id", merchantId)
      .eq("photo_type", photo_type);

    if (countError) {
      return errorResponse("Failed to check photo count", 500);
    }
    if ((count ?? 0) >= limit) {
      return errorResponse(`Maximum ${limit} ${photo_type} photos allowed. Delete one first.`, 400);
    }
  }

  const { data, error } = await supabase
    .from("merchant_photos")
    .insert({
      merchant_id: merchantId,
      photo_url,
      photo_type,
      sort_order: sort_order ?? 0,
    })
    .select("id, photo_url, photo_type, sort_order, created_at")
    .single();

  if (error) {
    return errorResponse(`Failed to save photo: ${error.message}`, 500);
  }

  return jsonResponse({ success: true, photo: data }, 201);
}

// =============================================================
// Handler: DELETE /merchant-store/photos/:id
// 删除照片记录（客户端需同时从 Storage 删除文件）
// =============================================================
async function handleDeletePhoto(
  supabase: ReturnType<typeof createClient>,
  merchantId: string,
  photoId: string
): Promise<Response> {
  // 验证此照片属于当前商家
  const { data: photo, error: fetchError } = await supabase
    .from("merchant_photos")
    .select("id, photo_url")
    .eq("id", photoId)
    .eq("merchant_id", merchantId)
    .single();

  if (fetchError || !photo) {
    return errorResponse("Photo not found or access denied", 404);
  }

  // 删除数据库记录
  const { error: deleteError } = await supabase
    .from("merchant_photos")
    .delete()
    .eq("id", photoId)
    .eq("merchant_id", merchantId);

  if (deleteError) {
    return errorResponse(`Failed to delete photo: ${deleteError.message}`, 500);
  }

  // 尝试从 Storage 删除文件（提取存储路径）
  // photo_url 格式: https://{project}.supabase.co/storage/v1/object/public/merchant-photos/{path}
  try {
    const storageUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const prefix = `${storageUrl}/storage/v1/object/public/merchant-photos/`;
    if (photo.photo_url.startsWith(prefix)) {
      const storagePath = photo.photo_url.replace(prefix, "");
      await supabase.storage.from("merchant-photos").remove([storagePath]);
    }
  } catch (storageErr) {
    // Storage 删除失败不阻塞，记录日志即可
    console.warn("Failed to delete from storage:", storageErr);
  }

  return jsonResponse({ success: true, deleted_id: photoId });
}

// =============================================================
// Handler: PATCH /merchant-store/photos/reorder
// 批量更新照片排序（照片 ID 列表顺序即新的 sort_order）
// =============================================================
async function handleReorderPhotos(
  supabase: ReturnType<typeof createClient>,
  merchantId: string,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  body: Record<string, any>
): Promise<Response> {
  const { ordered_ids } = body;

  if (!Array.isArray(ordered_ids) || ordered_ids.length === 0) {
    return errorResponse("ordered_ids must be a non-empty array", 400);
  }

  // 验证所有照片 ID 属于当前商家
  const { data: photos, error: fetchError } = await supabase
    .from("merchant_photos")
    .select("id")
    .eq("merchant_id", merchantId)
    .in("id", ordered_ids);

  if (fetchError) {
    return errorResponse("Failed to verify photo ownership", 500);
  }

  const ownedIds = new Set((photos ?? []).map((p: { id: string }) => p.id));
  for (const id of ordered_ids) {
    if (!ownedIds.has(id)) {
      return errorResponse(`Photo ${id} not found or access denied`, 403);
    }
  }

  // 批量更新 sort_order
  for (let i = 0; i < ordered_ids.length; i++) {
    const { error } = await supabase
      .from("merchant_photos")
      .update({ sort_order: i })
      .eq("id", ordered_ids[i])
      .eq("merchant_id", merchantId);

    if (error) {
      return errorResponse(`Failed to update sort_order for ${ordered_ids[i]}`, 500);
    }
  }

  return jsonResponse({ success: true, count: ordered_ids.length });
}

// =============================================================
// Handler: GET /merchant-store/categories
// 返回所有全局分类 + 当前商家已选分类 ID 列表
// =============================================================
async function handleGetCategories(
  supabase: ReturnType<typeof createClient>,
  merchantId: string
): Promise<Response> {
  // 获取所有全局分类
  const { data: allCategories, error: catErr } = await supabase
    .from("categories")
    .select("id, name, icon, order")
    .order("order");

  if (catErr) {
    return errorResponse(`Failed to fetch categories: ${catErr.message}`, 500);
  }

  // 获取商家已选的分类 ID
  const { data: selected, error: selErr } = await supabase
    .from("merchant_categories")
    .select("category_id")
    .eq("merchant_id", merchantId);

  if (selErr) {
    return errorResponse(`Failed to fetch merchant categories: ${selErr.message}`, 500);
  }

  const selectedIds = (selected ?? []).map((s: { category_id: number }) => s.category_id);

  return jsonResponse({
    categories: allCategories ?? [],
    selected_ids: selectedIds,
  });
}

// =============================================================
// Handler: PUT /merchant-store/categories
// 设置商家的全局分类（整体替换：先删后插）
// =============================================================
async function handlePutCategories(
  supabase: ReturnType<typeof createClient>,
  merchantId: string,
  body: Record<string, unknown>
): Promise<Response> {
  const { category_ids } = body;

  if (!Array.isArray(category_ids)) {
    return errorResponse("category_ids must be an array", 400);
  }

  // 最多选 5 个分类
  if (category_ids.length > 5) {
    return errorResponse("Maximum 5 categories allowed", 400);
  }

  // 校验所有 ID 为整数
  for (const id of category_ids) {
    if (typeof id !== "number" || !Number.isInteger(id)) {
      return errorResponse("All category_ids must be integers", 400);
    }
  }

  // 先删除旧的关联
  const { error: delErr } = await supabase
    .from("merchant_categories")
    .delete()
    .eq("merchant_id", merchantId);

  if (delErr) {
    return errorResponse(`Failed to clear categories: ${delErr.message}`, 500);
  }

  // 插入新的关联
  if (category_ids.length > 0) {
    const rows = category_ids.map((cid: number) => ({
      merchant_id: merchantId,
      category_id: cid,
    }));

    const { error: insErr } = await supabase
      .from("merchant_categories")
      .insert(rows);

    if (insErr) {
      return errorResponse(`Failed to set categories: ${insErr.message}`, 500);
    }
  }

  return jsonResponse({ success: true, category_ids });
}
