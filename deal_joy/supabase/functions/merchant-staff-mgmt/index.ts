// =============================================================
// Crunchy Plum Edge Function: merchant-staff-mgmt
// 门店员工管理：列表、邀请、修改角色、移除、接受邀请
// 注意：函数名用 merchant-staff-mgmt 避免和表名 merchant_staff 冲突
// =============================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { resolveAuth, requirePermission } from "../_shared/auth.ts";
import { sendEmail } from "../_shared/email.ts";
import { buildM22Email } from "../_shared/email-templates/merchant/staff-invitation.ts";

const MERCHANT_APP_URL = "https://merchant.crunchyplum.com";

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

  const url = new URL(req.url);
  const pathSegments = url.pathname
    .replace(/\/merchant-staff-mgmt\/?/, "")
    .split("/")
    .filter(Boolean);

  // -------------------------------------------------------
  // GET /merchant-staff-mgmt/preview-invitation/:id — 公开接口
  // 返回邀请基本信息（门店名、角色、脱敏邮箱），无需登录
  // -------------------------------------------------------
  if (req.method === "GET" && pathSegments[0] === "preview-invitation" && pathSegments[1]) {
    const invitationId = pathSegments[1];
    const { data: inv } = await supabaseAdmin
      .from("staff_invitations")
      .select("id, invited_email, role, status, expires_at, merchant_id")
      .eq("id", invitationId)
      .maybeSingle();

    if (!inv) return errorResponse("Invitation not found", 404);
    if (inv.status !== "pending") return errorResponse("Invitation is no longer valid", 410);
    if (new Date(inv.expires_at) < new Date()) return errorResponse("Invitation has expired", 410);

    const { data: merchant } = await supabaseAdmin
      .from("merchants")
      .select("name")
      .eq("id", inv.merchant_id)
      .single();

    // 脱敏邮箱：j***@gmail.com
    const email = inv.invited_email as string;
    const atIdx = email.indexOf("@");
    const maskedEmail = atIdx > 1
      ? email[0] + "***" + email.slice(atIdx)
      : "***" + email.slice(atIdx);

    return jsonResponse({
      invitation_id: inv.id,
      store_name: merchant?.name ?? "the store",
      role: inv.role,
      invited_email_masked: maskedEmail,
      expires_at: inv.expires_at,
    });
  }

  // -------------------------------------------------------
  // POST /merchant-staff-mgmt/accept — 员工接受邀请
  // 支持两种模式：
  //   新账号：body 含 email + password，服务端创建用户（自动确认邮箱）并登录
  //   已有账号：需要 Authorization header
  // -------------------------------------------------------
  if (req.method === "POST" && pathSegments[0] === "accept") {
    const body = await req.json();
    const { invitation_id, email: newEmail, password: newPassword } = body;

    if (!invitation_id) return errorResponse("invitation_id is required");

    let userId: string;
    let userEmail: string;
    let sessionTokens: { access_token: string; refresh_token: string } | null = null;

    const authHeaderAccept = req.headers.get("Authorization");

    // Flutter 客户端始终携带 Authorization 头（未登录时是 anon key，不代表有真实用户）
    // 先尝试 getUser()，成功才走"已登录"分支，否则走"新账号"分支
    let resolvedUser: { id: string; email: string } | null = null;
    if (authHeaderAccept) {
      const supabaseUserCheck = createClient(
        Deno.env.get("SUPABASE_URL") ?? "",
        Deno.env.get("SUPABASE_ANON_KEY") ?? "",
        {
          global: { headers: { Authorization: authHeaderAccept } },
          auth: { persistSession: false },
        }
      );
      const { data: { user: maybeUser } } = await supabaseUserCheck.auth.getUser();
      if (maybeUser?.email) {
        resolvedUser = { id: maybeUser.id, email: maybeUser.email };
      }
    }

    if (resolvedUser) {
      // 已有账号且已登录
      userId    = resolvedUser.id;
      userEmail = resolvedUser.email;
    } else if (newEmail && newPassword) {
      // 新账号：用 admin API 创建用户（自动确认邮箱），再登录获取 session
      const { data: created, error: createError } =
        await supabaseAdmin.auth.admin.createUser({
          email: newEmail,
          password: newPassword,
          email_confirm: true,
        });

      if (createError) {
        const errMsg = (createError.message ?? "").toLowerCase();
        if (
          errMsg.includes("already") ||
          errMsg.includes("email_exists") ||
          (createError as { status?: number }).status === 422
        ) {
          // 用户已存在：用 admin API 确认邮箱，确保能直接登录（不被要求 verify）
          const { data: userList } = await supabaseAdmin.auth.admin.listUsers();
          const existingAuthUser = userList?.users?.find(
            (u: { email?: string }) => u.email?.toLowerCase() === newEmail.toLowerCase()
          );
          if (existingAuthUser) {
            await supabaseAdmin.auth.admin.updateUserById(existingAuthUser.id, {
              email_confirm: true,
            });
          }
          return jsonResponse(
            { code: "user_already_exists", message: "An account with this email already exists. Please use Sign In." },
            409
          );
        }
        return errorResponse(`Failed to create account: ${createError.message}`);
      }

      userId    = created.user.id;
      userEmail = created.user.email ?? newEmail;

      // 用 anon client 登录以获取 session token
      const anonClient = createClient(
        Deno.env.get("SUPABASE_URL") ?? "",
        Deno.env.get("SUPABASE_ANON_KEY") ?? "",
        { auth: { persistSession: false } }
      );
      const { data: signInData, error: signInErr } =
        await anonClient.auth.signInWithPassword({ email: newEmail, password: newPassword });
      if (!signInErr && signInData.session) {
        sessionTokens = {
          access_token:  signInData.session.access_token,
          refresh_token: signInData.session.refresh_token,
        };
      }
    } else {
      return errorResponse("Missing authorization or email/password", 401);
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

    if (new Date(invitation.expires_at) < new Date()) {
      await supabaseAdmin
        .from("staff_invitations")
        .update({ status: "expired" })
        .eq("id", invitation_id);
      return errorResponse("Invitation has expired", 410);
    }

    if (invitation.invited_email !== userEmail) {
      return errorResponse("This invitation is for a different email address", 403);
    }

    // 创建员工记录
    const { data: staffRecord, error: staffError } = await supabaseAdmin
      .from("merchant_staff")
      .insert({
        merchant_id: invitation.merchant_id,
        user_id: userId,
        role: invitation.role,
        invited_by: invitation.invited_by,
        is_active: true,
      })
      .select()
      .single();

    if (staffError) {
      if (staffError.code === "23505") {
        return errorResponse("You are already a staff member of this store");
      }
      return errorResponse(`Failed to create staff record: ${staffError.message}`);
    }

    await supabaseAdmin
      .from("staff_invitations")
      .update({ status: "accepted" })
      .eq("id", invitation_id);

    // 响应包含 session（新账号模式下客户端用它登录）
    return jsonResponse({ staff: staffRecord, session: sessionTokens }, 201);
  }

  // 其余所有路由需要登录
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

  try {
    // 其他路由需要鉴权
    const auth = await resolveAuth(supabaseAdmin, user.id, req.headers);

    // -------------------------------------------------------
    // POST /merchant-staff-mgmt/leave — 员工主动离开门店
    // 将当前用户在 merchant_staff 中的记录设为 is_active = false
    // -------------------------------------------------------
    if (req.method === "POST" && pathSegments[0] === "leave") {
      const { error } = await supabaseAdmin
        .from("merchant_staff")
        .update({ is_active: false })
        .eq("user_id", user.id)
        .eq("is_active", true);

      if (error) return errorResponse(`Failed to leave store: ${error.message}`);
      return jsonResponse({ success: true });
    }

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

      const validRoles = ["regional_manager", "manager", "finance", "cashier", "service", "trainee"];
      if (!validRoles.includes(staffRole)) {
        return errorResponse(
          `Invalid role. Must be one of: ${validRoles.join(", ")}`
        );
      }

      // manager 不能邀请 manager 或更高角色（只有 store_owner 和品牌管理员可以）
      if (
        (staffRole === "manager" || staffRole === "regional_manager") &&
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
          .select("id, is_active")
          .eq("merchant_id", auth.merchantId)
          .eq("user_id", existingByEmail.id)
          .maybeSingle();

        // 只阻止已有活跃员工记录；禁用的员工可以重新邀请
        if (existingStaff && existingStaff.is_active) {
          return errorResponse("This user is already an active staff member");
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

      // 发送邀请邮件（即发即忘，不阻塞响应）
      (async () => {
        try {
          // 查商家名称和邀请者邮箱
          const [{ data: merchant }, { data: inviter }] = await Promise.all([
            supabaseAdmin.from("merchants").select("name").eq("id", auth.merchantId).single(),
            supabaseAdmin.from("users").select("email, full_name").eq("id", user.id).single(),
          ]);

          const storeName  = merchant?.name ?? "the store";
          const inviterName = inviter?.full_name || inviter?.email || "The store owner";
          const acceptUrl  = `${MERCHANT_APP_URL}/staff/accept?invitation_id=${invitation.id}`;

          const { subject, html } = buildM22Email({
            invitedEmail: email,
            storeName,
            role: staffRole,
            inviterName,
            invitationId: invitation.id,
            expiresAt: invitation.expires_at,
            acceptUrl,
          });

          await sendEmail(supabaseAdmin, {
            to: email,
            subject,
            htmlBody: html,
            emailCode: "M22",
            referenceId: invitation.id,
            recipientType: "merchant",
          });
        } catch (emailErr) {
          console.error("[staff-invite] Failed to send invitation email:", emailErr);
        }
      })();

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
        const validRoles = ["regional_manager", "manager", "finance", "cashier", "service", "trainee"];
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
