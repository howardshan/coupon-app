import { createClient } from "https://esm.sh/@supabase/supabase-js@2?target=deno";
import {
  AFTER_SALES_BUCKET,
  TimelineEntry,
  appendTimeline,
  decorateAfterSalesRequest,
  decorateAfterSalesRequests,
  normalizeAttachmentKeys,
  recordAfterSalesEvent,
} from "../_shared/after-sales.ts";
import { issueAfterSalesRefund } from "../_shared/after-sales-refund.ts";
import { sendEmail, getAdminRecipients } from "../_shared/email.ts";
import { buildC10Email } from "../_shared/email-templates/customer/after-sales-approved.ts";
import { buildC11Email } from "../_shared/email-templates/customer/after-sales-rejected.ts";
import { buildM12Email } from "../_shared/email-templates/merchant/platform-review-result.ts";
import { buildA6Email } from "../_shared/email-templates/admin/after-sales-closed.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function errorResponse(message: string, code = "bad_request", status = 400): Response {
  return jsonResponse({ error: code, message }, status);
}

type AdminContext = { userId: string; role: string };

/** 与 config.toml 目录名一致；线上 pathname 为 /functions/v1/platform-after-sales/... */
const FUNCTION_SLUG = "platform-after-sales";

/**
 * 从 URL pathname 解析函数名之后的子路径段（与 after-sales-request / merchant-after-sales 一致）
 */
function routePartsFromPathname(pathname: string): string[] {
  const p = pathname.replace(/\/+$/, "");
  const marker = `/${FUNCTION_SLUG}`;
  const i = p.indexOf(marker);
  const after =
    i >= 0 ? p.slice(i + marker.length) : p.replace(new RegExp(`^${marker}`), "");
  return after.split("/").filter(Boolean);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (!["GET", "POST"].includes(req.method)) {
    return errorResponse("Method not allowed", "method_not_allowed", 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  if (!supabaseUrl || !serviceKey || !anonKey) {
    return errorResponse("Supabase env vars missing", "config_error", 500);
  }

  const url = new URL(req.url);
  const segments = routePartsFromPathname(url.pathname);

  let body: Record<string, unknown> | null = null;
  if (req.method === "POST") {
    body = await req.json().catch(() => ({}));
  }

  let admin: AdminContext;
  try {
    admin = await resolveAdmin(req, anonKey, serviceKey, body);
  } catch (err) {
    return errorResponse((err as Error).message, "unauthorized", 401);
  }

  const serviceClient = createClient(supabaseUrl, serviceKey);

  if (segments[0] === "uploads" && req.method === "POST") {
    return await handleUploadSlots(serviceClient, admin, body ?? {});
  }

  if (req.method === "GET" || (req.method === "POST" && segments.length === 0)) {
    if (segments.length === 1 && segments[0]) {
      return await handleDetail(serviceClient, segments[0]);
    }
    return await handleList(serviceClient, url.searchParams, body ?? {});
  }

  if (segments.length === 2 && req.method === "POST") {
    const requestId = segments[0];
    const action = segments[1];
    if (action === "approve") {
      return await handleApprove(serviceClient, admin, requestId, body ?? {});
    }
    if (action === "reject") {
      return await handleReject(serviceClient, admin, requestId, body ?? {});
    }
  }

  return errorResponse("Route not found", "not_found", 404);
});

async function resolveAdmin(
  req: Request,
  anonKey: string,
  serviceKey: string,
  body: Record<string, unknown> | null
): Promise<AdminContext> {
  const url = new URL(req.url);
  const headerToken = (req.headers.get("Authorization") ?? "").replace(/^[Bb]earer\s+/i, "").trim();
  const queryToken = url.searchParams.get("access_token")?.trim() ?? "";
  const bodyToken =
    body && typeof body.access_token === "string" ? body.access_token.trim() : "";
  const token = bodyToken || queryToken || headerToken;
  if (!token) {
    throw new Error("Missing authorization");
  }

  const anonClient = createClient(Deno.env.get("SUPABASE_URL") ?? "", anonKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false },
  });
  const { data, error } = await anonClient.auth.getUser();
  if (error || !data?.user) {
    throw new Error("Invalid or expired token");
  }

  const serviceClient = createClient(Deno.env.get("SUPABASE_URL") ?? "", serviceKey);
  const { data: profile } = await serviceClient
    .from("users")
    .select("role")
    .eq("id", data.user.id)
    .maybeSingle();
  if (!profile || !["admin", "super_admin"].includes(profile.role ?? "")) {
    throw new Error("Admin access required");
  }

  return { userId: data.user.id, role: profile.role };
}

