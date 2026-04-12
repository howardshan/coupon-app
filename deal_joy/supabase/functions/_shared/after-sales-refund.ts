/**
 * 平台售后退款：与 create-refund 口径对齐
 * - 全额 Store Credit（payment_intent_id 以 store_credit_ 开头）：add_store_credit，不调 Stripe
 * - 混合支付：先退剩余 store credit 额度，再对卡部分 Stripe refund
 * - 纯卡 / 预授权：沿用原 Stripe 逻辑
 */
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2?target=deno";
import type { AfterSalesRequestRecord } from "./after-sales.ts";

type OrderRow = {
  id: string;
  payment_intent_id: string;
  total_amount: number;
  is_captured: boolean;
  capture_method: string | null;
  user_id: string;
  status: string;
  stripe_charge_id: string | null;
  store_credit_used: number | null;
};

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
      "id, payment_intent_id, total_amount, is_captured, capture_method, user_id, status, stripe_charge_id, store_credit_used",
    )
    .eq("id", request.order_id)
    .single();

  if (orderError || !order) {
    throw new Error("Order not found for after-sales request");
  }
  const o = order as OrderRow;
  if (!o.payment_intent_id) {
    throw new Error("Order missing payment_intent_id");
  }

  const { data: couponRow, error: couponErr } = await supabase
    .from("coupons")
    .select("order_item_id")
    .eq("id", request.coupon_id)
    .single();

  if (couponErr || !couponRow?.order_item_id) {
    throw new Error("Coupon or order_item_id not found");
  }
  const orderItemId = couponRow.order_item_id as string;

  const amount = Number(request.refund_amount || o.total_amount || 0);
  if (!amount || Number.isNaN(amount)) {
    throw new Error("Invalid refund amount");
  }

  const now = new Date().toISOString();
  const piStr = String(o.payment_intent_id);
  const isFullStoreCredit = piStr.startsWith("store_credit_");
  const storeCreditUsed = Number(o.store_credit_used ?? 0);

  const { data: refundedItems } = await supabase
    .from("order_items")
    .select("refund_credit_amount")
    .eq("order_id", o.id)
    .in("customer_status", ["refund_success", "refund_pending", "refund_processing"]);

  const alreadyRefundedCredit = (refundedItems ?? []).reduce(
    (sum: number, r: { refund_credit_amount: number | null }) =>
      sum + Number(r.refund_credit_amount ?? 0),
    0,
  );
  const remainingCredit = Math.max(0, storeCreditUsed - alreadyRefundedCredit);

  let creditRefundAmount = 0;
  let cardRefundAmount = 0;

  const isPreAuth =
    !isFullStoreCredit &&
    o.capture_method === "manual" &&
    o.is_captured === false;

  if (isFullStoreCredit) {
    // 全额余额支付：可退金额即申请金额（与订单已用余额一致）
    creditRefundAmount = Math.round(amount * 100) / 100;
    cardRefundAmount = 0;
  } else if (isPreAuth) {
    // 预授权整单取消：不走 store credit 拆分（与历史逻辑一致）
    creditRefundAmount = 0;
    cardRefundAmount = Math.round(amount * 100) / 100;
  } else {
    creditRefundAmount = Math.round(Math.min(remainingCredit, amount) * 100) / 100;
    cardRefundAmount = Math.round((amount - creditRefundAmount) * 100) / 100;
  }

  if (creditRefundAmount <= 0 && cardRefundAmount <= 0) {
    throw new Error("No refundable amount computed");
  }

  let refundId = "";
  let refundStatus = "succeeded";
  let isPreAuthFlag = false;

  // ── Stripe（卡部分或预授权）────────────────────────────────────────────
  if (cardRefundAmount > 0) {
    const stripeSecret = Deno.env.get("STRIPE_SECRET_KEY") ?? "";
    if (!stripeSecret) {
      throw new Error("Stripe secret key missing");
    }
    const Stripe = (await import("https://esm.sh/stripe@14?target=deno")).default;
    const stripe = new Stripe(stripeSecret, {
      apiVersion: "2024-04-10",
      httpClient: Stripe.createFetchHttpClient(),
    });

    try {
      if (isPreAuth) {
        isPreAuthFlag = true;
        const cancelled = await stripe.paymentIntents.cancel(o.payment_intent_id);
        refundId = cancelled.id;
        refundStatus = cancelled.status ?? "cancelled";
      } else {
        const refundParams: Record<string, unknown> = {
          amount: Math.round(cardRefundAmount * 100),
          reason: "requested_by_customer",
        };
        if (o.stripe_charge_id) {
          refundParams.charge = o.stripe_charge_id;
        } else {
          refundParams.payment_intent = o.payment_intent_id;
        }
        const refund = await stripe.refunds.create(refundParams as never);
        refundId = refund.id;
        refundStatus = refund.status ?? "succeeded";
      }
    } catch (err) {
      const message = err instanceof Error ? err.message : "Stripe refund failed";
      throw new Error(message);
    }
  }

  // ── Store Credit 退回 ─────────────────────────────────────────────────
  if (creditRefundAmount > 0) {
    const { error: rpcErr } = await supabase.rpc("add_store_credit", {
      p_user_id: o.user_id,
      p_amount: creditRefundAmount,
      p_order_item_id: orderItemId,
      p_description: reason,
    });
    if (rpcErr) {
      throw new Error(`add_store_credit failed: ${rpcErr.message}`);
    }
    if (!refundId) {
      refundId = `store_credit:${o.id.slice(0, 8)}`;
    } else {
      refundId = `${refundId}|sc:${creditRefundAmount}`;
    }
    refundStatus = "succeeded";
  }

  // ── 写回 order_items（与 execute-refund / create-refund 一致）──────────
  const refundMethod =
    cardRefundAmount > 0 ? "original_payment" : "store_credit";
  await supabase
    .from("order_items")
    .update({
      customer_status: "refund_success",
      refunded_at: now,
      refund_amount: amount,
      refund_credit_amount: creditRefundAmount,
      refund_method: refundMethod,
      refund_reason: reason,
      updated_at: now,
    })
    .eq("id", orderItemId);

  await supabase
    .from("orders")
    .update({
      status: "refunded",
      refund_reason: reason,
      refunded_at: now,
      updated_at: now,
    })
    .eq("id", o.id);

  await supabase
    .from("payments")
    .update({
      status: "refunded",
      refund_amount: amount,
    })
    .eq("order_id", o.id);

  await supabase
    .from("coupons")
    .update({ status: "refunded" })
    .eq("id", request.coupon_id);

  return {
    refundId: refundId || `after_sales:${request.id.slice(0, 8)}`,
    amount,
    status: refundStatus,
    completedAt: now,
    isPreAuth: isPreAuthFlag,
  };
}
