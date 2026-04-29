// =============================================================
// Crunchy Plum Edge Function: merchant-brand
// 品牌管理：品牌信息 CRUD、门店管理、管理员管理
// =============================================================

import Stripe from "https://esm.sh/stripe@14.1.0?target=deno";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { resolveAuth, requirePermission } from "../_shared/auth.ts";

// Stripe 客户端（品牌 Connect 账户用）
const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY") ?? "", {
  apiVersion: "2024-04-10",
});

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

      // 通过 email 查找门店 owner，再关联
      if (body.email && !body.merchant_id) {
        // 先通过 email 找到 auth user
        const { data: userData, error: userError } = await supabaseAdmin
          .auth.admin.listUsers();

        if (userError) {
          return errorResponse(`Failed to lookup user: ${userError.message}`);
        }

        const targetUser = (userData?.users ?? []).find(
          (u: { email?: string }) => u.email === body.email
        );

        if (!targetUser) {
          return errorResponse(`No user found with email: ${body.email}`, 404);
        }

        // 查找该用户拥有的门店
        const { data: userStores, error: storeError } = await supabaseAdmin
          .from("merchants")
          .select("id, name, address, brand_id")
          .eq("user_id", targetUser.id);

        if (storeError || !userStores || userStores.length === 0) {
          return errorResponse(`No store found for user: ${body.email}`, 404);
        }

        // 检查门店是否已属于其他品牌
        const store = userStores[0];
        if (store.brand_id && store.brand_id !== auth.brandId) {
          return errorResponse("This store already belongs to another brand");
        }
        if (store.brand_id === auth.brandId) {
          return errorResponse("This store is already in your brand");
        }

        // 关联门店到品牌
        const { data, error } = await supabaseAdmin
          .from("merchants")
          .update({ brand_id: auth.brandId })
          .eq("id", store.id)
          .select("id, name, address")
          .single();

        if (error) {
          return errorResponse(`Failed to add store: ${error.message}`);
        }
        return jsonResponse({ store: data });
      }

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

      // 同步更新 deal_applicable_stores 表：将该门店所有 active/pending 记录标记为 removed（品牌踢出）
      const { data: dasRecords } = await supabaseAdmin
        .from("deal_applicable_stores")
        .select("deal_id")
        .eq("store_id", storeId)
        .in("status", ["active", "pending_store_confirmation"]);

      if (dasRecords && dasRecords.length > 0) {
        for (const record of dasRecords) {
          await supabaseAdmin.rpc("remove_deal_store", {
            p_deal_id: record.deal_id,
            p_store_id: storeId,
            p_user_id: user.id,
            p_removed_reason: "brand_kicked",
          });
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

    // -------------------------------------------------------
    // POST /merchant-brand/connect — 创建品牌 Stripe Express 账户
    // -------------------------------------------------------
    if (req.method === "POST" && pathSegments[0] === "connect" && !pathSegments[1]) {
      if (auth.role !== "brand_owner") {
        return errorResponse("Only brand owner can connect Stripe account", 403);
      }

      // 检查是否已有 Stripe 账户
      const { data: existingBrand } = await supabaseAdmin
        .from("brands")
        .select("stripe_account_id, stripe_account_status")
        .eq("id", auth.brandId)
        .single();

      if (existingBrand?.stripe_account_id && existingBrand.stripe_account_status === "connected") {
        return errorResponse("Brand already has a connected Stripe account");
      }

      // 复用 merchant-withdrawal 已配置的 Stripe Connect 重定向 URL
      const returnUrl  = (Deno.env.get("STRIPE_CONNECT_RETURN_URL") ?? "").trim();
      const refreshUrl = (Deno.env.get("STRIPE_CONNECT_REFRESH_URL") ?? "").trim();
      if (!returnUrl || !refreshUrl) {
        return errorResponse("STRIPE_CONNECT_RETURN_URL / STRIPE_CONNECT_REFRESH_URL is not configured", 500);
      }

      // 复用现有 Stripe 账户（若已创建但未完成 onboarding）
      let stripeAccountId = existingBrand?.stripe_account_id ?? null;

      // 校验已存在的 Stripe 账户在当前平台下是否仍可访问
      // 切换 Stripe 平台账户后，旧账户 ID 会抛 "does not have access" / account_invalid，
      // 此时清空 DB 字段让下方 create 分支生成带 controller.losses 的新账户
      if (stripeAccountId) {
        try {
          const existing = await stripe.accounts.retrieve(stripeAccountId);
          if ((existing as { deleted?: boolean }).deleted) {
            stripeAccountId = null;
          }
        } catch (err) {
          const code = (err as { code?: string }).code;
          const msg  = String((err as { message?: string }).message ?? "");
          const isStale =
            code === "account_invalid" ||
            code === "resource_missing" ||
            msg.includes("does not have access to account") ||
            msg.includes("Application access may have been revoked");
          if (!isStale) throw err;
          console.log(`[Connect] stale brand stripe_account_id=${stripeAccountId}, clearing and recreating`);
          await supabaseAdmin
            .from("brands")
            .update({ stripe_account_id: null, stripe_account_status: "not_connected" })
            .eq("id", auth.brandId);
          stripeAccountId = null;
        }
      }

      if (!stripeAccountId) {
        // 查询品牌信息（用于 Stripe metadata）
        const { data: brandInfo } = await supabaseAdmin
          .from("brands")
          .select("name")
          .eq("id", auth.brandId)
          .single();

        // 创建 Connect 账户（controller 模式，平台承担损失）
        // controller.losses.payments=application 让平台拥有 loss liability，
        // 才能调用 Reserves Preview 写接口（POST /v1/reserve/holds）
        // controller.stripe_dashboard.type=express 保留 Express 商家面板 UX
        const account = await stripe.accounts.create({
          controller: {
            losses:                 { payments: "application" },
            fees:                   { payer: "application" },
            stripe_dashboard:       { type: "express" },
            requirement_collection: "stripe",
          },
          capabilities: {
            card_payments: { requested: true },
            transfers:     { requested: true },
          },
          metadata: {
            brand_id:   auth.brandId,
            brand_name: brandInfo?.name ?? "",
          },
        });
        stripeAccountId = account.id;

        // 保存 Stripe 账户 ID 到 brands 表
        await supabaseAdmin
          .from("brands")
          .update({
            stripe_account_id:     stripeAccountId,
            stripe_account_status: "pending",
          })
          .eq("id", auth.brandId);
      }

      // 生成 onboarding 链接
      const accountLink = await stripe.accountLinks.create({
        account:     stripeAccountId,
        refresh_url: refreshUrl,
        return_url:  returnUrl,
        type:        "account_onboarding",
      });

      return jsonResponse({ url: accountLink.url, stripe_account_id: stripeAccountId });
    }

    // -------------------------------------------------------
    // POST /merchant-brand/connect/refresh — 刷新品牌 Stripe 账户状态
    // -------------------------------------------------------
    if (req.method === "POST" && pathSegments[0] === "connect" && pathSegments[1] === "refresh") {
      const { data: brandData } = await supabaseAdmin
        .from("brands")
        .select("stripe_account_id")
        .eq("id", auth.brandId)
        .single();

      if (!brandData?.stripe_account_id) {
        return errorResponse("No Stripe account found for this brand", 404);
      }

      // 从 Stripe 读取账户状态；若账户失效（切换平台后的典型情况）则清空重连
      let account;
      try {
        account = await stripe.accounts.retrieve(brandData.stripe_account_id);
      } catch (err) {
        const code = (err as { code?: string }).code;
        const msg  = String((err as { message?: string }).message ?? "");
        const isStale =
          code === "account_invalid" ||
          code === "resource_missing" ||
          msg.includes("does not have access to account") ||
          msg.includes("Application access may have been revoked");
        if (!isStale) throw err;
        console.log(`[Connect] stale brand stripe_account_id=${brandData.stripe_account_id} in /refresh, clearing`);
        await supabaseAdmin
          .from("brands")
          .update({ stripe_account_id: null, stripe_account_status: "not_connected" })
          .eq("id", auth.brandId);
        return jsonResponse({
          is_connected:    false,
          account_id:      null,
          account_status:  "not_connected",
          account_email:   null,
          charges_enabled: false,
          payouts_enabled: false,
          needs_reconnect: true,
        });
      }

      // 补请求缺失的 capabilities（修复历史账户未传 capabilities 导致受限）
      const caps = (account as any).capabilities ?? {};
      if (caps.card_payments === undefined || caps.transfers === undefined) {
        try {
          await stripe.accounts.update(brandData.stripe_account_id, {
            capabilities: {
              card_payments: { requested: true },
              transfers:     { requested: true },
            },
          } as any);
        } catch (capErr) {
          console.error("[Connect] 补请求 capabilities 失败:", capErr);
        }
      }

      const isConnected = account.charges_enabled && account.payouts_enabled;
      const newStatus = isConnected ? "connected"
        : account.requirements?.disabled_reason ? "restricted"
        : "pending";
      const accountEmail = (account as any).email ?? null;

      await supabaseAdmin
        .from("brands")
        .update({ stripe_account_status: newStatus, stripe_account_email: accountEmail })
        .eq("id", auth.brandId);

      return jsonResponse({
        is_connected:    isConnected,
        account_id:      brandData.stripe_account_id,
        account_status:  newStatus,
        account_email:   accountEmail,
        charges_enabled: account.charges_enabled,
        payouts_enabled: account.payouts_enabled,
      });
    }

    // -------------------------------------------------------
    // GET /merchant-brand/connect/dashboard — 品牌 Stripe Dashboard 链接
    // -------------------------------------------------------
    if (req.method === "GET" && pathSegments[0] === "connect" && pathSegments[1] === "dashboard") {
      const { data: brandData } = await supabaseAdmin
        .from("brands")
        .select("stripe_account_id, stripe_account_status")
        .eq("id", auth.brandId)
        .single();

      if (!brandData?.stripe_account_id) {
        return errorResponse("No Stripe account found for this brand", 404);
      }
      if (brandData.stripe_account_status !== "connected") {
        return errorResponse("Stripe account is not fully connected yet");
      }

      const loginLink = await stripe.accounts.createLoginLink(brandData.stripe_account_id);
      return jsonResponse({ url: loginLink.url });
    }

    // -------------------------------------------------------
    // GET /merchant-brand/account — 品牌 Stripe 账户信息
    // -------------------------------------------------------
    if (req.method === "GET" && pathSegments[0] === "account") {
      const { data: brandData } = await supabaseAdmin
        .from("brands")
        .select("stripe_account_id, stripe_account_status, stripe_account_email")
        .eq("id", auth.brandId)
        .single();

      const isConnected = brandData?.stripe_account_status === "connected";
      return jsonResponse({
        is_connected:   isConnected,
        account_id:     brandData?.stripe_account_id ?? null,
        account_status: brandData?.stripe_account_status ?? "not_connected",
        account_email:  brandData?.stripe_account_email ?? null,
      });
    }

    // -------------------------------------------------------
    // GET /merchant-brand/earnings/summary — 品牌收入概览
    // -------------------------------------------------------
    if (req.method === "GET" && pathSegments[0] === "earnings" && pathSegments[1] === "summary") {
      const now = new Date();
      const defaultMonth = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}`;
      const monthParam  = new URL(req.url).searchParams.get("month") ?? defaultMonth;
      const monthStart  = /^\d{4}-\d{2}$/.test(monthParam) ? `${monthParam}-01` : monthParam;

      const { data, error } = await supabaseAdmin.rpc("get_brand_earnings_summary", {
        p_brand_id:    auth.brandId,
        p_month_start: monthStart,
      });

      if (error) {
        console.error("brand earnings summary error:", error);
        return errorResponse(`Failed to fetch brand earnings summary: ${error.message}`, 500);
      }

      const row = Array.isArray(data) ? data[0] : data;
      return jsonResponse({
        month:              monthParam,
        month_start:        monthStart,
        total_brand_fee:    parseFloat(row?.total_brand_fee    ?? "0"),
        pending_settlement: parseFloat(row?.pending_settlement ?? "0"),
        settled_amount:     parseFloat(row?.settled_amount     ?? "0"),
      });
    }

    // -------------------------------------------------------
    // GET /merchant-brand/earnings/transactions — 品牌交易明细
    // -------------------------------------------------------
    if (req.method === "GET" && pathSegments[0] === "earnings" && pathSegments[1] === "transactions") {
      const sp       = new URL(req.url).searchParams;
      const dateFrom = sp.get("date_from") || null;
      const dateTo   = sp.get("date_to")   || null;
      const page     = Math.max(1, parseInt(sp.get("page") ?? "1"));
      const perPage  = Math.min(100, Math.max(1, parseInt(sp.get("per_page") ?? "20")));

      const { data, error } = await supabaseAdmin.rpc("get_brand_transactions", {
        p_brand_id:  auth.brandId,
        p_date_from: dateFrom,
        p_date_to:   dateTo,
        p_page:      page,
        p_per_page:  perPage,
      });

      if (error) {
        console.error("brand transactions error:", error);
        return errorResponse(`Failed to fetch brand transactions: ${error.message}`, 500);
      }

      const rows = Array.isArray(data) ? data : [];
      const totalCount = rows.length > 0 ? parseInt(rows[0].total_count ?? "0") : 0;

      return jsonResponse({
        data: rows.map((row: Record<string, string>) => ({
          order_id:    row.order_id,
          store_name:  row.store_name   ?? "",
          deal_title:  row.deal_title   ?? "",
          amount:      parseFloat(row.amount      ?? "0"),
          brand_fee:   parseFloat(row.brand_fee   ?? "0"),
          status:      row.status,
          created_at:  row.created_at,
        })),
        pagination: {
          page,
          per_page: perPage,
          total:    totalCount,
          has_more: page * perPage < totalCount,
        },
      });
    }

    // -------------------------------------------------------
    // GET /merchant-brand/earnings/balance — 品牌可提现余额
    // -------------------------------------------------------
    if (req.method === "GET" && pathSegments[0] === "earnings" && pathSegments[1] === "balance") {
      const { data, error } = await supabaseAdmin.rpc("get_brand_balance", {
        p_brand_id: auth.brandId,
      });

      if (error) {
        console.error("brand balance error:", error);
        return errorResponse(`Failed to fetch brand balance: ${error.message}`, 500);
      }

      const row = Array.isArray(data) ? data[0] : data;
      return jsonResponse({
        available_balance: parseFloat(row?.available_balance ?? "0"),
        total_earned:      parseFloat(row?.total_earned      ?? "0"),
        total_withdrawn:   parseFloat(row?.total_withdrawn   ?? "0"),
        currency:          "usd",
      });
    }

    // -------------------------------------------------------
    // POST /merchant-brand/withdraw — 品牌提现
    // -------------------------------------------------------
    if (req.method === "POST" && pathSegments[0] === "withdraw" && !pathSegments[1]) {
      if (auth.role !== "brand_owner") {
        return errorResponse("Only brand owner can initiate withdrawal", 403);
      }

      const body = await req.json();
      const amount = Number(body.amount);
      if (!amount || amount < 10) {
        return errorResponse("Minimum withdrawal amount is $10.00");
      }

      // 验证品牌 Stripe 账户状态
      const { data: brandData } = await supabaseAdmin
        .from("brands")
        .select("stripe_account_id, stripe_account_status, name")
        .eq("id", auth.brandId)
        .single();

      if (!brandData?.stripe_account_id || brandData.stripe_account_status !== "connected") {
        return errorResponse("Brand Stripe account is not connected. Please complete Stripe onboarding first.");
      }

      // 检查是否有未完成的提现
      const { data: pendingW } = await supabaseAdmin
        .from("brand_withdrawals")
        .select("id")
        .eq("brand_id", auth.brandId)
        .in("status", ["pending", "processing"])
        .maybeSingle();

      if (pendingW) {
        return errorResponse("There is already a pending withdrawal. Please wait for it to complete.");
      }

      // 验证余额是否充足
      const { data: balanceData, error: balanceErr } = await supabaseAdmin.rpc("get_brand_balance", {
        p_brand_id: auth.brandId,
      });
      if (balanceErr) {
        return errorResponse(`Failed to check balance: ${balanceErr.message}`, 500);
      }
      const balRow = Array.isArray(balanceData) ? balanceData[0] : balanceData;
      const availableBalance = parseFloat(String(balRow?.available_balance ?? "0"));
      if (amount > availableBalance + 0.01) {
        return errorResponse(`Insufficient balance. Available: $${availableBalance.toFixed(2)}`);
      }

      // 创建 brand_withdrawals 记录（初始 pending）
      const { data: withdrawal, error: wInsertErr } = await supabaseAdmin
        .from("brand_withdrawals")
        .insert({
          brand_id:     auth.brandId,
          amount,
          status:       "pending",
          requested_by: user.id,
          requested_at: new Date().toISOString(),
        })
        .select()
        .single();

      if (wInsertErr) {
        return errorResponse(`Failed to create withdrawal: ${wInsertErr.message}`, 500);
      }

      // 调用 Stripe Transfer API
      try {
        const transfer = await stripe.transfers.create(
          {
            amount:      Math.round(amount * 100),
            currency:    "usd",
            destination: brandData.stripe_account_id,
            metadata:    { brand_withdrawal_id: withdrawal.id, brand_id: auth.brandId },
          },
          { idempotencyKey: withdrawal.id }
        );

        // 成功：更新为 completed
        await supabaseAdmin
          .from("brand_withdrawals")
          .update({
            stripe_transfer_id: transfer.id,
            status:             "completed",
            completed_at:       new Date().toISOString(),
          })
          .eq("id", withdrawal.id);

        return jsonResponse({
          withdrawal: { ...withdrawal, status: "completed", stripe_transfer_id: transfer.id },
        }, 201);
      } catch (stripeErr) {
        const reason = stripeErr instanceof Error ? stripeErr.message : "Stripe transfer failed";
        await supabaseAdmin
          .from("brand_withdrawals")
          .update({ status: "failed", failure_reason: reason })
          .eq("id", withdrawal.id);
        return errorResponse(`Withdrawal failed: ${reason}`, 502);
      }
    }

    // -------------------------------------------------------
    // GET /merchant-brand/withdraw/history — 品牌提现记录
    // -------------------------------------------------------
    if (req.method === "GET" && pathSegments[0] === "withdraw" && pathSegments[1] === "history") {
      const sp      = new URL(req.url).searchParams;
      const page    = Math.max(1, parseInt(sp.get("page") ?? "1"));
      const perPage = Math.min(50, Math.max(1, parseInt(sp.get("per_page") ?? "20")));
      const offset  = (page - 1) * perPage;

      const { data, error, count } = await supabaseAdmin
        .from("brand_withdrawals")
        .select("*", { count: "exact" })
        .eq("brand_id", auth.brandId)
        .order("requested_at", { ascending: false })
        .range(offset, offset + perPage - 1);

      if (error) {
        return errorResponse(`Failed to fetch withdrawal history: ${error.message}`, 500);
      }

      return jsonResponse({
        data: data ?? [],
        pagination: {
          page,
          per_page: perPage,
          total:    count ?? 0,
          has_more: offset + perPage < (count ?? 0),
        },
      });
    }

    // -------------------------------------------------------
    // GET /merchant-brand/withdrawal/settings — 获取品牌自动提现设置
    // -------------------------------------------------------
    if (req.method === "GET" && pathSegments[0] === "withdrawal" && pathSegments[1] === "settings") {
      const { data, error } = await supabaseAdmin
        .from("brand_withdrawal_settings")
        .select("*")
        .eq("brand_id", auth.brandId)
        .maybeSingle();

      if (error) {
        return errorResponse(`Failed to fetch settings: ${error.message}`, 500);
      }

      // 没有设置记录则返回默认值
      const settings = data ?? {
        auto_withdrawal_enabled: false,
        auto_withdrawal_frequency: "weekly",
        auto_withdrawal_day: 1,
        min_withdrawal_amount: 50.00,
      };

      return jsonResponse({ settings });
    }

    // -------------------------------------------------------
    // PATCH /merchant-brand/withdrawal/settings — 更新品牌自动提现设置
    // -------------------------------------------------------
    if (req.method === "PATCH" && pathSegments[0] === "withdrawal" && pathSegments[1] === "settings") {
      if (auth.role !== "brand_owner" && auth.role !== "brand_admin") {
        return errorResponse("Only brand owner/admin can manage withdrawal settings", 403);
      }

      const body = await req.json();
      const settingsData: Record<string, unknown> = {
        brand_id: auth.brandId,
        updated_at: new Date().toISOString(),
      };

      if (body.auto_withdrawal_enabled !== undefined) {
        settingsData.auto_withdrawal_enabled = Boolean(body.auto_withdrawal_enabled);
      }
      if (body.auto_withdrawal_frequency !== undefined) {
        const validFreqs = ["daily", "weekly", "biweekly", "monthly"];
        if (!validFreqs.includes(body.auto_withdrawal_frequency as string)) {
          return errorResponse(`Invalid frequency. Must be one of: ${validFreqs.join(", ")}`);
        }
        settingsData.auto_withdrawal_frequency = body.auto_withdrawal_frequency;
      }
      if (body.auto_withdrawal_day !== undefined) {
        settingsData.auto_withdrawal_day = Number(body.auto_withdrawal_day);
      }
      if (body.min_withdrawal_amount !== undefined) {
        const minAmount = Number(body.min_withdrawal_amount);
        if (minAmount < 10) {
          return errorResponse("Minimum withdrawal amount cannot be less than $10.00");
        }
        settingsData.min_withdrawal_amount = minAmount;
      }

      const { data, error } = await supabaseAdmin
        .from("brand_withdrawal_settings")
        .upsert(settingsData, { onConflict: "brand_id" })
        .select()
        .single();

      if (error) {
        return errorResponse(`Failed to update settings: ${error.message}`, 500);
      }

      return jsonResponse({ settings: data });
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
