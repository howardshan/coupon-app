// ============================================================
// admin-merchant-onboard — 平台管理员代商家提交入驻申请（至 pending）
// Authorization: 管理员 JWT；数据归属 target 用户（与 merchant-register 语义对齐）
//
// action:
//   - submit_application（默认）：创建/关联账号并写入申请（可带 documents）
//   - create_account_only：仅创建 Auth 用户（create_user），便于先拿到 user_id 再上传 Storage
// ============================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  AdminResolveError,
  resolvePlatformAdmin,
  type PlatformAdminContext,
} from "../_shared/admin_resolve.ts";
import {
  submitMerchantApplication,
  validateMerchantRegisterRequest,
  type MerchantRegisterRequestBody,
} from "../_shared/merchant_application_submit.ts";

interface TargetPayload {
  mode: "create_user" | "link_existing";
  email: string;
  user_id?: string;
  initial_password?: string;
}

interface AuditPayload {
  consent_reference?: string;
  note?: string;
}

type OnboardAction = "submit_application" | "create_account_only";

interface AdminOnboardRequestBody {
  action?: OnboardAction;
  target: TargetPayload;
  application?: MerchantRegisterRequestBody;
  audit?: AuditPayload;
}

function jsonResponse(data: unknown, status: number): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
    },
  });
}

function randomInitialPassword(): string {
  const bytes = new Uint8Array(20);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}

function normalizeEmail(s: string): string {
  return s.trim().toLowerCase();
}

async function resolveOwnerForOnboard(
  adminSupabase: ReturnType<typeof createClient>,
  target: TargetPayload,
): Promise<
  | { ok: true; ownerUserId: string; ownerAuthEmail: string | null; generatedPassword?: string }
  | { ok: false; status: number; error: string; code: string }
