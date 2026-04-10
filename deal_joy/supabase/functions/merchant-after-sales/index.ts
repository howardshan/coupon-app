import { createClient } from "https://esm.sh/@supabase/supabase-js@2?target=deno";
import {
  AFTER_SALES_BUCKET,
  TimelineEntry,
  appendTimeline,
  decorateAfterSalesRequest,
  decorateAfterSalesRequests,
  issueAfterSalesRefund,
  normalizeAttachmentKeys,
  recordAfterSalesEvent,
} from "../_shared/after-sales.ts";
import { resolveAuth, requirePermission } from "../_shared/auth.ts";
import { sendEmail } from "../_shared/email.ts";
import { buildC13Email } from "../_shared/email-templates/customer/after-sales-merchant-replied.ts";
import { buildM10Email } from "../_shared/email-templates/merchant/after-sales-approved.ts";
import { buildM11Email } from "../_shared/email-templates/merchant/after-sales-rejected-escalated.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-merchant-id, x-app-bearer",
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

/** 与 supabase/config.toml 中函数目录名一致 */
const FUNCTION_SLUG = "merchant-after-sales";

/**
 * 从 URL pathname 解析函数名之后的子路径段。
 * 线上网关 pathname 为 /functions/v1/merchant-after-sales/...，本地或直连可能为 /merchant-after-sales/...
 */
function routePartsFromPathname(pathname: string): string[] {
  const p = pathname.replace(/\/+$/, "");
  const marker = `/${FUNCTION_SLUG}`;
  const i = p.indexOf(marker);
  const after =
    i >= 0 ? p.slice(i + marker.length) : p.replace(new RegExp(`^${marker}`), "");
  return after.split("/").filter(Boolean);
}

function sanitizePath(filename: string, merchantId: string): string {
  const safeName = filename
    .toLowerCase()
    .replace(/[^a-z0-9._-]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 64);
  return `merchant/${merchantId}/${Date.now()}-${crypto.randomUUID()}-${safeName || "evidence"}`;
}

type MerchantAuth = {
  userId: string;
  merchantId: string;
  merchantIds: string[];
};

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

  let parsedBody: Record<string, unknown> | null = null;
  if (req.method === "POST") {
    parsedBody = await req.json().catch(() => ({}));
  }

  const token = extractToken(req, url, parsedBody);
  if (!token) {
    return errorResponse("Missing authorization", "unauthorized", 401);
  }

  const anonClient = createClient(supabaseUrl, anonKey);
  const { data: userData, error: userError } = await anonClient.auth.getUser(token);
  if (userError || !userData?.user) {
    return errorResponse("Invalid or expired token", "unauthorized", 401);
  }
  const userId = userData.user.id;

  const serviceClient = createClient(supabaseUrl, serviceKey);
  let merchantContext;
  try {
    merchantContext = await resolveAuth(serviceClient, userId, req.headers);
    requirePermission(merchantContext, "orders");
  } catch (err) {
    return errorResponse((err as Error).message, "forbidden", 403);
  }
  const auth: MerchantAuth = {
    userId,
    merchantId: merchantContext.merchantId,
    merchantIds: merchantContext.merchantIds,
  };

  if (segments[0] === "uploads" && req.method === "POST") {
    return await handleUploadSlots(serviceClient, auth, parsedBody ?? {});
  }

  if (req.method === "GET" || (req.method === "POST" && segments.length === 0)) {
    // GET list or POST list (body filters)
    if (segments.length === 1 && segments[0]) {
      return await handleDetail(serviceClient, auth, segments[0]);
    }
    return await handleList(serviceClient, auth, url.searchParams, parsedBody ?? {});
  }

  if (segments.length === 2 && req.method === "POST") {
    const requestId = segments[0];
    const action = segments[1];
    if (action === "approve") {
      return await handleApprove(serviceClient, auth, requestId, parsedBody ?? {});
    }
    if (action === "reject") {
      return await handleReject(serviceClient, auth, requestId, parsedBody ?? {});
    }
  }

  return errorResponse("Route not found", "not_found", 404);
});

function extractToken(
  req: Request,
  url: URL,
  body: Record<string, unknown> | null
): string {
  const header = req.headers.get("Authorization") ?? "";
  const bearer = header.replace(/^[Bb]earer\s+/i, "").trim();
  const custom = req.headers.get("x-app-bearer")?.trim() ?? "";
  const queryToken = url.searchParams.get("access_token")?.trim() ?? "";
  const bodyToken =
    body && typeof body.access_token === "string" ? body.access_token.trim() : "";
  return bodyToken || queryToken || custom || bearer;
}

