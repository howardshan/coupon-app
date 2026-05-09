// account-delete：整账号 (full) / 仅商家身份 (merchant_only)
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import Stripe from "https://esm.sh/stripe@14?target=deno";
import { closeMerchantStore } from "../_shared/merchant_store_close.ts";

const PLACEHOLDER_USER_ID = "a0000001-0000-4000-8000-000000000001";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-merchant-id",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY") ?? "", {
  apiVersion: "2024-04-10",
  httpClient: Stripe.createFetchHttpClient(),
});

interface MerchantRoleSnapshot {
  brandAdmin: boolean;
  ownedMerchantIds: string[];
  staffMerchantIds: string[];
}

async function loadMerchantRoles(
  admin: ReturnType<typeof createClient>,
  userId: string,
): Promise<MerchantRoleSnapshot> {
  const { data: ba } = await admin.from("brand_admins").select("brand_id").eq(
    "user_id",
    userId,
  );
  const { data: owned } = await admin.from("merchants").select("id, status").eq(
    "user_id",
    userId,
  );
  const { data: staff } = await admin.from("merchant_staff").select("merchant_id")
    .eq("user_id", userId).eq("is_active", true);

  return {
    brandAdmin: (ba?.length ?? 0) > 0,
    ownedMerchantIds: (owned ?? []).map((r: { id: string }) => r.id),
    staffMerchantIds: (staff ?? []).map((r: { merchant_id: string }) =>
      r.merchant_id
    ),
  };
}

function hasAnyMerchantRole(s: MerchantRoleSnapshot): boolean {
  return s.brandAdmin || s.ownedMerchantIds.length > 0 ||
    s.staffMerchantIds.length > 0;
}

/** 商家侧清理：与商家计划 §4 一致 */
async function runMerchantCleanup(
  admin: ReturnType<typeof createClient>,
  userId: string,
  roles: MerchantRoleSnapshot,
): Promise<void> {
  if (roles.brandAdmin) {
    await admin.from("brand_admins").delete().eq("user_id", userId);
  }

  await admin.from("merchant_staff").delete().eq("user_id", userId);

  if (roles.ownedMerchantIds.length > 0) {
    const { data: stores } = await admin.from("merchants").select("id, status").in(
      "id",
      roles.ownedMerchantIds,
    );
    for (const m of stores ?? []) {
      const st = (m as { id: string; status: string }).status;
      if (st !== "closed") {
        await closeMerchantStore(
          admin,
          (m as { id: string }).id,
          userId,
        );
      }
    }
    await admin.from("merchants").update({ user_id: PLACEHOLDER_USER_ID }).eq(
      "user_id",
      userId,
    );
  }

  const merchantIdsForPush = [
    ...new Set([...roles.ownedMerchantIds, ...roles.staffMerchantIds]),
  ];
  if (merchantIdsForPush.length > 0) {
    await admin.from("merchant_fcm_tokens").delete().in(
      "merchant_id",
      merchantIdsForPush,
    );
  }
}

/** Gift：接收方删号时尽量将券退回赠送人（赠送人仍存在时） */
async function tryReturnGiftsToGifter(
  admin: ReturnType<typeof createClient>,
  userId: string,
): Promise<void> {
  const { data: coupons } = await admin
    .from("coupons")
    .select("id, gifted_from_user_id")
    .eq("current_holder_user_id", userId)
    .not("gifted_from_user_id", "is", null);

  for (const c of coupons ?? []) {
    const gid = (c as { gifted_from_user_id: string }).gifted_from_user_id;
    const { data: gifter } = await admin.from("users").select("id").eq("id", gid)
      .maybeSingle();
    if (gifter) {
      await admin.from("coupons").update({ current_holder_user_id: gid }).eq(
        "id",
        (c as { id: string }).id,
      );
    }
  }
}

