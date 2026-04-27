// Edge Function: confirm-tip-payment-session
// POST body: { tip_id }
// Auth: 用户 JWT（非商户）；仅 coupon_tips.payer_user_id === auth.uid() 可获取 client_secret

import Stripe from "npm:stripe@14.25.0";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY") ?? "", {
  apiVersion: "2024-04-10",
  httpClient: Stripe.createFetchHttpClient(),
});

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function err(message: string, code: string, status = 400) {
  return json({ error: code, message }, status);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return err("Method not allowed", "method_not_allowed", 405);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return err("Missing authorization", "unauthorized", 401);
  }

  let body: { tip_id?: string };
  try {
    body = await req.json();
  } catch {
    return err("Invalid JSON body", "invalid_request", 400);
  }

  const tipId = body.tip_id?.trim();
  if (!tipId) {
    return err("tip_id is required", "invalid_request", 400);
  }

  const supabaseUser = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    { global: { headers: { Authorization: authHeader } } },
  );

  const { data: { user }, error: authErr } = await supabaseUser.auth.getUser();
  if (authErr || !user) {
    return err("Invalid or expired token", "unauthorized", 401);
  }

  const supabaseAdmin = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  const { data: tipRow, error: tipErr } = await supabaseAdmin
    .from("coupon_tips")
    .select("id, payer_user_id, status, stripe_payment_intent_id")
    .eq("id", tipId)
    .maybeSingle();

  if (tipErr || !tipRow) {
    return err("Tip not found", "not_found", 404);
  }

  const payerId = tipRow.payer_user_id as string | null;
  if (!payerId || payerId !== user.id) {
    return err("You are not authorized to confirm this tip payment", "forbidden", 403);
  }

  if (tipRow.status === "paid") {
    return json({ flow: "completed", tip_id: tipId });
  }

  const piId = tipRow.stripe_payment_intent_id as string | null;
  if (!piId) {
    return err("No payment session found for this tip", "no_payment_intent", 400);
  }

  let pi: Stripe.PaymentIntent;
  try {
    pi = await stripe.paymentIntents.retrieve(piId);
  } catch (e) {
    console.error("[confirm-tip-payment-session] retrieve PI", e);
    return err("Could not load payment session", "stripe_error", 502);
  }

  if (pi.status === "succeeded") {
    return json({
      flow: "completed",
      tip_id: tipId,
      stripe_payment_intent_id: pi.id,
    });
  }
  if (pi.status === "processing") {
    return json({
      flow: "processing",
      tip_id: tipId,
      stripe_payment_intent_id: pi.id,
    });
  }

  const allowed = new Set([
    "requires_action",
    "requires_confirmation",
    "requires_payment_method",
  ]);
  if (!allowed.has(pi.status)) {
    return err(
      `This payment cannot be completed in the app (status: ${pi.status})`,
      "invalid_pi_state",
      400,
    );
  }

  if (!pi.client_secret) {
    return err("Payment session is missing client secret", "missing_client_secret", 500);
  }

  return json({
    flow: "ready",
    tip_id: tipId,
    client_secret: pi.client_secret,
    stripe_payment_intent_id: pi.id,
  });
});
