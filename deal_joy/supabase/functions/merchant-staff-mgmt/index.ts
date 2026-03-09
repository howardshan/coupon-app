// =============================================================
// DealJoy Edge Function: merchant-staff-mgmt
// 门店员工管理：列表、邀请、修改角色、移除、接受邀请
// 注意：函数名用 merchant-staff-mgmt 避免和表名 merchant_staff 冲突
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

  const url = new URL(req.url);
  const pathSegments = url.pathname
    .replace(/\/merchant-staff-mgmt\/?/, "")
    .split("/")
    .filter(Boolean);

  try {
    // -------------------------------------------------------
    // POST /merchant-staff-mgmt/accept — 员工接受邀请
    // 无需 resolveAuth（用户可能还没有 merchant 关联）
    // -------------------------------------------------------
    if (req.method === "POST" && pathSegments[0] === "accept") {
      const body = await req.json();
      const { invitation_id } = body;

      if (!invitation_id) {
        return errorResponse("invitation_id is required");
      }

      // 查找邀请记录
      const { data: invitation, error: invError } = await supabaseAdmin
        .from("staff_invitations")
        .select("*")
        .eq("id", invitation_id)
        .eq("status", "pending")
        .single();

      if (invError || !invitation) {
        return errorResponse("Invitation not found or already used", 404);
      }

      // 检查是否过期
      if (new Date(invitation.expires_at) < new Date()) {
        await supabaseAdmin
          .from("staff_invitations")
          .update({ status: "expired" })
          .eq("id", invitation_id);
        return errorResponse("Invitation has expired", 410);
      }

      // 检查邮箱匹配
      if (invitation.invited_email !== user.email) {
        return errorResponse(
          "This invitation is for a different email address",
          403
        );
      }

      // 创建员工记录
      const { data: staffRecord, error: staffError } = await supabaseAdmin
        .from("merchant_staff")
        .insert({
          merchant_id: invitation.merchant_id,
          user_id: user.id,
          role: invitation.role,
          invited_by: invitation.invited_by,
          is_active: true,
        })
        .select()
        .single();

      if (staffError) {
        // 可能已存在（UNIQUE 约束）
        if (staffError.code === "23505") {
          return errorResponse("You are already a staff member of this store");
        }
        return errorResponse(
          `Failed to create staff record: ${staffError.message}`
        );
      }

      // 更新邀请状态
      await supabaseAdmin
        .from("staff_invitations")
        .update({ status: "accepted" })
        .eq("id", invitation_id);

      return jsonResponse({ staff: staffRecord }, 201);
    }

    // 其他路由需要鉴权
    const auth = await resolveAuth(supabaseAdmin, user.id, req.headers);

    // -------------------------------------------------------
    // GET /merchant-staff-mgmt — 当前门店员工列表
    // -------------------------------------------------------
    if (req.method === "GET" && pathSegments.length === 0) {
      requirePermission(auth, "staff");

      const { data: staffList, error } = await supabaseAdmin
        .from("merchant_staff")
        .select("id, user_id, role, nickname, is_active, created_at, updated_at")
        .eq("merchant_id", auth.merchantId)
        .order("created_at");

      if (error) {
        return errorResponse(`Failed to fetch staff: ${error.message}`);
      }

      // 获取员工的 email 信息（从 auth.users）
      const userIds = (staffList ?? []).map(
        (s: { user_id: string }) => s.user_id
      );
      let emailMap: Record<string, string> = {};
      if (userIds.length > 0) {
        const { data: users } = await supabaseAdmin
          .from("users")
          .select("id, email")
          .in("id", userIds);
        emailMap = (users ?? []).reduce(
          (acc: Record<string, string>, u: { id: string; email: string }) => {
            acc[u.id] = u.email;
            return acc;
          },
          {}
        );
      }

      const staffWithEmail = (staffList ?? []).map(
        (s: { user_id: string; [key: string]: unknown }) => ({
          ...s,
          email: emailMap[s.user_id] ?? "",
        })
      );

      // 获取待处理的邀请
      const { data: pendingInvitations } = await supabaseAdmin
        .from("staff_invitations")
        .select("id, invited_email, role, status, expires_at, created_at")
        .eq("merchant_id", auth.merchantId)
        .eq("status", "pending")
        .order("created_at", { ascending: false });

      return jsonResponse({
        staff: staffWithEmail,
        pending_invitations: pendingInvitations ?? [],
      });
    }

    // -------------------------------------------------------
    // POST /merchant-staff-mgmt/invite — 邀请员工
    // -------------------------------------------------------
    if (req.method === "POST" && pathSegments[0] === "invite") {
      requirePermission(auth, "staff");

      const body = await req.json();
      const { email, role: staffRole, nickname } = body;

      if (!email) {
        return errorResponse("Email is required");
      }

      const validRoles = ["manager", "cashier", "service"];
      if (!validRoles.includes(staffRole)) {
        return errorResponse(
          `Invalid role. Must be one of: ${validRoles.join(", ")}`
        );
      }

      // manager 不能邀请 manager（只有 store_owner 和品牌管理员可以）
      if (
        staffRole === "manager" &&
        auth.role === "manager"
      ) {
        return errorResponse(
          "Managers cannot invite other managers. Only store owner or brand admin can.",
          403
        );
      }

      // 检查是否已经是员工
      const { data: existingByEmail } = await supabaseAdmin
        .from("users")
        .select("id")
        .eq("email", email)
        .maybeSingle();

      if (existingByEmail) {
        const { data: existingStaff } = await supabaseAdmin
          .from("merchant_staff")
          .select("id")
          .eq("merchant_id", auth.merchantId)
          .eq("user_id", existingByEmail.id)
          .maybeSingle();

        if (existingStaff) {
          return errorResponse("This user is already a staff member");
        }
      }

      // 创建邀请
      const { data: invitation, error } = await supabaseAdmin
        .from("staff_invitations")
        .insert({
          merchant_id: auth.merchantId,
          invited_email: email,
          role: staffRole,
          invited_by: user.id,
        })
        .select()
        .single();

      if (error) {
        return errorResponse(`Failed to create invitation: ${error.message}`);
      }

      // TODO: 发送邀请邮件（V2）

      return jsonResponse({ invitation }, 201);
    }

    // -------------------------------------------------------
    // PATCH /merchant-staff-mgmt/:id — 修改员工角色/昵称
    // -------------------------------------------------------
    if (req.method === "PATCH" && pathSegments[0] && pathSegments[0] !== "invite" && pathSegments[0] !== "accept") {
      requirePermission(auth, "staff");

      const staffId = pathSegments[0];
      const body = await req.json();

      // 角色优先级：用于"只能修改比自己低的角色"校验
      const rolePriority: Record<string, number> = {
        brand_owner: 6, brand_admin: 5, store_owner: 4,
        manager: 3, service: 2, cashier: 1,
      };

      // 查询目标员工当前角色
      const { data: targetStaff } = await supabaseAdmin
        .from("merchant_staff")
        .select("user_id, role")
        .eq("id", staffId)
        .eq("merchant_id", auth.merchantId)
        .single();

      if (!targetStaff) {
        return errorResponse("Staff member not found", 404);
      }

      // 不能修改自己
      if (targetStaff.user_id === user.id) {
        return errorResponse("Cannot modify your own role");
      }

      // 不能修改比自己高或平级的角色
      const myPriority = rolePriority[auth.role] ?? 0;
      const targetPriority = rolePriority[targetStaff.role] ?? 0;
      if (targetPriority >= myPriority) {
        return errorResponse(
          "Cannot modify a staff member with equal or higher role",
          403
        );
      }

      const updateData: Record<string, unknown> = {};

      // 修改角色
      if (body.role !== undefined) {
        const validRoles = ["manager", "cashier", "service"];
        if (!validRoles.includes(body.role)) {
          return errorResponse(
            `Invalid role. Must be one of: ${validRoles.join(", ")}`
          );
        }

        // 不能把别人提升到和自己一样或更高的角色
        const newRolePriority = rolePriority[body.role] ?? 0;
        if (newRolePriority >= myPriority) {
          return errorResponse(
            "Cannot assign a role equal to or higher than your own",
            403
          );
        }

        updateData.role = body.role;
      }

      // 修改昵称
      if (body.nickname !== undefined) {
        updateData.nickname = body.nickname;
      }

      // 修改激活状态
      if (body.is_active !== undefined) {
        updateData.is_active = body.is_active;
      }

      if (Object.keys(updateData).length === 0) {
        return errorResponse("No valid fields to update");
      }

      updateData.updated_at = new Date().toISOString();

      const { data, error } = await supabaseAdmin
        .from("merchant_staff")
        .update(updateData)
        .eq("id", staffId)
        .eq("merchant_id", auth.merchantId) // 安全校验
        .select()
        .single();

      if (error) {
        return errorResponse(`Failed to update staff: ${error.message}`);
      }

      return jsonResponse({ staff: data });
    }

    // -------------------------------------------------------
    // DELETE /merchant-staff-mgmt/:id — 移除员工（软删除，is_active=false）
    // -------------------------------------------------------
    if (req.method === "DELETE" && pathSegments[0]) {
      requirePermission(auth, "staff");

      const staffId = pathSegments[0];

      // 角色优先级
      const rolePriority: Record<string, number> = {
        brand_owner: 6, brand_admin: 5, store_owner: 4,
        manager: 3, service: 2, cashier: 1,
      };

      // 查询目标员工
      const { data: targetStaff } = await supabaseAdmin
        .from("merchant_staff")
        .select("user_id, role")
        .eq("id", staffId)
        .eq("merchant_id", auth.merchantId)
        .single();

      if (!targetStaff) {
        return errorResponse("Staff member not found", 404);
      }

      // 不能移除自己
      if (targetStaff.user_id === user.id) {
        return errorResponse("Cannot remove yourself");
      }

      // 不能移除比自己高或平级的角色
      const myPriority = rolePriority[auth.role] ?? 0;
      const targetPriority = rolePriority[targetStaff.role] ?? 0;
      if (targetPriority >= myPriority) {
        return errorResponse(
          "Cannot remove a staff member with equal or higher role",
          403
        );
      }

      // 软删除：设为 is_active=false，保留记录
      const { error } = await supabaseAdmin
        .from("merchant_staff")
        .update({ is_active: false, updated_at: new Date().toISOString() })
        .eq("id", staffId)
        .eq("merchant_id", auth.merchantId);

      if (error) {
        return errorResponse(`Failed to remove staff: ${error.message}`);
      }

      return jsonResponse({ success: true });
    }

    return errorResponse("Not found", 404);
  } catch (e) {
    const msg = e instanceof Error ? e.message : "Internal server error";
    const status = msg.includes("Unauthorized") || msg.includes("Forbidden")
      ? 403
      : msg.includes("No merchant")
      ? 404
      : 500;
    return errorResponse(msg, status);
  }
});