> {
  const targetEmailNorm = normalizeEmail(target.email);
  let generatedPassword: string | undefined;

  if (target.mode === "create_user") {
    const provided = target.initial_password?.trim() ?? "";
    const pwd = provided.length >= 8 ? provided : randomInitialPassword();
    if (provided.length < 8) {
      generatedPassword = pwd;
    }

    const { data: created, error: createError } = await adminSupabase.auth.admin.createUser({
      email: target.email.trim(),
      password: pwd,
      email_confirm: true,
    });

    if (createError) {
      const errMsg = (createError.message ?? "").toLowerCase();
      if (
        errMsg.includes("already") ||
        errMsg.includes("email_exists") ||
        (createError as { status?: number }).status === 422
      ) {
        return {
          ok: false,
          status: 409,
          error: "An account with this email already exists. Use target.mode link_existing.",
          code: "EMAIL_EXISTS",
        };
      }
      console.error("[admin-merchant-onboard] createUser:", createError);
      return {
        ok: false,
        status: 500,
        error: createError.message ?? "Failed to create user",
        code: "AUTH_CREATE_FAILED",
      };
    }

    return {
      ok: true,
      ownerUserId: created.user!.id,
      ownerAuthEmail: created.user!.email ?? target.email.trim(),
      generatedPassword,
    };
  }

  if (target.user_id?.trim()) {
    const { data: authData, error: getErr } = await adminSupabase.auth.admin.getUserById(
      target.user_id.trim(),
    );
    if (getErr || !authData?.user) {
      return { ok: false, status: 404, error: "User not found", code: "USER_NOT_FOUND" };
    }
    const authEmail = authData.user.email
      ? normalizeEmail(authData.user.email)
      : "";
    if (!authEmail || authEmail !== targetEmailNorm) {
      return {
        ok: false,
        status: 400,
        error: "target.user_id does not match target.email",
        code: "EMAIL_MISMATCH",
      };
    }
    return {
      ok: true,
      ownerUserId: authData.user.id,
      ownerAuthEmail: authData.user.email ?? null,
    };
  }

  const { data: row, error: qErr } = await adminSupabase
    .from("users")
    .select("id, email")
    .ilike("email", target.email.trim())
    .maybeSingle();

  if (qErr || !row?.id) {
    return {
      ok: false,
      status: 404,
      error: "No user found for this email. Use create_user or verify the email.",
      code: "USER_NOT_FOUND",
    };
  }
  return {
    ok: true,
    ownerUserId: row.id,
    ownerAuthEmail: row.email ?? target.email.trim(),
  };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Access-Control-Allow-Headers": "Authorization, Content-Type",
      },
    });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed", code: "METHOD_NOT_ALLOWED" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const adminSupabase = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  let adminCtx: PlatformAdminContext;
  try {
    adminCtx = await resolvePlatformAdmin(req, { supabaseUrl, anonKey, serviceKey });
  } catch (e) {
    if (e instanceof AdminResolveError) {
      return jsonResponse({ error: e.message, code: "ADMIN_REQUIRED" }, e.status);
    }
    throw e;
  }

  let body: AdminOnboardRequestBody;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "Invalid JSON body", code: "INVALID_JSON" }, 400);
  }

  const action: OnboardAction = body.action ?? "submit_application";

  if (!body?.target?.email?.trim()) {
    return jsonResponse({ error: "target.email is required", code: "VALIDATION_ERROR" }, 400);
  }

  if (action === "create_account_only") {
    if (body.target.mode !== "create_user") {
      return jsonResponse({
        error: "create_account_only requires target.mode create_user",
        code: "VALIDATION_ERROR",
      }, 400);
    }
    const owner = await resolveOwnerForOnboard(adminSupabase, body.target);
    if (!owner.ok) {
      return jsonResponse({ error: owner.error, code: owner.code }, owner.status);
    }
    const out: Record<string, unknown> = {
      target_user_id: owner.ownerUserId,
      email: body.target.email.trim(),
      message: "Account created. Upload documents to Storage, then call submit_application with link_existing.",
    };
    if (owner.generatedPassword) {
      out.generated_password = owner.generatedPassword;
      out.password_auto_generated = true;
    }
    return jsonResponse(out, 200);
  }

  if (!body.application) {
    return jsonResponse({ error: "application is required", code: "VALIDATION_ERROR" }, 400);
  }

  const targetEmailNorm = normalizeEmail(body.target.email);
  const contactNorm = normalizeEmail(body.application.contact_email ?? "");
  if (contactNorm !== targetEmailNorm) {
    return jsonResponse({
      error: "application.contact_email must match target.email",
      code: "EMAIL_MISMATCH",
    }, 400);
  }

  const val = validateMerchantRegisterRequest(body.application);
  if (val) {
    return jsonResponse({ error: val, code: "VALIDATION_ERROR" }, 400);
  }

  const owner = await resolveOwnerForOnboard(adminSupabase, body.target);
  if (!owner.ok) {
    return jsonResponse({ error: owner.error, code: owner.code }, owner.status);
  }

  const { ownerUserId, ownerAuthEmail, generatedPassword } = owner;

  const audit = body.audit ?? {};
  const detailPayload: Record<string, unknown> = {
    source: "admin_merchant_onboard",
    onboarded_user_id: ownerUserId,
    admin_user_id: adminCtx.userId,
  };
  if (audit.consent_reference?.trim()) {
    detailPayload.consent_reference = audit.consent_reference.trim();
  }
  if (audit.note?.trim()) {
    detailPayload.note = audit.note.trim();
  }
  const detailJson = JSON.stringify(detailPayload);

  const result = await submitMerchantApplication(adminSupabase, {
    ownerUserId,
    ownerAuthEmail,
    body: body.application,
    activity: {
      actorType: "admin",
      actorUserId: adminCtx.userId,
      detail: detailJson,
    },
  });

  if (!("merchant_id" in result)) {
    return jsonResponse({ error: result.error, code: "SUBMIT_FAILED" }, result.status);
  }

  const response: Record<string, unknown> = {
    merchant_id: result.merchant_id,
    status: result.status,
    message: result.message,
    registration_type: result.registration_type,
    brand_id: result.brand_id ?? null,
    target_user_id: ownerUserId,
    is_resubmission: result.is_resubmission,
  };
  if (generatedPassword) {
    response.generated_password = generatedPassword;
    response.password_auto_generated = true;
  }

  return jsonResponse(response, 200);
});
