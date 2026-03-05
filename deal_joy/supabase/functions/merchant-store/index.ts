// =============================================================
// DealJoy Edge Function: merchant-store
// 处理门店信息的 CRUD：基本信息、照片记录、营业时间
// =============================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// CORS 响应头（允许跨域调用）
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
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

  // 查询当前用户关联的 merchant_id
  const { data: merchant, error: merchantError } = await supabaseAdmin
    .from("merchants")
    .select("id")
    .eq("user_id", user.id)
    .single();

  if (merchantError || !merchant) {
    return errorResponse("Merchant not found for this user", 404);
  }

  const merchantId = merchant.id;

  // 解析 URL 路径
  const url = new URL(req.url);
  const pathSegments = url.pathname
    .replace(/\/merchant-store\/?/, "")
    .split("/")
    .filter(Boolean);

  // 路由分发
  try {
    // --- GET /merchant-store ---
    // 获取完整门店信息：基本信息 + 照片列表 + 营业时间 + 标签
    if (req.method === "GET" && pathSegments.length === 0) {
      return await handleGetStore(supabaseAdmin, merchantId);
    }

    // --- PATCH /merchant-store ---
    // 更新基本信息（店名、简介、电话、地址、标签）
    if (req.method === "PATCH" && pathSegments.length === 0) {
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
  merchantId: string
): Promise<Response> {
  // 获取基本信息
  const { data: storeData, error: storeError } = await supabase
    .from("merchants")
    .select(
      "id, name, description, phone, address, lat, lng, category, tags, is_online, status, homepage_cover_url, header_photo_style, header_photos"
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

  return jsonResponse({
    store: storeData,
    photos: photos ?? [],
    hours: hours ?? [],
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
