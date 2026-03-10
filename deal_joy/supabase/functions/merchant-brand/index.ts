// =============================================================
// DealJoy Edge Function: merchant-brand
// 品牌管理：品牌信息 CRUD、门店管理、管理员管理
// =============================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { resolveAuth, requirePermission } from "../_shared/auth.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-merchant-id",
  "Access-Control-Allow-Methods": "GET, POST, PATCH, DELETE, OPTIONS",
};

function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function errorResponse(message: string, status = 400): Response {
  return jsonResponse({ error: message }, status);
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  const supabaseAdmin = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    { auth: { persistSession: false } }
  );

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

  const {
    data: { user },
    error: authError,
  } = await supabaseUser.auth.getUser();

  if (authError || !user) {
    return errorResponse("Unauthorized", 401);
  }

  // 解析路径
  const url = new URL(req.url);
  const pathSegments = url.pathname
    .replace(/\/merchant-brand\/?/, "")
    .split("/")
    .filter(Boolean);

  try {
    // 鉴权
    let auth;
    try {
      auth = await resolveAuth(supabaseAdmin, user.id, req.headers);
    } catch (e) {
      // 品牌管理员可能没有关联 merchant，但有 brand_admins 记录
      // 这种情况下 resolveAuth 会抛异常，需要特殊处理
      const { data: brandAdmin } = await supabaseAdmin
        .from("brand_admins")
        .select("brand_id, role")
        .eq("user_id", user.id)
        .maybeSingle();

      if (!brandAdmin) {
        return errorResponse((e as Error).message, 403);
      }

      // 构造一个最小的 auth 对象
      const { data: brandStores } = await supabaseAdmin
        .from("merchants")
        .select("id")
        .eq("brand_id", brandAdmin.brand_id);

      auth = {
        userId: user.id,
        merchantId: brandStores?.[0]?.id ?? "",
        merchantIds: (brandStores ?? []).map((s: { id: string }) => s.id),
        role: brandAdmin.role === "owner" ? "brand_owner" : "brand_admin",
        brandId: brandAdmin.brand_id,
        isBrandAdmin: true,
        permissions: brandAdmin.role === "owner"
          ? ["scan", "orders", "orders_detail", "reviews", "deals", "store", "finance", "staff", "influencer", "marketing", "analytics", "settings", "brand"]
          : ["scan", "orders", "orders_detail", "reviews", "deals", "store", "finance", "staff", "influencer", "marketing", "analytics", "settings", "brand"],
      } as any;
    }

    // -------------------------------------------------------
    // POST /merchant-brand — 创建品牌（独立门店升级为连锁）
    // 此端点不要求已有 brandId，仅要求 store_owner
    // -------------------------------------------------------
    if (req.method === "POST" && pathSegments.length === 0) {
      if (auth.role !== "store_owner") {
        return errorResponse("Only store owner can create a brand", 403);
      }

      const body = await req.json();
      const { name, description, logo_url } = body;
      if (!name) {
        return errorResponse("Brand name is required");
      }

      // 检查门店是否已关联品牌
      const { data: currentMerchant } = await supabaseAdmin
        .from("merchants")
        .select("brand_id")
        .eq("id", auth.merchantId)
        .single();

      if (currentMerchant?.brand_id) {
        return errorResponse("This store is already associated with a brand");
      }

      // 1. 创建品牌
      const { data: brand, error: brandError } = await supabaseAdmin
        .from("brands")
        .insert({
          name,
          description: description ?? null,
          logo_url: logo_url ?? null,
          owner_id: user.id,
        })
        .select()
        .single();

      if (brandError) {
        return errorResponse(`Failed to create brand: ${brandError.message}`);
      }

      // 2. 关联门店到品牌
      await supabaseAdmin
        .from("merchants")
        .update({ brand_id: brand.id })
        .eq("id", auth.merchantId);

      // 3. 创建 brand_admins 记录（brand_owner）
      await supabaseAdmin
        .from("brand_admins")
        .insert({
          brand_id: brand.id,
          user_id: user.id,
          role: "owner",
        });

      return jsonResponse({ brand }, 201);
    }

    // 品牌管理权限检查
    requirePermission(auth, "brand");

    if (!auth.brandId) {
      return errorResponse("You are not associated with any brand", 403);
    }

    // -------------------------------------------------------
    // GET /merchant-brand — 品牌信息 + 门店列表 + 管理员列表
    // -------------------------------------------------------
    if (req.method === "GET" && pathSegments.length === 0) {
      const [brandRes, storesRes, adminsRes] = await Promise.all([
        supabaseAdmin
          .from("brands")
          .select("*")
          .eq("id", auth.brandId)
          .single(),
        supabaseAdmin
          .from("merchants")
          .select("id, name, address, city, status, logo_url, phone")
          .eq("brand_id", auth.brandId)
          .order("created_at"),
        supabaseAdmin
          .from("brand_admins")
          .select("id, user_id, role, created_at")
          .eq("brand_id", auth.brandId)
          .order("created_at"),
      ]);

      if (brandRes.error) {
        return errorResponse("Brand not found", 404);
      }

      // 补充管理员的 email 和 full_name（brand_admins.user_id 指向 auth.users，无法直接 join public.users）
      const rawAdmins = adminsRes.data ?? [];
      const adminUserIds = rawAdmins.map((a: any) => a.user_id);
      let adminsWithUserInfo = rawAdmins;
      if (adminUserIds.length > 0) {
        const { data: adminUsers } = await supabaseAdmin
          .from("users")
          .select("id, email, full_name")
          .in("id", adminUserIds);
        const userMap = new Map((adminUsers ?? []).map((u: any) => [u.id, u]));
        adminsWithUserInfo = rawAdmins.map((a: any) => ({
          ...a,
          email: (userMap.get(a.user_id) as any)?.email ?? null,
          full_name: (userMap.get(a.user_id) as any)?.full_name ?? null,
        }));
      }

      return jsonResponse({
        brand: brandRes.data,
        stores: storesRes.data ?? [],
        admins: adminsWithUserInfo,
      });
    }

    // -------------------------------------------------------
    // PATCH /merchant-brand — 更新品牌信息
    // -------------------------------------------------------
    if (req.method === "PATCH" && pathSegments.length === 0) {
      const body = await req.json();
      const allowedFields = [
        "name",
        "logo_url",
        "description",
        "category",
        "website",
        "company_name",
        "ein",
      ];

      const updateData: Record<string, unknown> = {};
      for (const field of allowedFields) {
        if (body[field] !== undefined) {
          updateData[field] = body[field];
        }
      }

      if (Object.keys(updateData).length === 0) {
        return errorResponse("No valid fields to update");
      }

      updateData.updated_at = new Date().toISOString();

      const { data, error } = await supabaseAdmin
        .from("brands")
        .update(updateData)
        .eq("id", auth.brandId)
        .select()
        .single();

      if (error) {
        return errorResponse(`Failed to update brand: ${error.message}`);
      }

      return jsonResponse({ brand: data });
    }

    // -------------------------------------------------------
    // POST /merchant-brand/stores — 添加新门店到品牌
    // -------------------------------------------------------
    if (
      req.method === "POST" &&
      pathSegments[0] === "stores"
    ) {
      const body = await req.json();

      if (body.merchant_id) {
        // 关联现有门店（更新 brand_id）
        const { data, error } = await supabaseAdmin
          .from("merchants")
          .update({ brand_id: auth.brandId })
          .eq("id", body.merchant_id)
          .select("id, name, address")
          .single();

        if (error) {
          return errorResponse(`Failed to add store: ${error.message}`);
        }
        return jsonResponse({ store: data });
      }

      // 创建新的空门店
      const { name, address, phone, city, category } = body;
      if (!name) {
        return errorResponse("Store name is required");
      }

      const { data, error } = await supabaseAdmin
        .from("merchants")
        .insert({
          name,
          address: address ?? "",
          phone: phone ?? "",
          city: city ?? "",
          category: category ?? "",
          brand_id: auth.brandId,
          user_id: user.id, // 暂时用品牌管理员的 user_id
          status: "approved", // 品牌管理员创建的门店直接 approved
        })
        .select("id, name, address")
        .single();

      if (error) {
        return errorResponse(`Failed to create store: ${error.message}`);
      }
      return jsonResponse({ store: data }, 201);
    }

    // -------------------------------------------------------
    // DELETE /merchant-brand/stores/:id — 从品牌移除门店
    // -------------------------------------------------------
    if (
      req.method === "DELETE" &&
      pathSegments[0] === "stores" &&
      pathSegments[1]
    ) {
      const storeId = pathSegments[1];

      // 只清除 brand_id，不删除门店
      const { error } = await supabaseAdmin
        .from("merchants")
        .update({ brand_id: null })
        .eq("id", storeId)
        .eq("brand_id", auth.brandId); // 安全校验：只能移除自己品牌的门店

      if (error) {
        return errorResponse(`Failed to remove store: ${error.message}`);
      }

      // 从多店 deal 的 applicable_merchant_ids 中移除该门店
      const { data: affectedDeals } = await supabaseAdmin
        .from("deals")
        .select("id, applicable_merchant_ids")
        .contains("applicable_merchant_ids", [storeId]);

      if (affectedDeals && affectedDeals.length > 0) {
        for (const deal of affectedDeals) {
          const updatedIds = (deal.applicable_merchant_ids || [])
            .filter((id: string) => id !== storeId);
          await supabaseAdmin
            .from("deals")
            .update({
              applicable_merchant_ids: updatedIds.length > 0 ? updatedIds : null,
            })
            .eq("id", deal.id);

          // 若 deal 无可用门店且非原 merchant 的 deal，自动停用
          if (updatedIds.length === 0) {
            const dealInfo = await supabaseAdmin
              .from("deals")
              .select("merchant_id, is_active")
              .eq("id", deal.id)
              .single();
            // 如果移除的是 deal 原始门店（不太可能），跳过
            if (dealInfo.data && dealInfo.data.merchant_id !== storeId && dealInfo.data.is_active) {
              // 多店 deal 已无可用门店但原店仍在，保持 active
            }
          }
        }
      }

      // 发通知给被移除门店的 owner
      try {
        const { data: storeOwnerData } = await supabaseAdmin
          .from("merchants")
          .select("user_id, name")
          .eq("id", storeId)
          .single();
        if (storeOwnerData) {
          await supabaseAdmin.from("merchant_notifications").insert({
            merchant_id: storeId,
            type: "system",
            title: "Removed from Brand",
            body: `Your store "${storeOwnerData.name}" has been removed from the brand.`,
            is_read: false,
          });
        }
      } catch (_) {
        // 通知失败不阻断主流程
      }

      return jsonResponse({ success: true });
    }

    // -------------------------------------------------------
    // POST /merchant-brand/admins — 邀请品牌管理员
    // -------------------------------------------------------
    if (
      req.method === "POST" &&
      pathSegments[0] === "admins"
    ) {
      // 仅 brand_owner 可邀请
      if (auth.role !== "brand_owner") {
        return errorResponse("Only brand owner can invite admins", 403);
      }

      const body = await req.json();
      const { email, role: inviteRole } = body;

      if (!email) {
        return errorResponse("Email is required");
      }

      const validRoles = ["admin"];
      if (!validRoles.includes(inviteRole ?? "admin")) {
        return errorResponse("Invalid role");
      }

      // 创建邀请记录
      const { data, error } = await supabaseAdmin
        .from("brand_invitations")
        .insert({
          brand_id: auth.brandId,
          invited_email: email,
          role: inviteRole ?? "admin",
          invited_by: user.id,
        })
        .select()
        .single();

      if (error) {
        return errorResponse(`Failed to create invitation: ${error.message}`);
      }

      // TODO: 发送邀请邮件（V2）

      return jsonResponse({ invitation: data }, 201);
    }

    // -------------------------------------------------------
    // DELETE /merchant-brand/admins/:id — 移除品牌管理员
    // -------------------------------------------------------
    if (
      req.method === "DELETE" &&
      pathSegments[0] === "admins" &&
      pathSegments[1]
    ) {
      if (auth.role !== "brand_owner") {
        return errorResponse("Only brand owner can remove admins", 403);
      }

      const adminId = pathSegments[1];

      // 不能移除自己
      const { data: targetAdmin } = await supabaseAdmin
        .from("brand_admins")
        .select("user_id")
        .eq("id", adminId)
        .single();

      if (targetAdmin?.user_id === user.id) {
        return errorResponse("Cannot remove yourself");
      }

      const { error } = await supabaseAdmin
        .from("brand_admins")
        .delete()
        .eq("id", adminId)
        .eq("brand_id", auth.brandId);

      if (error) {
        return errorResponse(`Failed to remove admin: ${error.message}`);
      }
      return jsonResponse({ success: true });
    }

    return errorResponse("Not found", 404);
  } catch (e) {
    const msg = e instanceof Error ? e.message : "Internal server error";
    const status = msg.includes("Unauthorized") || msg.includes("Forbidden")
      ? 403
      : 500;
    return errorResponse(msg, status);
  }
});
