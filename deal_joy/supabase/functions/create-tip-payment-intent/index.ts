// Edge Function: create-tip-payment-intent
// POST body: { coupon_id, amount_cents, preset_choice?, signature_png_base64? }
// Auth: merchant JWT + X-Merchant-Id; requirePermission('scan'); trainee forbidden.

import Stripe from "npm:stripe@14.25.0";
// 勿用 ?target=deno：esm 会把 std/node polyfill 打进包，在 Edge Runtime 触发 Deno.core.runMicrotasks 不可用
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { decodeBase64 } from 'https://deno.land/std@0.224.0/encoding/base64.ts';
import {
  type AuthResult,
  resolveAuth,
  requirePermission,
} from '../_shared/auth.ts';

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
  apiVersion: '2024-04-10',
  httpClient: Stripe.createFetchHttpClient(),
});

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, x-merchant-id',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function err(message: string, code: string, status = 400) {
  return json({ error: code, message }, status);
}

/** P0: percent = up to 100% of base; fixed = up to max preset dollars. */
function validateTipAmountCents(params: {
  amountCents: number;
  tipsMode: string;
  baseCents: number;
  p1: number | null;
  p2: number | null;
  p3: number | null;
}): { ok: true } | { ok: false; message: string } {
  const { amountCents, tipsMode, baseCents, p1, p2, p3 } = params;
  if (!Number.isInteger(amountCents) || amountCents < 0) {
    return { ok: false, message: 'amount_cents must be a non-negative integer' };
  }
  if (amountCents === 0) {
    return { ok: false, message: 'amount_cents must be greater than zero for payment' };
  }
  if (baseCents <= 0) {
    return { ok: false, message: 'Cannot compute tip base for this coupon' };
  }

  if (tipsMode === 'percent') {
    const maxTip = baseCents;
    if (amountCents > maxTip) {
      return { ok: false, message: 'Tip exceeds maximum for percent mode (100% of purchase price)' };
    }
    return { ok: true };
  }
  if (tipsMode === 'fixed') {
    const presetCents = [p1, p2, p3]
      .filter((v): v is number => v != null && Number.isFinite(v))
      .map((v) => Math.round(v * 100));
    const maxFixed = presetCents.length > 0 ? Math.max(...presetCents) : baseCents;
    if (amountCents > maxFixed) {
      return { ok: false, message: 'Tip exceeds maximum for fixed presets' };
    }
    return { ok: true };
  }
  return { ok: false, message: 'Invalid tips_mode' };
}