/** 消费者未核销券：与闭店一致，标记 refund_requested 由既有 cron/流水线处理 */
async function markConsumerUnusedOrdersForRefund(
  admin: ReturnType<typeof createClient>,
  userId: string,
): Promise<void> {
  const orderIdSet = new Set<string>();
  const terminal = new Set([
    "refunded",
    "refund_requested",
    "voided",
    "refund_failed",
  ]);

  const { data: buyerOrders } = await admin.from("orders").select("id, status").eq(
    "user_id",
    userId,
  );
  const buyerCandid = (buyerOrders ?? [])
    .filter((o: { status: string }) => !terminal.has(o.status))
    .map((o: { id: string }) => o.id);
  if (buyerCandid.length > 0) {
    const { data: buyerItems } = await admin.from("order_items").select("order_id")
      .in("order_id", buyerCandid).in("customer_status", ["unused", "gifted"]);
    for (const it of buyerItems ?? []) {
      orderIdSet.add((it as { order_id: string }).order_id);
    }
  }

  const { data: heldCoupons } = await admin.from("coupons").select("order_id").eq(
    "current_holder_user_id",
    userId,
  );
  const heldOrderIds = [
    ...new Set((heldCoupons ?? []).map((c: { order_id: string }) => c.order_id)),
  ];
  if (heldOrderIds.length > 0) {
    const { data: heldItems } = await admin.from("order_items").select("order_id")
      .in("order_id", heldOrderIds).in("customer_status", ["unused", "gifted"]);
    const { data: heldOrders } = await admin.from("orders").select("id, status").in(
      "id",
      heldOrderIds,
    );
    const st = new Map(
      (heldOrders ?? []).map((r: { id: string; status: string }) => [r.id, r.status]),
    );
    for (const it of heldItems ?? []) {
      const oid = (it as { order_id: string }).order_id;
      const os = st.get(oid);
      if (os && !terminal.has(os)) orderIdSet.add(oid);
    }
  }

  if (orderIdSet.size === 0) return;

  const now = new Date().toISOString();
  const ids = [...orderIdSet];
  await admin.from("orders").update({
    status: "refund_requested",
    refund_reason: "account_deleted",
    refund_requested_at: now,
    updated_at: now,
  }).in("id", ids);

  await admin.from("coupons").update({ status: "refund_requested" }).in(
    "order_id",
    ids,
  );
}

async function cleanupStripeCustomer(
  admin: ReturnType<typeof createClient>,
  userId: string,
): Promise<void> {
  const { data: u } = await admin.from("users").select("stripe_customer_id").eq(
    "id",
    userId,
  ).maybeSingle();
  const cid = u?.stripe_customer_id as string | null | undefined;
  if (!cid) return;

  try {
    const pms = await stripe.paymentMethods.list({ customer: cid, type: "card" });
    for (const pm of pms.data) {
      try {
        await stripe.paymentMethods.detach(pm.id);
      } catch (e) {
        console.warn("[account-delete] detach PM", e);
      }
    }
    await stripe.customers.del(cid);
  } catch (e) {
    console.warn("[account-delete] Stripe customer delete", e);
    await admin.from("users").update({ stripe_customer_id: null }).eq("id", userId);
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false },
  });

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return json({ error: "Missing authorization header" }, 401);
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });

  const { data: { user }, error: authErr } = await userClient.auth.getUser();
  if (authErr || !user) {
    return json({ error: "Unauthorized" }, 401);
  }

  let body: { scope?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const scope = body.scope;
  if (scope !== "merchant_only" && scope !== "full") {
    return json({ error: 'scope must be "merchant_only" or "full"' }, 400);
  }

  const userId = user.id;

  try {
    const roles = await loadMerchantRoles(admin, userId);

    if (scope === "merchant_only") {
      if (!hasAnyMerchantRole(roles)) {
        return json({
          error:
            "No merchant identity found. Use the customer app to delete your full account, or sign in with a merchant account.",
          code: "no_merchant_identity",
        }, 400);
      }
      await runMerchantCleanup(admin, userId, roles);
      return json({
        success: true,
        scope: "merchant_only",
        message: "Merchant identity removed. You can still use the customer app.",
      });
    }

    // ----- full -----
    if (hasAnyMerchantRole(roles)) {
      await runMerchantCleanup(admin, userId, roles);
    }

    await tryReturnGiftsToGifter(admin, userId);
    await markConsumerUnusedOrdersForRefund(admin, userId);
    await cleanupStripeCustomer(admin, userId);

    const { error: rpcErr } = await admin.rpc("account_delete_reassign_all", {
      p_from: userId,
      p_to: PLACEHOLDER_USER_ID,
    });
    if (rpcErr) {
      console.error("[account-delete] rpc", rpcErr);
      return json({ error: `Data cleanup failed: ${rpcErr.message}` }, 500);
    }

    const { error: delErr } = await admin.auth.admin.deleteUser(userId);
    if (delErr) {
      console.error("[account-delete] auth delete", delErr);
      return json({ error: `Auth delete failed: ${delErr.message}` }, 500);
    }

    return json({
      success: true,
      scope: "full",
      message: "Account deleted",
    });
  } catch (e) {
    console.error("[account-delete]", e);
    return json({ error: (e as Error).message ?? "Internal error" }, 500);
  }
});
