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
import { sendEmail, getAdminRecipients } from "../_shared/email.ts";
import { buildC9Email } from "../_shared/email-templates/customer/after-sales-submitted.ts";
import { buildM9Email } from "../_shared/email-templates/merchant/after-sales-received.ts";
import { buildA5Email } from "../_shared/email-templates/admin/after-sales-escalated.ts";

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
  // 使用带 Authorization 的 anon client + getUser()，由服务端校验 JWT（支持 ES256）
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false },
  });
  const { data, error } = await userClient.auth.getUser();
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

/** 宽松 UUID 匹配（16 位券码 XXXX-XXXX-XXXX-XXXX 不会误匹配） */
const LOOSE_UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** 将用户输入规范为 DB coupons.coupon_code（16 位大写十六进制，无分隔符） */
function normalizeCouponCodeInput(raw: string): string | null {
  const norm = raw.replace(/-/g, "").toUpperCase();
  if (norm.length !== 16 || !/^[0-9A-F]+$/.test(norm)) return null;
  return norm;
}

/** 仅标量列，避免 PostgREST 嵌套 embed 在部分环境下报错导致整查询失败 */
const COUPON_SELECT_FOR_CREATE =
  "id, order_id, order_item_id, user_id, status, used_at, merchant_id, redeemed_at_merchant_id, deal_id";

type CouponForCreate = {
  id: string;
  order_id: string | null;
  order_item_id: string | null;
  user_id: string;
  status: string;
  used_at: string | null;
  merchant_id: string | null;
  redeemed_at_merchant_id: string | null;
  deal_id: string | null;
};

/**
 * 解析可用于提交售后的已使用券：
 * - couponId 为 UUID：按 id 查，若无行且带了 orderId 则回退按订单查（避免误传 order_item id）
 * - couponId 为展示用券码：按 coupon_code 查
 * - 仅 orderId：取该订单下最近核销的一张 used 券
 */
async function findCouponForAfterSalesCreate(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  couponIdRaw: string,
  orderIdRaw: string,
): Promise<CouponForCreate | null> {
  const base = () =>
    supabase
      .from("coupons")
      .select(COUPON_SELECT_FOR_CREATE)
      .eq("user_id", userId)
      .eq("status", "used");

  const byId = async (id: string): Promise<CouponForCreate | null> => {
    const { data, error } = await base().eq("id", id).maybeSingle();
    if (error) {
      console.error("[after-sales] coupon byId", error.message);
      return null;
    }
    return (data as CouponForCreate) ?? null;
  };

  const byOrder = async (orderId: string): Promise<CouponForCreate | null> => {
    const { data, error } = await base()
      .eq("order_id", orderId)
      .order("used_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    if (error) {
      console.error("[after-sales] coupon byOrder", error.message);
      return null;
    }
    return (data as CouponForCreate) ?? null;
  };

  const byCode = async (code: string): Promise<CouponForCreate | null> => {
    const { data, error } = await base().eq("coupon_code", code).maybeSingle();
    if (error) {
      console.error("[after-sales] coupon byCode", error.message);
      return null;
    }
    return (data as CouponForCreate) ?? null;
  };

  if (couponIdRaw && !LOOSE_UUID_RE.test(couponIdRaw)) {
    const code = normalizeCouponCodeInput(couponIdRaw);
    if (code) {
      const c = await byCode(code);
      if (c) return c;
    }
    if (orderIdRaw) return await byOrder(orderIdRaw);
    return null;
  }

  if (couponIdRaw && LOOSE_UUID_RE.test(couponIdRaw)) {
    const c = await byId(couponIdRaw);
    if (c) return c;
    if (orderIdRaw) return await byOrder(orderIdRaw);
    return null;
  }

  if (orderIdRaw) return await byOrder(orderIdRaw);
  return null;
}

function sanitizePath(filename: string, userId: string): string {
  const safeName = filename
    .toLowerCase()
    .replace(/[^a-z0-9._-]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 64);
  return `user/${userId}/${Date.now()}-${crypto.randomUUID()}-${safeName || "evidence"}`;
}