function stripDataUrlBase64(input: string): string {
  const m = input.match(/^data:image\/png;base64,(.+)$/i);
  return m ? m[1]!.trim() : input.trim();
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'POST') {
    return err('Method not allowed', 'method_not_allowed', 405);
  }

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    return err('Missing authorization', 'unauthorized', 401);
  }

  // 尽早消费请求体，避免在多次 await（鉴权/查库）后再读 body 流导致长时间挂起
  let body: {
    coupon_id?: string;
    amount_cents?: number;
    preset_choice?: string;
    signature_png_base64?: string;
  };
  try {
    body = await req.json();
  } catch {
    return err('Invalid JSON body', 'invalid_request', 400);
  }
  console.log('[create-tip-payment-intent] body parsed');

  const supabaseAdmin = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  );

  const supabaseUser = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_ANON_KEY') ?? '',
    { global: { headers: { Authorization: authHeader } } },
  );

  const { data: { user }, error: authErr } = await supabaseUser.auth.getUser();
  if (authErr || !user) {
    return err('Invalid or expired token', 'unauthorized', 401);
  }

  let auth: AuthResult;
  try {
    auth = await resolveAuth(supabaseAdmin, user.id, req.headers);
  } catch (e) {
    return err((e as Error).message, 'unauthorized', 403);
  }
  requirePermission(auth, 'scan');

  if (auth.role === 'trainee') {
    return err('Trainee accounts cannot collect tips', 'forbidden', 403);
  }
  console.log('[create-tip-payment-intent] auth ok', { userId: user.id, merchantId: auth.merchantId });

  const couponId = body.coupon_id?.trim();
  const amountCents = body.amount_cents;
  if (!couponId) {
    return err('coupon_id is required', 'invalid_request', 400);
  }
  if (typeof amountCents !== 'number') {
    return err('amount_cents is required', 'invalid_request', 400);
  }

  console.log('[create-tip-payment-intent] start db + stripe', { couponId, amountCents });
  const { data: paidExists } = await supabaseAdmin
    .from('coupon_tips')
    .select('id')
    .eq('coupon_id', couponId)
    .eq('status', 'paid')
    .maybeSingle();

  if (paidExists) {
    return err('A tip has already been paid for this voucher', 'already_paid', 409);
  }

  // 防重：同一张券在短时间内已有 pending 时，不再重复创建 PI（避免多条 pending 卡住）
  const pendingWindowMs = 10 * 60 * 1000;
  const pendingSinceIso = new Date(Date.now() - pendingWindowMs).toISOString();
  const { data: recentPending } = await supabaseAdmin
    .from('coupon_tips')
    .select('id, stripe_payment_intent_id, created_at')
    .eq('coupon_id', couponId)
    .eq('status', 'pending')
    .gte('created_at', pendingSinceIso)
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle();
  if (recentPending) {
    return json({
      error: 'pending_exists',
      message: 'A pending tip request already exists for this voucher. Please wait and retry.',
      existing_tip_id: recentPending.id,
      existing_stripe_payment_intent_id: recentPending.stripe_payment_intent_id ?? null,
      retry_after_seconds: Math.ceil(pendingWindowMs / 1000),
    }, 409);
  }

  const { data: coupon, error: cErr } = await supabaseAdmin
    .from('coupons')
    .select(
      'id, status, deal_id, order_item_id, redeemed_at_merchant_id, redeemed_by_merchant_id',
    )
    .eq('id', couponId)
    .single();

  if (cErr || !coupon) {
    return err('Voucher not found', 'not_found', 404);
  }
  if (coupon.status !== 'used') {
    return err('Voucher must be redeemed before tipping', 'invalid_state', 400);
  }

  const redeemMerchantId = (coupon.redeemed_at_merchant_id ?? coupon.redeemed_by_merchant_id) as
    | string
    | null;
  if (!redeemMerchantId || redeemMerchantId !== auth.merchantId) {
    return err('Tip collection is only allowed at the store that redeemed this voucher', 'wrong_merchant', 403);
  }

  const { data: deal, error: dErr } = await supabaseAdmin
    .from('deals')
    .select(
      'id, tips_enabled, tips_mode, tips_preset_1, tips_preset_2, tips_preset_3, discount_price',
    )
    .eq('id', coupon.deal_id)
    .single();

  if (dErr || !deal) {
    return err('Deal not found', 'not_found', 404);
  }
  if (!deal.tips_enabled) {
    return err('Tips are not enabled for this deal', 'tips_disabled', 400);
  }
  const tipsMode = deal.tips_mode as string | null;
  if (tipsMode !== 'percent' && tipsMode !== 'fixed') {
    return err('Deal tips_mode is not configured', 'invalid_deal', 400);
  }

  let baseCents = 0;
  if (coupon.order_item_id) {
    const { data: oi } = await supabaseAdmin
      .from('order_items')
      .select('unit_price')
      .eq('id', coupon.order_item_id)
      .maybeSingle();
    const up = Number((oi as { unit_price?: number })?.unit_price ?? 0);
    baseCents = Math.round(up * 100);
  }
  if (baseCents <= 0) {
    const dp = Number(deal.discount_price ?? 0);
    baseCents = Math.round(dp * 100);
  }

  const p1 = deal.tips_preset_1 != null ? Number(deal.tips_preset_1) : null;
  const p2 = deal.tips_preset_2 != null ? Number(deal.tips_preset_2) : null;
  const p3 = deal.tips_preset_3 != null ? Number(deal.tips_preset_3) : null;

  const v = validateTipAmountCents({
    amountCents,
    tipsMode,
    baseCents,
    p1,
    p2,
    p3,
  });
  if (!v.ok) {
    return err(v.message, 'invalid_amount', 400);
  }

  const { data: merch } = await supabaseAdmin
    .from('merchants')
    .select('stripe_account_id')
    .eq('id', redeemMerchantId)
    .single();

  const connectId = (merch as { stripe_account_id?: string | null })?.stripe_account_id ?? null;
  if (!connectId) {
    return err('Merchant Stripe Connect is not ready', 'stripe_not_ready', 400);
  }

  const { data: tipRow, error: insErr } = await supabaseAdmin
    .from('coupon_tips')
    .insert({
      coupon_id: couponId,
      order_item_id: coupon.order_item_id,
      deal_id: coupon.deal_id,
      merchant_id: redeemMerchantId,
      payer_user_id: null,
      amount_cents: amountCents,
      currency: 'usd',
      tips_mode_snapshot: tipsMode,
      preset_choice: body.preset_choice ?? null,
      status: 'pending',
      signature_storage_path: null,
      created_by_merchant_user_id: user.id,
    })
    .select('id')
    .single();

  if (insErr || !tipRow) {
    console.error('[create-tip-payment-intent] insert coupon_tips', insErr);
    return err('Failed to create tip record', 'server_error', 500);
  }

  const tipId = tipRow.id as string;
  console.log('[create-tip-payment-intent] coupon_tips pending row', { tipId, couponId });

  if (body.signature_png_base64 && body.signature_png_base64.length > 0) {
    try {
      const raw = stripDataUrlBase64(body.signature_png_base64);
      const bytes = decodeBase64(raw);
      const path = `${redeemMerchantId}/${tipId}.png`;
      const { error: upErr } = await supabaseAdmin.storage
        .from('tip-signatures')
        .upload(path, bytes, { contentType: 'image/png', upsert: true });
      if (upErr) {
        console.error('[create-tip-payment-intent] signature upload failed', upErr);
        await supabaseAdmin.from('coupon_tips').update({ status: 'canceled' }).eq('id', tipId);
        return err('Failed to store signature', 'signature_upload_failed', 500);
      }
      await supabaseAdmin.from('coupon_tips').update({ signature_storage_path: path }).eq('id', tipId);
    } catch (e) {
      console.error('[create-tip-payment-intent] signature decode failed', e);
      await supabaseAdmin.from('coupon_tips').update({ status: 'canceled' }).eq('id', tipId);
      return err('Invalid signature_png_base64', 'invalid_signature', 400);
    }
  }

  try {
    console.log('[create-tip-payment-intent] calling Stripe paymentIntents.create', {
      amountCents,
      connectId: connectId ? `${connectId.slice(0, 8)}…` : null,
    });
    const pi = await stripe.paymentIntents.create({
      amount: amountCents,
      currency: 'usd',
      automatic_payment_methods: { enabled: true },
      application_fee_amount: 0,
      transfer_data: { destination: connectId },
      metadata: {
        type: 'tip',
        tip_id: tipId,
        coupon_id: couponId,
        order_item_id: coupon.order_item_id ?? '',
        merchant_id: redeemMerchantId,
      },
    });

    await supabaseAdmin
      .from('coupon_tips')
      .update({ stripe_payment_intent_id: pi.id })
      .eq('id', tipId);

    console.log('[create-tip-payment-intent] Stripe PI ok', { paymentIntentId: pi.id });
    return json({
      tip_id: tipId,
      client_secret: pi.client_secret,
      stripe_payment_intent_id: pi.id,
    });
  } catch (e) {
    console.error('[create-tip-payment-intent] Stripe PI failed', e);
    await supabaseAdmin.from('coupon_tips').update({ status: 'failed' }).eq('id', tipId);
    const msg = e instanceof Error ? e.message : 'Stripe error';
    return err(msg, 'stripe_error', 502);
  }
});