async function handleUploadSlots(
  supabase: ReturnType<typeof createClient>,
  admin: AdminContext,
  body: Record<string, unknown>
): Promise<Response> {
  const files = Array.isArray(body.files) ? body.files : [];
  if (!files.length) {
    return errorResponse("files array required", "invalid_payload", 400);
  }
  if (files.length > 3) {
    return errorResponse("Maximum 3 files per request", "too_many_files", 400);
  }
  const bucket = supabase.storage.from(AFTER_SALES_BUCKET);
  const uploads = [];
  for (const file of files) {
    const filename = typeof file?.filename === "string" ? file.filename : "evidence";
    const path = `platform/${admin.userId}/${Date.now()}-${crypto.randomUUID()}-${filename
      .toLowerCase()
      .replace(/[^a-z0-9._-]+/g, "-")}`;
    const { data, error } = await bucket.createSignedUploadUrl(path);
    if (error || !data) {
      return errorResponse("Failed to create upload url", "storage_error", 500);
    }
    uploads.push({ path, bucket: AFTER_SALES_BUCKET, signedUrl: data.signedUrl, token: data.token });
  }
  return jsonResponse({ uploads });
}

async function handleList(
  supabase: ReturnType<typeof createClient>,
  params: URLSearchParams,
  body: Record<string, unknown>
): Promise<Response> {
  const statusParam =
    (body?.status as string) || params.get("status") || "awaiting_platform,merchant_rejected";
  const statuses = Array.from(
    new Set(
      statusParam
        .split(",")
        .map((s) => s.trim())
        .filter(Boolean)
    )
  );
  const search = (body?.search as string) || params.get("search") || "";
  const page = Math.max(Number((body?.page as number) ?? params.get("page") ?? 1), 1);
  const perPage = Math.min(
    Math.max(Number((body?.perPage as number) ?? params.get("per_page") ?? 20), 1),
    100,
  );
  const offset = (page - 1) * perPage;

  let query = supabase
    .from("after_sales_requests")
    .select(
      "id, status, reason_code, reason_detail, refund_amount, merchant_feedback, platform_feedback, created_at, escalated_at, user_id, merchant_id, orders(order_number, total_amount), after_sales_events(*)",
      { count: "exact" }
    )
    .order("created_at", { ascending: false })
    .range(offset, offset + perPage - 1);

  if (statuses.length) {
    query = query.in("status", statuses);
  }
  if (search) {
    query = query.ilike("reason_detail", `%${search}%`);
  }

  const { data, error, count } = await query;
  if (error) {
    console.error("[platform-after-sales] list error", error.message);
    return errorResponse("Failed to load requests", "db_error", 500);
  }

  const hydrated = await decorateAfterSalesRequests(supabase, data ?? []);
  return jsonResponse({ data: hydrated, total: count ?? 0, page, per_page: perPage });
}

async function handleDetail(
  supabase: ReturnType<typeof createClient>,
  requestId: string
): Promise<Response> {
  // 不嵌套 users(*)：user_id 指向 auth.users，PostgREST 易失败；与 merchant-after-sales 一致
  const { data, error } = await supabase
    .from("after_sales_requests")
    .select("*, orders(*), coupons(used_at), after_sales_events(*)")
    .eq("id", requestId)
    .single();
  if (error) {
    console.error("[platform-after-sales] detail query", error.message);
    return errorResponse("Request not found", "not_found", 404);
  }
  if (!data) {
    return errorResponse("Request not found", "not_found", 404);
  }
  const hydrated = await decorateAfterSalesRequest(supabase, data);
  return jsonResponse({ request: hydrated });
}

