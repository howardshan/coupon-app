import Stripe from "https://esm.sh/stripe@14?target=deno";
import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2?target=deno";

export type TimelineEntry = {
  status: string;
  actor: "user" | "merchant" | "platform" | "system";
  note?: string;
  attachments?: string[];
  at: string;
  meta?: Record<string, unknown>;
};

export type AfterSalesEventRow = {
  id: number;
  request_id: string;
  actor_role: "user" | "merchant" | "platform" | "system" | string;
  actor_id: string | null;
  action: string;
  payload: Record<string, unknown> | null;
  created_at: string;
};

export interface AfterSalesRequestRecord {
  id: string;
  order_id: string;
  coupon_id: string;
  user_id: string;
  merchant_id: string;
  store_id: string;
  status: string;
  refund_amount: number | string | null;
  timeline: unknown;
  metadata?: Record<string, unknown> | null;
  user_attachments?: string[] | null;
  merchant_attachments?: string[] | null;
  platform_attachments?: string[] | null;
  after_sales_events?: AfterSalesEventRow[] | null;
}

const stripeSecret = Deno.env.get("STRIPE_SECRET_KEY") ?? "";
if (!stripeSecret) {
  console.warn(
    "[after-sales] STRIPE_SECRET_KEY is not configured; refund calls will fail"
  );
}

const stripe = stripeSecret
  ? new Stripe(stripeSecret, {
      apiVersion: "2024-04-10",
      httpClient: Stripe.createFetchHttpClient(),
    })
  : null;

export const AFTER_SALES_BUCKET =
  Deno.env.get("SUPABASE_AFTER_SALE_BUCKET") ?? "after-sales-evidence";

const MAX_ATTACHMENTS = 3;
const SIGNED_URL_TTL = 60 * 60 * 24 * 30; // 30 days

function isSignedUrl(value: string): boolean {
  return /^https?:\/\//i.test(value.trim());
}

function sanitizeAttachmentValue(value: unknown): string | null {
  if (typeof value === "string" && value.trim()) {
    if (isSignedUrl(value)) {
      throw new Error("attachments must use storage path, not signed URL");
    }
    return value.trim();
  }
  if (value && typeof value === "object") {
    const path = "path" in value ? (value as { path?: string }).path : null;
    if (typeof path === "string" && path.trim()) {
      return path.trim();
    }
  }
  return null;
}

export function normalizeAttachmentKeys(input: unknown): string[] {
  if (input == null) return [];
  if (!Array.isArray(input)) {
    throw new Error("attachments must be an array");
  }
  if (input.length > MAX_ATTACHMENTS) {
    throw new Error(`attachments cannot exceed ${MAX_ATTACHMENTS}`);
  }
  const cleaned: string[] = [];
  for (const item of input) {
    const sanitized = sanitizeAttachmentValue(item);
    if (!sanitized) {
      throw new Error("attachments must contain path strings");
    }
    cleaned.push(sanitized);
  }
  return cleaned;
}

export async function signEvidenceUrls(
  supabase: SupabaseClient,
  keys: string[]
): Promise<Record<string, string>> {
  const uniqueKeys = Array.from(
    new Set(keys.filter((key) => typeof key === "string" && key.trim()))
  );
  if (!uniqueKeys.length) return {};
  const bucket = supabase.storage.from(AFTER_SALES_BUCKET);
  const signed: Record<string, string> = {};
  for (const key of uniqueKeys) {
    if (isSignedUrl(key)) {
      signed[key] = key;
      continue;
    }
    const { data, error } = await bucket.createSignedUrl(key, SIGNED_URL_TTL);
    if (error || !data?.signedUrl) {
      console.error("[after-sales] failed to sign url", key, error?.message);
      continue;
    }
    signed[key] = data.signedUrl;
  }
  return signed;
}

export function appendTimeline(
  existing: unknown,
  entry: TimelineEntry
): TimelineEntry[] {
  const arr: TimelineEntry[] = Array.isArray(existing)
    ? (existing as TimelineEntry[])
    : [];
  const attachments = Array.isArray(entry.attachments)
    ? entry.attachments
        .filter((value) => typeof value === "string" && value.trim())
        .map((value) => value.trim())
    : [];
  return [...arr, { ...entry, attachments }];
}

function collectKeysFromTimeline(timeline: TimelineEntry[]): string[] {
  const keys: string[] = [];
  for (const item of timeline) {
    if (!Array.isArray(item.attachments)) continue;
    for (const att of item.attachments) {
      if (typeof att === "string" && att.trim() && !isSignedUrl(att)) {
        keys.push(att.trim());
      }
    }
  }
  return keys;
}

function collectKeysFromEvents(events: AfterSalesEventRow[]): string[] {
  const keys: string[] = [];
  for (const event of events) {
    const payloadAttachments = Array.isArray(event.payload?.attachments)
      ? (event.payload!.attachments as unknown[])
      : [];
    for (const att of payloadAttachments) {
      if (typeof att === "string" && att.trim() && !isSignedUrl(att)) {
        keys.push(att.trim());
      }
    }
  }
  return keys;
}

function mapAttachmentList(
  list: string[] | null | undefined,
  signed: Record<string, string>
): string[] {
  if (!Array.isArray(list)) return [];
  return list
    .filter((value) => typeof value === "string" && value.trim())
    .map((value) => signed[value] ?? value);
}