async function handleUploadSlots(
  supabase: ReturnType<typeof createClient>,
  auth: MerchantAuth,
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
    const path = sanitizePath(filename, auth.merchantId);
    const { data, error } = await bucket.createSignedUploadUrl(path);
    if (error || !data) {
      console.error("[merchant-after-sales] upload url error", error?.message);
      return errorResponse("Failed to create upload url", "storage_error", 500);
    }
    uploads.push({ path, bucket: AFTER_SALES_BUCKET, signedUrl: data.signedUrl, token: data.token });
  }
  return jsonResponse({ uploads });
}

async function handleList(
  supabase: ReturnType<typeof createClient>,
  auth: MerchantAuth,
  params: URLSearchParams,
  body: Record<string, unknown>
): Promise<Response> {
  const statusParam =
    (body?.status as string) || params.get("status") || "pending,awaiting_platform";
  const statuses = Array.from(
    new Set(
      statusParam
        .split(",")
        .map((s) => s.trim())
        .filter(Boolean)
    )
  );
  const storeId = (body?.storeId as string) || params.get("store_id") || null;
  const page = Math.max(Number((body?.page as number) ?? params.get("page") ?? 1), 1);
  const perPage = Math.min(
    Math.max(Number((body?.perPage as number) ?? params.get("per_page") ?? 20), 1),
    100,
  );
  const offset = (page - 1) * perPage;

  let query = supabase
    .from("after_sales_requests")
    .select(
      "id, status, reason_code, reason_detail, refund_amount, user_attachments, merchant_feedback, created_at, expires_at, store_id, order_id, user_id, timeline, orders(total_amount, order_number), after_sales_events(*)",
      { count: "exact" }
    )
    .in("merchant_id", auth.merchantIds)
    .order("created_at", { ascending: false })
    .range(offset, offset + perPage - 1);

  if (statuses.length) {
    query = query.in("status", statuses);
  }
  if (storeId) {
    query = query.eq("store_id", storeId);
  }

  const { data, error, count } = await query;
  if (error) {
    console.error("[merchant-after-sales] list error", error.message);
    return errorResponse("Failed to load after-sales requests", "db_error", 500);
  }

  const rows = data ?? [];
  const userIds = [
    ...new Set(
      rows
        .map((r: { user_id?: string | null }) => r.user_id)
        .filter((id): id is string => typeof id === "string" && id.length > 0),
    ),
  ];
  const userMap = new Map<string, { full_name: string | null }>();
  if (userIds.length > 0) {
    const { data: usersData, error: usersErr } = await supabase
      .from("users")
      .select("id, full_name")
      .in("id", userIds);
    if (usersErr) {
      console.error("[merchant-after-sales] list users error", usersErr.message);
      return errorResponse("Failed to load after-sales requests", "db_error", 500);
    }
    for (const u of usersData ?? []) {
      userMap.set(u.id as string, { full_name: (u as { full_name?: string | null }).full_name ?? null });
    }
  }

  const hydrated = await decorateAfterSalesRequests(supabase, rows);
  return jsonResponse({
    data: hydrated.map((row) => {
      const u = userMap.get(String(row.user_id ?? ""));
      const fullName = u?.full_name ?? null;
      return {
        ...row,
        users: fullName != null ? { full_name: fullName } : null,
        user_display_name: maskName(fullName ?? "Anonymous"),
      };
    }),
    total: count ?? 0,
    page,
    per_page: perPage,
  });
}

function maskName(name: string): string {
  if (!name) return "User";
  if (name.length === 1) return `${name[0]}*`;
  return `${name[0]}***${name[name.length - 1]}`;
}

async function handleDetail(
  supabase: ReturnType<typeof createClient>,
  auth: MerchantAuth,
  requestId: string
): Promise<Response> {
  const { data, error } = await supabase
    .from("after_sales_requests")
    .select("*, orders(*), after_sales_events(*)")
    .eq("id", requestId)
    .in("merchant_id", auth.merchantIds)
    .single();

  if (error || !data) {
    return errorResponse("Request not found", "not_found", 404);
  }

  const uid = data.user_id as string | undefined;
  let userRow: { full_name: string | null; avatar_url: string | null } | null = null;
  if (uid) {
    const { data: u } = await supabase
      .from("users")
      .select("full_name, avatar_url")
      .eq("id", uid)
      .maybeSingle();
    userRow = u
      ? {
        full_name: (u as { full_name?: string | null }).full_name ?? null,
        avatar_url: (u as { avatar_url?: string | null }).avatar_url ?? null,
      }
      : null;
  }

  const withUser = {
    ...data,
    users: userRow
      ? { full_name: userRow.full_name, avatar_url: userRow.avatar_url }
      : null,
  };
  const hydrated = await decorateAfterSalesRequest(supabase, withUser);
  return jsonResponse({
    request: {
      ...hydrated,
      user_display_name: maskName(userRow?.full_name ?? "Anonymous"),
    },
  });
}

