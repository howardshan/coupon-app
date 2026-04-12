/**
 * 售后 Stripe 退款：单独文件 + 运行时动态 import Stripe，避免 platform-after-sales GET
 * 等路径在加载 _shared/after-sales.ts 时拉取 Node 兼容层（Deno.core.runMicrotasks 在 Edge 不可用）。
 */
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2?target=deno";
import type { AfterSalesRequestRecord } from "./after-sales.ts";

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

  const stripeSecret = Deno.env.get("STRIPE_SECRET_KEY") ?? "";
  if (!stripeSecret) {
    console.warn(
      "[after-sales-refund] STRIPE_SECRET_KEY is not configured; refund calls will fail",
    );
    throw new Error("Stripe secret key missing");
  }

  const { data: order, error: orderError } = await supabase
    .from("orders")
    .select(
      "id, payment_intent_id, total_amount, is_captured, capture_method, user_id, status",
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

  // 仅在执行退款时加载 Stripe，避免 Edge 冷启动 / GET 详情触发 std/node 微任务错误
  const Stripe = (await import("https://esm.sh/stripe@14?target=deno")).default;
  const stripe = new Stripe(stripeSecret, {
    apiVersion: "2024-04-10",
    httpClient: Stripe.createFetchHttpClient(),
  });

  try {
    if (isPreAuth) {
      const cancelled = await stripe.paymentIntents.cancel(
        order.payment_intent_id,
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
