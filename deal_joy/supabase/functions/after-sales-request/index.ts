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

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

const REASON_CODES = new Set<
  "mistaken_redemption" | "bad_experience" | "service_issue" | "quality_issue" | "other"
>(["mistaken_redemption", "bad_experience", "service_issue", "quality_issue", "other"]);

const WINDOW_DAYS = 7;

function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function errorResponse(message: string, code = "bad_request", status = 400): Response {
  return jsonResponse({ error: code, message }, status);
}

type AuthContext = { token: string; userId: string };

async function resolveUser(
  req: Request,
  anonKey: string,
  parsedBody: Record<string, unknown> | null
): Promise<AuthContext> {
  const url = new URL(req.url);
  const authHeader = req.headers.get("Authorization") ?? "";
  const headerToken = authHeader.replace(/^[Bb]earer\s+/i, "").trim();
  const queryToken = url.searchParams.get("access_token")?.trim() ?? "";
  const bodyToken =
    parsedBody && typeof parsedBody.access_token === "string"
      ? parsedBody.access_token.trim()
      : "";
  const token = bodyToken || queryToken || headerToken;
  if (!token) {
    throw new Error("Missing authorization token");
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const userClient = createClient(supabaseUrl, anonKey);
  const { data, error } = await userClient.auth.getUser(token);
  if (error || !data?.user) {
    throw new Error("Invalid or expired token");
  }

  return { token, userId: data.user.id };
}

function withinWindow(usedAt: string): boolean {
  const used = new Date(usedAt).getTime();
  const now = Date.now();
  const diffDays = (now - used) / (1000 * 60 * 60 * 24);
  return diffDays <= WINDOW_DAYS;
}

function sanitizePath(filename: string, userId: string): string {
  const safeName = filename
    .toLowerCase()
    .replace(/[^a-z0-9._-]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 64);
  return `user/${userId}/${Date.now()}-${crypto.randomUUID()}-${safeName || "evidence"}`;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const allowedMethods = ["GET", "POST"];
  if (!allowedMethods.includes(req.method)) {
    return errorResponse("Method not allowed", "method_not_allowed", 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

  if (!supabaseUrl || !serviceKey || !anonKey) {
    return errorResponse("Supabase env vars missing", "config_error", 500);
  }

  let parsedBody: Record<string, unknown> | null = null;
  if (req.method !== "GET") {
    parsedBody = await req.json().catch(() => ({}));
  }

  let auth: AuthContext;
  try {
    auth = await resolveUser(req, anonKey, parsedBody);
  } catch (err) {
    return errorResponse((err as Error).message, "unauthorized", 401);
  }

  const serviceClient = createClient(supabaseUrl, serviceKey);
  const url = new URL(req.url);
  const pathname = url.pathname.replace(/\/+$/, "");
  const suffix = pathname.replace(/^\/after-sales-request/, "");
  const parts = suffix.split("/").filter(Boolean);

  if (parts[0] === "uploads" && req.method === "POST") {
    return await handleUploadSlots(serviceClient, auth, parsedBody ?? {});
  }

  if (req.method === "GET") {
    if (parts.length === 1 && parts[0]) {
      return await handleGetSingle(serviceClient, auth.userId, parts[0]);
    }
    return await handleList(serviceClient, auth.userId, url.searchParams);
  }

  // POST actions
  if (parts.length === 2 && parts[1] === "escalate") {
    return await handleEscalation(serviceClient, auth.userId, parts[0]);
  }

  if (parts.length === 0) {
    return await handleCreateRequest(serviceClient, auth.userId, parsedBody ?? {});
  }

  return errorResponse("Unsupported route", "not_found", 404);
});

async function handleUploadSlots(
  supabase: ReturnType<typeof createClient>,
  auth: AuthContext,
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
  const results = [];
  for (const file of files) {
    const name = typeof file?.filename === "string" ? file.filename : "evidence";
    const path = sanitizePath(name, auth.userId);
    const { data, error } = await bucket.createSignedUploadUrl(path);
    if (error || !data) {
      console.error("[after-sales-upload] failed", error?.message);
      return errorResponse("Failed to create upload url", "storage_error", 500);
    }
    results.push({
      path,
      bucket: AFTER_SALES_BUCKET,
      signedUrl: data.signedUrl,
      token: data.token,
    });
  }

  return jsonResponse({ uploads: results });
}

async function handleCreateRequest(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  body: Record<string, unknown>
): Promise<Response> {
  const couponId = typeof body.couponId === "string" ? body.couponId.trim() : "";
  const orderId = typeof body.orderId === "string" ? body.orderId.trim() : "";
  const reasonCode = typeof body.reasonCode === "string" ? body.reasonCode : "";
  const reasonDetail = typeof body.reasonDetail === "string" ? body.reasonDetail.trim() : "";
  const attachmentKeys = normalizeAttachmentKeys(body.attachments ?? []);

  if (!couponId && !orderId) {
    return errorResponse("couponId or orderId required", "invalid_payload", 400);
  }
  if (!REASON_CODES.has(reasonCode as any)) {
    return errorResponse("Invalid reason code", "invalid_reason", 400);
  }
  if (reasonDetail.length < 20) {
    return errorResponse("Reason detail must be at least 20 characters", "invalid_detail", 400);
  }

  let couponQuery = supabase
    .from("coupons")
    .select(
      "id, order_id, user_id, status, used_at, merchant_id, redeemed_at_merchant_id, orders(id, total_amount, merchant_id)"
    )
    .eq("user_id", userId)
    .eq("status", "used")
    .limit(1);

  if (couponId) {
    couponQuery = couponQuery.eq("id", couponId);
  } else {
    couponQuery = couponQuery.eq("order_id", orderId);
  }

  const { data: coupon, error: couponError } = await couponQuery.single();
  if (couponError || !coupon) {
    return errorResponse("Coupon not found or not redeemable", "coupon_not_found", 404);
  }
  if (!coupon.used_at) {
    return errorResponse("Coupon has not been redeemed", "not_used", 400);
  }
  if (!withinWindow(coupon.used_at)) {
    return errorResponse("After-sales window expired", "window_expired", 400);
  }

  const existsQuery = await supabase
    .from("after_sales_requests")
    .select("id, status")
    .eq("coupon_id", coupon.id)
    .not("status", "in", "(refunded,closed,platform_rejected)")
    .maybeSingle();
  if (existsQuery.data) {
    return errorResponse(
      "An after-sales request already exists for this coupon",
      "duplicate_request",
      409,
    );
  }

  const nowIso = new Date().toISOString();
  const expiresAt = new Date(
    new Date(coupon.used_at).getTime() + WINDOW_DAYS * 24 * 60 * 60 * 1000,
  ).toISOString();
  const order = coupon.orders as
    | { id: string; total_amount: number; merchant_id: string }
    | null;
  if (!order) {
    return errorResponse("Order reference missing", "order_missing", 400);
  }
  const refundAmount = Number(order.total_amount);

  const timeline: TimelineEntry[] = appendTimeline([], {
    status: "pending",
    actor: "user",
    note: reasonDetail,
    attachments: attachmentKeys,
    at: nowIso,
  });

  const insertPayload = {
    order_id: order.id,
    coupon_id: coupon.id,
    user_id: userId,
    merchant_id: coupon.merchant_id,
    store_id: coupon.redeemed_at_merchant_id ?? coupon.merchant_id,
    status: "pending",
    reason_code: reasonCode,
    reason_detail: reasonDetail,
    refund_amount: refundAmount,
    user_attachments: attachmentKeys,
    expires_at: expiresAt,
    timeline,
    metadata: { source: "deal_joy" },
  };

  const { data: created, error: insertError } = await supabase
    .from("after_sales_requests")
    .insert(insertPayload)
    .select("id, status, expires_at, timeline")
    .single();

  if (insertError || !created) {
    console.error("[after-sales] insert error", insertError?.message);
    return errorResponse("Failed to submit after-sales request", "insert_failed", 500);
  }

  await recordAfterSalesEvent({
    supabase,
    requestId: created.id,
    actorRole: "user",
    actorId: userId,
    action: "user_submitted",
    note: reasonDetail,
    attachments: attachmentKeys,
    extra: { reason_code: reasonCode },
  });
  await notifyMerchantAfterSales(supabase, insertPayload.merchant_id, created.id, reasonCode);
  const decorated = await fetchUserRequest(supabase, userId, created.id);
  const hydrated = await decorateAfterSalesRequest(supabase, decorated);
  return jsonResponse({ request: hydrated });
}

async function handleList(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  params: URLSearchParams
): Promise<Response> {
  const filterOrder = params.get("order_id");
  const query = supabase
    .from("after_sales_requests")
    .select("*, after_sales_events(*)")
    .eq("user_id", userId)
    .order("created_at", { ascending: false });

  if (filterOrder) {
    query.eq("order_id", filterOrder);
  }

  const { data, error } = await query;
  if (error) {
    console.error("[after-sales] list error", error.message);
    return errorResponse("Failed to load requests", "db_error", 500);
  }
  const hydrated = await decorateAfterSalesRequests(supabase, data ?? []);
  return jsonResponse({ requests: hydrated });
}

async function handleGetSingle(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  requestId: string
): Promise<Response> {
  const { data, error } = await supabase
    .from("after_sales_requests")
    .select("*, after_sales_events(*)")
    .eq("user_id", userId)
    .eq("id", requestId)
    .single();

  if (error || !data) {
    return errorResponse("Request not found", "not_found", 404);
  }
  const hydrated = await decorateAfterSalesRequest(supabase, data);
  return jsonResponse({ request: hydrated });
}

async function handleEscalation(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  requestId: string
): Promise<Response> {
  const { data: request, error } = await supabase
    .from("after_sales_requests")
    .select("id, status, timeline")
    .eq("user_id", userId)
    .eq("id", requestId)
    .single();

  if (error || !request) {
    return errorResponse("Request not found", "not_found", 404);
  }
  if (request.status !== "merchant_rejected") {
    return errorResponse(
      "Only merchant rejected cases can be escalated",
      "invalid_status",
      400,
    );
  }

  const nowIso = new Date().toISOString();
  const updatedTimeline = appendTimeline(request.timeline, {
    status: "awaiting_platform",
    actor: "user",
    note: "User requested platform review",
    at: nowIso,
  });

  const { data: updated, error: updateError } = await supabase
    .from("after_sales_requests")
    .update({
      status: "awaiting_platform",
      escalated_at: nowIso,
      timeline: updatedTimeline,
    })
    .eq("id", requestId)
    .eq("user_id", userId)
    .select("id, status, timeline, escalated_at")
    .single();

  if (updateError || !updated) {
    console.error("[after-sales] escalate error", updateError?.message);
    return errorResponse("Failed to escalate", "update_failed", 500);
  }

  await recordAfterSalesEvent({
    supabase,
    requestId,
    actorRole: "user",
    actorId: userId,
    action: "user_escalated",
    note: "User requested platform review",
  });
  const decorated = await fetchUserRequest(supabase, userId, requestId);
  const hydrated = await decorateAfterSalesRequest(supabase, decorated);
  return jsonResponse({ request: hydrated });
}

async function fetchUserRequest(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  requestId: string
) {
  const { data } = await supabase
    .from("after_sales_requests")
    .select("*, after_sales_events(*)")
    .eq("id", requestId)
    .eq("user_id", userId)
    .single();
  return data;
}

async function notifyMerchantAfterSales(
  supabase: ReturnType<typeof createClient>,
  merchantId: string,
  requestId: string,
  reasonCode: string
) {
  try {
    await supabase.from("merchant_notifications").insert({
      merchant_id: merchantId,
      type: "system",
      title: "New After-Sales Request",
      body: "A customer submitted an after-sales request that needs review.",
      data: {
        request_id: requestId,
        reason_code: reasonCode,
      },
    });
  } catch (err) {
    console.warn("[after-sales] notify merchant failed", err);
  }
}