async function handleApprove(
  supabase: ReturnType<typeof createClient>,
  auth: MerchantAuth,
  requestId: string,
  body: Record<string, unknown>
): Promise<Response> {
  const note = typeof body.note === "string" ? body.note.trim() : "";
  const attachments = normalizeAttachmentKeys(body.attachments ?? []);
  if (note.length < 5) {
    return errorResponse("Approval note must be at least 5 characters", "invalid_note", 400);
  }

  const request = await fetchRequestForAction(supabase, auth, requestId);
  if (!request) {
    return errorResponse("Request not found", "not_found", 404);
  }
  if (request.status !== "pending") {
    return errorResponse(
      `Request status is ${request.status}, expected pending`,
      "invalid_status",
      400,
    );
  }

  const nowIso = new Date().toISOString();
  const decisionTimeline = appendTimeline(request.timeline, {
    status: "merchant_approved",
    actor: "merchant",
    note,
    attachments,
    at: nowIso,
  } as TimelineEntry);

  const { data: updated, error: updateError } = await supabase
    .from("after_sales_requests")
    .update({
      status: "merchant_approved",
      merchant_feedback: note,
      merchant_attachments: attachments,
      timeline: decisionTimeline,
      metadata: {
        ...(request.metadata ?? {}),
        merchant_decided_at: nowIso,
        merchant_actor: auth.userId,
      },
    })
    .eq("id", requestId)
    .select("id, order_id, coupon_id, refund_amount, timeline, metadata")
    .single();

  if (updateError || !updated) {
    console.error("[merchant-after-sales] approve update error", updateError?.message);
    return errorResponse("Failed to update request", "update_failed", 500);
  }

  await recordAfterSalesEvent({
    supabase,
    requestId,
    actorRole: "merchant",
    actorId: auth.userId,
    action: "merchant_approved",
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
            is_pre_auth: refundResult.isPreAuth,
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
      actorId: auth.userId,
      action: "refund_succeeded",
      note: `Refunded (${refundResult.status})`,
      extra: { refund_id: refundResult.refundId },
    });
    // C13 + M10：通知客户已批准，通知商家确认（fire-and-forget）
    (async () => {
      try {
        const { data: reqInfo } = await supabase
          .from("after_sales_requests")
          .select("user_id, coupons(deal_id, deals(title))")
          .eq("id", requestId)
          .single();
        const { data: merchantInfo } = await supabase
          .from("merchants").select("name").eq("id", auth.merchantId).single();
        const merchantName = merchantInfo?.name ?? "";
        const dealTitle = (reqInfo as any)?.coupons?.deals?.title as string | undefined;
        const requestIdShort = requestId.slice(0, 8).toUpperCase();
        const refundAmount = Number(updated.refund_amount ?? 0);

        if (reqInfo?.user_id) {
          const { data: customerUser } = await supabase
            .from("users").select("email").eq("id", reqInfo.user_id).single();
          if (customerUser?.email) {
            const { subject: c13Subject, html: c13Html } = buildC13Email({
              requestId: requestIdShort, merchantName, decision: "approved",
              merchantNote: note, refundAmount, dealTitle,
            });
            await sendEmail(supabase, {
              to: customerUser.email, subject: c13Subject, htmlBody: c13Html,
              emailCode: "C13", referenceId: requestId, recipientType: "customer",
              userId: reqInfo.user_id,
            });
          }
        }

        const { data: merchantUser } = await supabase
          .from("users").select("email").eq("id", auth.userId).single();
        if (merchantUser?.email) {
          const { subject: m10Subject, html: m10Html } = buildM10Email({
            merchantName, requestId: requestIdShort, refundAmount,
          });
          await sendEmail(supabase, {
            to: merchantUser.email, subject: m10Subject, htmlBody: m10Html,
            emailCode: "M10", referenceId: requestId, recipientType: "merchant",
            merchantId: auth.merchantId,
          });
        }
      } catch (err) {
        console.warn("[merchant-after-sales] approve email failed", err);
      }
    })();

    const refreshed = await fetchMerchantRequest(supabase, auth, requestId);
    const hydrated = await decorateAfterSalesRequest(supabase, refreshed);
    const fallback = await decorateAfterSalesRequest(supabase, updated);
    return jsonResponse({ request: hydrated ?? fallback, refund: refundResult });
  } catch (err) {
    console.error("[merchant-after-sales] refund error", err);
    const failTimeline = appendTimeline(updated.timeline, {
      status: "merchant_approved",
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
      actorId: auth.userId,
      action: "refund_failed",
      note: (err as Error).message,
    });
    return errorResponse((err as Error).message, "stripe_error", 502);
  }
}