export async function decorateAfterSalesRequest<T extends AfterSalesRequestRecord | null>(
  supabase: SupabaseClient,
  record: T
): Promise<T> {
  if (!record) return record;

  const timeline = Array.isArray(record.timeline)
    ? (record.timeline as TimelineEntry[])
    : [];
  const events = Array.isArray(record.after_sales_events)
    ? record.after_sales_events
    : [];

  const keyPool = new Set<string>();
  const addKeys = (values?: string[] | null) => {
    if (!Array.isArray(values)) return;
    for (const value of values) {
      if (typeof value === "string" && value.trim() && !isSignedUrl(value)) {
        keyPool.add(value.trim());
      }
    }
  };

  addKeys(record.user_attachments);
  addKeys(record.merchant_attachments);
  addKeys(record.platform_attachments);
  collectKeysFromTimeline(timeline).forEach((key) => keyPool.add(key));
  collectKeysFromEvents(events).forEach((key) => keyPool.add(key));

  const signedMap = await signEvidenceUrls(supabase, Array.from(keyPool));
  const hydratedTimeline = timeline.map((entry) => ({
    ...entry,
    attachments: mapAttachmentList(entry.attachments, signedMap),
  }));
  const hydratedEvents = events.map((event) => {
    const attachments = Array.isArray(event.payload?.attachments)
      ? (event.payload!.attachments as unknown[])
      : [];
    const formatted = attachments
      .filter((value): value is string => typeof value === "string")
      .map((value) => signedMap[value] ?? value);
    return {
      ...event,
      payload: {
        ...(event.payload ?? {}),
        attachments: formatted,
      },
    } satisfies AfterSalesEventRow;
  });

  return {
    ...record,
    user_attachments: mapAttachmentList(record.user_attachments, signedMap),
    merchant_attachments: mapAttachmentList(
      record.merchant_attachments,
      signedMap
    ),
    platform_attachments: mapAttachmentList(
      record.platform_attachments,
      signedMap
    ),
    timeline: hydratedTimeline,
    after_sales_events: hydratedEvents,
  } as T;
}

export async function decorateAfterSalesRequests(
  supabase: SupabaseClient,
  records: AfterSalesRequestRecord[] | null | undefined
): Promise<AfterSalesRequestRecord[]> {
  if (!records?.length) return [];
  const hydrated = await Promise.all(
    records.map((record) => decorateAfterSalesRequest(supabase, record))
  );
  return hydrated.filter((item): item is AfterSalesRequestRecord => Boolean(item));
}

export async function recordAfterSalesEvent(params: {
  supabase: SupabaseClient;
  requestId: string;
  actorRole: "user" | "merchant" | "platform" | "system";
  actorId?: string | null;
  action: string;
  note?: string;
  attachments?: string[];
  extra?: Record<string, unknown>;
}): Promise<void> {
  const { supabase, requestId, actorRole, actorId, action, note, attachments, extra } =
    params;
  const payload: Record<string, unknown> = { ...(extra ?? {}) };
  if (note) payload.note = note;
  if (attachments?.length) payload.attachments = attachments;
  await supabase.from("after_sales_events").insert({
    request_id: requestId,
    actor_role: actorRole,
    actor_id: actorId ?? null,
    action,
    payload,
  });
}

export async function issueAfterSalesRefund(params: {
  supabase: SupabaseClient;
  request: AfterSalesRequestRecord;
  reason?: string;
}): Promise<{
  refundId: string;
  amount: number;
  status: string;
  completedAt: string;
  isPreAuth: boolean;
}> {
  const { supabase, request, reason = "after_sale_post_redeem" } = params;

  const { data: order, error: orderError } = await supabase
    .from("orders")
    .select(
      "id, payment_intent_id, total_amount, is_captured, capture_method, user_id, status"
    )
    .eq("id", request.order_id)
    .single();

  if (orderError || !order) {
    throw new Error("Order not found for after-sales request");
  }
  if (!order.payment_intent_id) {
    throw new Error("Order missing payment_intent_id");
  }

  const amount = Number(request.refund_amount || order.total_amount || 0);
  if (!amount || Number.isNaN(amount)) {
    throw new Error("Invalid refund amount");
  }

  const now = new Date().toISOString();
  const isPreAuth =
    order.capture_method === "manual" && order.is_captured === false;
  let refundId = "pre_auth_cancelled";
  let refundStatus = "cancelled";

  if (!stripe) {
    throw new Error("Stripe secret key missing");
  }

  try {
    if (isPreAuth) {
      const cancelled = await stripe.paymentIntents.cancel(
        order.payment_intent_id
      );
      refundId = cancelled.id;
      refundStatus = cancelled.status ?? "cancelled";
    } else {
      const cents = Math.round(amount * 100);
      const refund = await stripe.refunds.create({
        payment_intent: order.payment_intent_id,
        amount: cents,
        reason: "requested_by_customer",
      });
      refundId = refund.id;
      refundStatus = refund.status ?? "succeeded";
    }
  } catch (err) {
    const message = err instanceof Error ? err.message : "Stripe refund failed";
    throw new Error(message);
  }

  await supabase
    .from("orders")
    .update({
      status: "refunded",
      refund_reason: reason,
      refunded_at: now,
      updated_at: now,
    })
    .eq("id", order.id);

  await supabase
    .from("payments")
    .update({
      status: "refunded",
      refund_amount: amount,
    })
    .eq("order_id", order.id);

  await supabase
    .from("coupons")
    .update({ status: "refunded" })
    .eq("id", request.coupon_id);

  return {
    refundId,
    amount,
    status: refundStatus,
    completedAt: now,
    isPreAuth,
  };
}