async function handleApprove(
  supabase: ReturnType<typeof createClient>,
  admin: AdminContext,
  requestId: string,
  body: Record<string, unknown>
): Promise<Response> {
  const note = typeof body.note === "string" ? body.note.trim() : "";
  const attachments = normalizeAttachmentKeys(body.attachments ?? []);
  if (note.length < 10) {
    return errorResponse("Approval note must be at least 10 characters", "invalid_note", 400);
  }

  const request = await fetchRequest(supabase, requestId);
  if (!request) {
    return errorResponse("Request not found", "not_found", 404);
  }
  if (request.status !== "awaiting_platform") {
    return errorResponse(
      `Request status is ${request.status}, expected awaiting_platform`,
      "invalid_status",
      400,
    );
  }

  const nowIso = new Date().toISOString();
  const decisionTimeline = appendTimeline(request.timeline, {
    status: "platform_approved",
    actor: "platform",
    note,
    attachments,
    at: nowIso,
  } as TimelineEntry);

  const { data: updated, error: updateError } = await supabase
    .from("after_sales_requests")
    .update({
      status: "platform_approved",
      platform_feedback: note,
      platform_attachments: attachments,
      platform_decided_at: nowIso,
      timeline: decisionTimeline,
      metadata: {
        ...(request.metadata ?? {}),
        platform_actor: admin.userId,
      },
    })
    .eq("id", requestId)
    .select("id, order_id, coupon_id, refund_amount, timeline, metadata")
    .single();

  if (updateError || !updated) {
    console.error("[platform-after-sales] approve update error", updateError?.message);
    return errorResponse("Failed to update request", "update_failed", 500);
  }

  await recordAfterSalesEvent({
    supabase,
    requestId,
    actorRole: "platform",
    actorId: admin.userId,
    action: "platform_approved",
    note,
    attachments,
  });

  try {
    const refundResult = await issueAfterSalesRefund({ supabase, request: updated });
    const finalTimeline = appendTimeline(updated.timeline, {
      status: "refunded",
      actor: "system",
      note: `Refunded (${refundResult.status})`,
      at: refundResult.completedAt,
      meta: { stripe_refund_id: refundResult.refundId },
    });

    const { data: finalized } = await supabase
      .from("after_sales_requests")
      .update({
        status: "refunded",
        refunded_at: refundResult.completedAt,
        timeline: finalTimeline,
        metadata: {
          ...(updated.metadata ?? {}),
          refund: {
            id: refundResult.refundId,
            status: refundResult.status,
            actor: admin.userId,
          },
        },
      })
      .eq("id", requestId)
      .select("id")
      .single();

    await recordAfterSalesEvent({
      supabase,
      requestId,
      actorRole: "system",
      actorId: admin.userId,
      action: "refund_succeeded",
      note: `Refunded (${refundResult.status})`,
      extra: { refund_id: refundResult.refundId },
    });
    // C10 + M12 + A6：平台批准后通知客户、商家和管理员（fire-and-forget）
    (async () => {
      try {
        const { data: reqInfo } = await supabase
          .from("after_sales_requests")
          .select("user_id, merchant_id, refund_amount, coupons(deal_id, deals(title))")
          .eq("id", requestId)
          .single();
        const dealTitle = (reqInfo as any)?.coupons?.deals?.title as string | undefined;
        const requestIdShort = requestId.slice(0, 8).toUpperCase();
        const refundAmount = Number(reqInfo?.refund_amount ?? updated.refund_amount ?? 0);
        const { data: adminUser } = await supabase
          .from("users").select("full_name").eq("id", admin.userId).single();
        const adminReviewerName = adminUser?.full_name as string | undefined;

        // C10：通知客户平台已批准退款
        if (reqInfo?.user_id) {
          const { data: customerUser } = await supabase
            .from("users").select("email").eq("id", reqInfo.user_id).single();
          if (customerUser?.email) {
            const { subject: c10Subject, html: c10Html } = buildC10Email({
              requestId: requestIdShort, refundAmount,
              refundMethod: "original_payment", dealTitle,
            });
            await sendEmail(supabase, {
              to: customerUser.email, subject: c10Subject, htmlBody: c10Html,
              emailCode: "C10", referenceId: requestId, recipientType: "customer",
              userId: reqInfo.user_id,
            });
          }
        }

        // M12：通知商家平台最终裁决（已批准）
        if (reqInfo?.merchant_id) {
          const { data: merchantInfo } = await supabase
            .from("merchants").select("name, user_id").eq("id", reqInfo.merchant_id).single();
          if (merchantInfo) {
            const { data: merchantUser } = await supabase
              .from("users").select("email").eq("id", merchantInfo.user_id).single();
            if (merchantUser?.email) {
              const { subject: m12Subject, html: m12Html } = buildM12Email({
                merchantName: merchantInfo.name, requestId: requestIdShort,
                decision: "approved", platformNote: note, refundAmount,
              });
              await sendEmail(supabase, {
                to: merchantUser.email, subject: m12Subject, htmlBody: m12Html,
                emailCode: "M12", referenceId: requestId, recipientType: "merchant",
                merchantId: reqInfo.merchant_id,
              });
            }
          }
        }

        // A6：管理员结案存档通知（已批准）
        const adminEmails = await getAdminRecipients(supabase, "A6");
        if (adminEmails.length > 0) {
          const { subject: a6Subject, html: a6Html } = buildA6Email({
            requestId: requestIdShort, decision: "approved",
            platformNote: note, adminReviewerName, refundAmount, dealTitle,
          });
          await sendEmail(supabase, {
            to: adminEmails, subject: a6Subject, htmlBody: a6Html,
            emailCode: "A6", referenceId: requestId, recipientType: "admin",
          });
        }
      } catch (err) {
        console.warn("[platform-after-sales] approve email failed", err);
      }
    })();

    const refreshed = await fetchAdminRequest(supabase, requestId);
    const hydrated = await decorateAfterSalesRequest(supabase, refreshed);
    const fallback = await decorateAfterSalesRequest(supabase, updated);
    return jsonResponse({ request: hydrated ?? fallback, refund: refundResult });
  } catch (err) {
    console.error("[platform-after-sales] refund error", err);
    const failTimeline = appendTimeline(updated.timeline, {
      status: "platform_approved",
      actor: "system",
      note: `Refund failed: ${(err as Error).message}`,
      at: new Date().toISOString(),
    });
    await supabase
      .from("after_sales_requests")
      .update({
        timeline: failTimeline,
        metadata: {
          ...(updated.metadata ?? {}),
          refund_error: (err as Error).message,
        },
      })
      .eq("id", requestId);
    await recordAfterSalesEvent({
      supabase,
      requestId,
      actorRole: "system",
      actorId: admin.userId,
      action: "refund_failed",
      note: (err as Error).message,
    });
    return errorResponse((err as Error).message, "stripe_error", 502);
  }
}