/** 与 supabase/config.toml 中函数目录名一致 */
const FUNCTION_SLUG = "after-sales-request";

/**
 * 从 URL pathname 解析函数名之后的子路径段。
 * 线上网关 pathname 为 /functions/v1/after-sales-request/...，本地或直连可能为 /after-sales-request/...
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
  const parts = routePartsFromPathname(url.pathname);

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

/** 与 submit-refund-dispute 一致：按单行 order_item 计算可退金额（勿用整单 orders.total_amount） */
function roundMoneyAmount(n: number): number {
  return Math.round(n * 100) / 100;
}

/**
 * 根据券对应的 order_items 行计算售后申请退款额（单价 + 服务费 + 税）。
 * 多商家一单时，每券只关联一行，避免误用整单总价。
 */
async function computeAfterSalesRefundAmount(
  supabase: ReturnType<typeof createClient>,
  coupon: CouponForCreate,
  orderId: string,
): Promise<{ ok: true; amount: number } | { ok: false; response: Response }> {
  let orderItemId = coupon.order_item_id;
  if (!orderItemId) {
    const { data: row, error } = await supabase
      .from("order_items")
      .select("id")
      .eq("order_id", orderId)
      .eq("coupon_id", coupon.id)
      .maybeSingle();
    if (error) {
      console.error("[after-sales] resolve order_item by coupon_id", error.message);
      return {
        ok: false,
        response: errorResponse(
          "Failed to resolve order line for refund amount",
          "db_error",
          500,
        ),
      };
    }
    orderItemId = (row as { id?: string } | null)?.id ?? null;
  }

  if (!orderItemId) {
    return {
      ok: false,
      response: errorResponse(
        "Missing order line for this coupon; cannot compute refund amount",
        "order_item_missing",
        400,
      ),
    };
  }

  const { data: item, error: itemErr } = await supabase
    .from("order_items")
    .select("id, order_id, unit_price, service_fee, tax_amount")
    .eq("id", orderItemId)
    .eq("order_id", orderId)
    .maybeSingle();

  if (itemErr || !item) {
    if (itemErr) console.error("[after-sales] order_item fetch", itemErr.message);
    return {
      ok: false,
      response: errorResponse("Order line not found for this coupon", "order_item_missing", 404),
    };
  }

  const row = item as {
    unit_price: number | string | null;
    service_fee: number | string | null;
    tax_amount: number | string | null;
  };
  const unitPrice = Number(row.unit_price ?? 0);
  const serviceFee = Number(row.service_fee ?? 0);
  const taxAmount = Number(row.tax_amount ?? 0);
  const amount = roundMoneyAmount(unitPrice + serviceFee + taxAmount);

  if (!amount || Number.isNaN(amount) || amount <= 0) {
    return {
      ok: false,
      response: errorResponse(
        "Invalid refundable amount for this coupon",
        "invalid_amount",
        400,
      ),
    };
  }

  return { ok: true, amount };
}

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

  const coupon = await findCouponForAfterSalesCreate(supabase, userId, couponId, orderId);
  if (!coupon) {
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

  // 与争议退款互斥：同一 order_item 仅一条待处理主诉求
  if (coupon.order_item_id) {
    const { data: pendingDispute } = await supabase
      .from("refund_requests")
      .select("id")
      .eq("order_item_id", coupon.order_item_id)
      .in("status", ["pending_merchant", "pending_admin"])
      .maybeSingle();
    if (pendingDispute) {
      return errorResponse(
        "A refund dispute is already pending for this coupon. Wait for merchant review or for automatic escalation to After-sales.",
        "dispute_pending",
        409,
      );
    }
  }

  if (!coupon.order_id) {
    return errorResponse("Order reference missing", "order_missing", 400);
  }
  // 仅校验订单存在（退款额按 order_items 行计算，勿用 orders.total_amount）
  const { data: orderRow, error: orderFetchError } = await supabase
    .from("orders")
    .select("id")
    .eq("id", coupon.order_id)
    .maybeSingle();
  if (orderFetchError || !orderRow) {
    if (orderFetchError) {
      console.error("[after-sales] order fetch", orderFetchError.message);
    }
    return errorResponse("Order reference missing", "order_missing", 400);
  }
  const order = orderRow as { id: string };

  const refundCalc = await computeAfterSalesRefundAmount(supabase, coupon, order.id);
  if (!refundCalc.ok) return refundCalc.response;
  const refundAmount = refundCalc.amount;

  const nowIso = new Date().toISOString();
  const expiresAt = new Date(
    new Date(coupon.used_at).getTime() + WINDOW_DAYS * 24 * 60 * 60 * 1000,
  ).toISOString();

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
    console.error(
      "[after-sales] insert error",
      insertError?.message,
      insertError?.code,
      insertError?.details,
    );
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

  // 发送邮件通知（fire-and-forget）
  const requestIdShort = created.id.slice(0, 8).toUpperCase();
  let dealTitle: string | undefined;
  if (coupon.deal_id) {
    const { data: dealRow } = await supabase
      .from("deals")
      .select("title")
      .eq("id", coupon.deal_id)
      .maybeSingle();
    dealTitle = (dealRow?.title as string | undefined) ?? undefined;
  }
  (async () => {
    try {
      // C9：客户提交售后申请确认
      const { data: userRow } = await supabase
        .from("users").select("email").eq("id", userId).single();
      if (userRow?.email) {
        const { subject: c9Subject, html: c9Html } = buildC9Email({
          requestId: requestIdShort,
          reasonCode,
          dealTitle,
        });
        await sendEmail(supabase, {
          to: userRow.email, subject: c9Subject, htmlBody: c9Html,
          emailCode: "C9", referenceId: created.id, recipientType: "customer", userId,
        });
      }

      // M9：通知商家收到售后申请
      const { data: merchantRow } = await supabase
        .from("merchants").select("name, user_id").eq("id", insertPayload.merchant_id).single();
      if (merchantRow) {
        const { data: merchantUserRow } = await supabase
          .from("users").select("email").eq("id", merchantRow.user_id).single();
        if (merchantUserRow?.email) {
          const { subject: m9Subject, html: m9Html } = buildM9Email({
            merchantName: merchantRow.name,
            requestId: requestIdShort,
            reasonCode,
            reasonDetail,
            dealTitle,
          });
          await sendEmail(supabase, {
            to: merchantUserRow.email, subject: m9Subject, htmlBody: m9Html,
            emailCode: "M9", referenceId: created.id, recipientType: "merchant",
            merchantId: insertPayload.merchant_id,
          });
        }
      }
    } catch (err) {
      console.warn("[after-sales] email notification failed", err);
    }
  })();

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
  let query = supabase
    .from("after_sales_requests")
    .select("*, after_sales_events(*)")
    .eq("user_id", userId)
    .order("created_at", { ascending: false });

  if (filterOrder) {
    query = query.eq("order_id", filterOrder);
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

  // A5：通知管理员案件已升级（fire-and-forget）
  (async () => {
    try {
      const adminEmails = await getAdminRecipients(supabase, "A5");
      if (adminEmails.length > 0) {
        // 查询案件详情（reason_code, reason_detail, merchant_feedback, deal title）
        const { data: reqDetail } = await supabase
          .from("after_sales_requests")
          .select("reason_code, reason_detail, merchant_feedback, coupon_id, coupons(deal_id, deals(title))")
          .eq("id", requestId)
          .single();
        const dealTitle = (reqDetail as any)?.coupons?.deals?.title as string | undefined;
        const { subject: a5Subject, html: a5Html } = buildA5Email({
          requestId: requestId.slice(0, 8).toUpperCase(),
          reasonCode: reqDetail?.reason_code ?? "",
          reasonDetail: reqDetail?.reason_detail ?? "",
          merchantRejectionNote: reqDetail?.merchant_feedback ?? undefined,
          dealTitle,
        });
        await sendEmail(supabase, {
          to: adminEmails, subject: a5Subject, htmlBody: a5Html,
          emailCode: "A5", referenceId: requestId, recipientType: "admin",
        });
      }
    } catch (err) {
      console.warn("[after-sales] A5 admin escalation email failed", err);
    }
  })();

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