async function handleReject(
  supabase: ReturnType<typeof createClient>,
  auth: MerchantAuth,
  requestId: string,
  body: Record<string, unknown>
): Promise<Response> {
  const note = typeof body.note === "string" ? body.note.trim() : "";
  const attachments = normalizeAttachmentKeys(body.attachments ?? []);
  if (note.length < 10) {
    return errorResponse("Rejection reason must be at least 10 characters", "invalid_note", 400);
  }
  if (!attachments.length) {
    return errorResponse(
      "At least one attachment is required for rejection",
      "attachments_required",
      400,
    );
  }

  const request = await fetchRequestForAction(supabase, auth, requestId);
  if (!request) {
    return errorResponse("Request not found", "not_found", 404);
  }
  if (request.status !== "pending") {
    return errorResponse(
      `Request status is ${request.status}, expected pending`,
      "invalid_status",
      400,
    );
  }

  const nowIso = new Date().toISOString();
  const timeline = appendTimeline(request.timeline, {
    status: "merchant_rejected",
    actor: "merchant",
    note,
    attachments,
    at: nowIso,
  });

  const { data, error } = await supabase
    .from("after_sales_requests")
    .update({
      status: "merchant_rejected",
      merchant_feedback: note,
      merchant_attachments: attachments,
      timeline,
      metadata: {
        ...(request.metadata ?? {}),
        merchant_decided_at: nowIso,
        merchant_actor: auth.userId,
      },
    })
    .eq("id", requestId)
    .select("id, status, timeline")
    .single();

  if (error || !data) {
    console.error("[merchant-after-sales] reject error", error?.message);
    return errorResponse("Failed to reject request", "update_failed", 500);
  }

  await recordAfterSalesEvent({
    supabase,
    requestId,
    actorRole: "merchant",
    actorId: auth.userId,
    action: "merchant_rejected",
    note,
    attachments,
  });
  // C13 + M11：通知客户已拒绝，通知商家拒绝已记录（fire-and-forget）
  (async () => {
    try {
      const { data: reqInfo } = await supabase
        .from("after_sales_requests")
        .select("user_id, coupons(deal_id, deals(title))")
        .eq("id", requestId)
        .single();
      const { data: merchantInfo } = await supabase
        .from("merchants").select("name").eq("id", auth.merchantId).single();
      const merchantName = merchantInfo?.name ?? "";
      const dealTitle = (reqInfo as any)?.coupons?.deals?.title as string | undefined;
      const requestIdShort = requestId.slice(0, 8).toUpperCase();

      if (reqInfo?.user_id) {
        const { data: customerUser } = await supabase
          .from("users").select("email").eq("id", reqInfo.user_id).single();
        if (customerUser?.email) {
          const { subject: c13Subject, html: c13Html } = buildC13Email({
            requestId: requestIdShort, merchantName, decision: "rejected",
            merchantNote: note, dealTitle,
          });
          await sendEmail(supabase, {
            to: customerUser.email, subject: c13Subject, htmlBody: c13Html,
            emailCode: "C13", referenceId: requestId, recipientType: "customer",
            userId: reqInfo.user_id,
          });
        }
      }

      const { data: merchantUser } = await supabase
        .from("users").select("email").eq("id", auth.userId).single();
      if (merchantUser?.email) {
        const { subject: m11Subject, html: m11Html } = buildM11Email({
          merchantName, requestId: requestIdShort,
        });
        await sendEmail(supabase, {
          to: merchantUser.email, subject: m11Subject, htmlBody: m11Html,
          emailCode: "M11", referenceId: requestId, recipientType: "merchant",
          merchantId: auth.merchantId,
        });
      }
    } catch (err) {
      console.warn("[merchant-after-sales] reject email failed", err);
    }
  })();

  const refreshed = await fetchMerchantRequest(supabase, auth, requestId);
  const hydrated = await decorateAfterSalesRequest(supabase, refreshed);
  const fallback = await decorateAfterSalesRequest(supabase, data);
  return jsonResponse({ request: hydrated ?? fallback });
}

async function fetchRequestForAction(
  supabase: ReturnType<typeof createClient>,
  auth: MerchantAuth,
  requestId: string
) {
  const { data } = await supabase
    .from("after_sales_requests")
    .select("id, status, order_id, coupon_id, refund_amount, timeline, metadata")
    .eq("id", requestId)
    .in("merchant_id", auth.merchantIds)
    .maybeSingle();
  return data ?? null;
}

async function fetchMerchantRequest(
  supabase: ReturnType<typeof createClient>,
  auth: MerchantAuth,
  requestId: string
) {
  const { data } = await supabase
    .from("after_sales_requests")
    .select("*, after_sales_events(*)")
    .eq("id", requestId)
    .in("merchant_id", auth.merchantIds)
    .maybeSingle();
  return data ?? null;
}