async function handleReject(
  supabase: ReturnType<typeof createClient>,
  admin: AdminContext,
  requestId: string,
  body: Record<string, unknown>
): Promise<Response> {
  const note = typeof body.note === "string" ? body.note.trim() : "";
  const attachments = normalizeAttachmentKeys(body.attachments ?? []);
  if (note.length < 10) {
    return errorResponse("Rejection reason must be at least 10 characters", "invalid_note", 400);
  }

  const request = await fetchRequest(supabase, requestId);
  if (!request) {
    return errorResponse("Request not found", "not_found", 404);
  }
  if (request.status !== "awaiting_platform") {
    return errorResponse(
      `Request status is ${request.status}, expected awaiting_platform`,
      "invalid_status",
      400,
    );
  }

  const nowIso = new Date().toISOString();
  const timeline = appendTimeline(request.timeline, {
    status: "platform_rejected",
    actor: "platform",
    note,
    attachments,
    at: nowIso,
  });

  const { data, error } = await supabase
    .from("after_sales_requests")
    .update({
      status: "platform_rejected",
      platform_feedback: note,
      platform_attachments: attachments,
      platform_decided_at: nowIso,
      closed_at: nowIso,
      timeline,
      metadata: {
        ...(request.metadata ?? {}),
        platform_actor: admin.userId,
      },
    })
    .eq("id", requestId)
    .select("id, status, timeline, closed_at")
    .single();

  if (error || !data) {
    return errorResponse("Failed to reject request", "update_failed", 500);
  }
  await recordAfterSalesEvent({
    supabase,
    requestId,
    actorRole: "platform",
    actorId: admin.userId,
    action: "platform_rejected",
    note,
    attachments,
  });
  // C11 + M12 + A6：平台拒绝后通知客户、商家和管理员（fire-and-forget）
  (async () => {
    try {
      const { data: reqInfo } = await supabase
        .from("after_sales_requests")
        .select("user_id, merchant_id, coupons(deal_id, deals(title))")
        .eq("id", requestId)
        .single();
      const dealTitle = (reqInfo as any)?.coupons?.deals?.title as string | undefined;
      const requestIdShort = requestId.slice(0, 8).toUpperCase();
      const { data: adminUser } = await supabase
        .from("users").select("full_name").eq("id", admin.userId).single();
      const adminReviewerName = adminUser?.full_name as string | undefined;

      // C11：通知客户平台已拒绝
      if (reqInfo?.user_id) {
        const { data: customerUser } = await supabase
          .from("users").select("email").eq("id", reqInfo.user_id).single();
        if (customerUser?.email) {
          const { subject: c11Subject, html: c11Html } = buildC11Email({
            requestId: requestIdShort, rejectionNote: note, dealTitle,
          });
          await sendEmail(supabase, {
            to: customerUser.email, subject: c11Subject, htmlBody: c11Html,
            emailCode: "C11", referenceId: requestId, recipientType: "customer",
            userId: reqInfo.user_id,
          });
        }
      }

      // M12：通知商家平台最终裁决（已拒绝）
      if (reqInfo?.merchant_id) {
        const { data: merchantInfo } = await supabase
          .from("merchants").select("name, user_id").eq("id", reqInfo.merchant_id).single();
        if (merchantInfo) {
          const { data: merchantUser } = await supabase
            .from("users").select("email").eq("id", merchantInfo.user_id).single();
          if (merchantUser?.email) {
            const { subject: m12Subject, html: m12Html } = buildM12Email({
              merchantName: merchantInfo.name, requestId: requestIdShort,
              decision: "rejected", platformNote: note,
            });
            await sendEmail(supabase, {
              to: merchantUser.email, subject: m12Subject, htmlBody: m12Html,
              emailCode: "M12", referenceId: requestId, recipientType: "merchant",
              merchantId: reqInfo.merchant_id,
            });
          }
        }
      }

      // A6：管理员结案存档通知（已拒绝）
      const adminEmails = await getAdminRecipients(supabase, "A6");
      if (adminEmails.length > 0) {
        const { subject: a6Subject, html: a6Html } = buildA6Email({
          requestId: requestIdShort, decision: "rejected",
          platformNote: note, adminReviewerName, dealTitle,
        });
        await sendEmail(supabase, {
          to: adminEmails, subject: a6Subject, htmlBody: a6Html,
          emailCode: "A6", referenceId: requestId, recipientType: "admin",
        });
      }
    } catch (err) {
      console.warn("[platform-after-sales] reject email failed", err);
    }
  })();

  const refreshed = await fetchAdminRequest(supabase, requestId);
  const hydrated = await decorateAfterSalesRequest(supabase, refreshed);
  const fallback = await decorateAfterSalesRequest(supabase, data);
  return jsonResponse({ request: hydrated ?? fallback });
}

async function fetchRequest(
  supabase: ReturnType<typeof createClient>,
  requestId: string
) {
  const { data } = await supabase
    .from("after_sales_requests")
    .select("id, status, order_id, coupon_id, refund_amount, timeline, metadata")
    .eq("id", requestId)
    .maybeSingle();
  return data ?? null;
}

async function fetchAdminRequest(
  supabase: ReturnType<typeof createClient>,
  requestId: string
) {
  const { data } = await supabase
    .from("after_sales_requests")
    .select("*, after_sales_events(*)")
    .eq("id", requestId)
    .maybeSingle();
  return data ?? null;
}
