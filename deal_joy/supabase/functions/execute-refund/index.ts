// Edge Function: execute-refund (内部调用)
// 执行退款：order_item + store_credit 争议单走单笔入账；否则走 Stripe 整单 legacy 路径

import Stripe from 'https://esm.sh/stripe@14?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2?target=deno';

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
  apiVersion: '2024-04-10',
  httpClient: Stripe.createFetchHttpClient(),
});

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const body = await req.json();
    const { refundRequestId, approvedBy } = body as {
      refundRequestId?: string;
      approvedBy?: 'merchant' | 'admin';
    };

    if (!refundRequestId) {
      return new Response(
        JSON.stringify({ error: 'refundRequestId is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
    const serviceClient = createClient(supabaseUrl, serviceRoleKey);

    const { data: refundReq, error: rrError } = await serviceClient
      .from('refund_requests')
      .select(`
        id,
        order_id,
        order_item_id,
        refund_amount,
        status,
        refund_method,
        user_reason,
        orders(payment_intent_id, is_captured, total_amount, user_id)
      `)
      .eq('id', refundRequestId)
      .single();

    if (rrError || !refundReq) {
      return new Response(
        JSON.stringify({ error: 'Refund request not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    if (refundReq.status === 'completed') {
      return new Response(
        JSON.stringify({ success: true, message: 'Already completed' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const now = new Date().toISOString();
    const orderItemId = refundReq.order_item_id as string | null | undefined;
    const refundMethod = refundReq.refund_method as string | null | undefined;

    // ── 单笔 Store Credit（submit-refund-dispute + order_item_id）────────────────
    if (orderItemId && refundMethod === 'store_credit') {
      const order = refundReq.orders as {
        user_id: string;
      } | null;
      if (!order?.user_id) {
        return new Response(
          JSON.stringify({ error: 'Order user not found' }),
          { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
        );
      }

      const { data: line, error: lineErr } = await serviceClient
        .from('order_items')
        .select('id, order_id, stripe_transfer_id, stripe_transfer_amount')
        .eq('id', orderItemId)
        .single();

      if (lineErr || !line || line.order_id !== refundReq.order_id) {
        return new Response(
          JSON.stringify({ error: 'Order item mismatch' }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
        );
      }

      // Step 1: 把商家的 transfer 划回平台账户（store credit 资金由此来源）
      const scTransferId = line.stripe_transfer_id as string | null;
      const scTransferAmt = Number(line.stripe_transfer_amount ?? 0);
      if (scTransferId && scTransferAmt > 0) {
        try {
          await stripe.transfers.createReversal(scTransferId, {
            amount: Math.round(scTransferAmt * 100),
            metadata: { order_item_id: orderItemId, reason: 'store_credit_refund_dispute' },
          });
          console.log(`[execute-refund SC] Reversed $${scTransferAmt} from transfer ${scTransferId}`);
        } catch (reversalErr) {
          console.error('[execute-refund SC] Transfer reversal failed（不阻断）:', reversalErr);
        }
      }

      const refundAmount = Number(refundReq.refund_amount);
      const desc = String(refundReq.user_reason ?? '').trim() || 'Refund dispute approved';

      // Step 2: 发放 store credit
      const { error: rpcErr } = await serviceClient.rpc('add_store_credit', {
        p_user_id: order.user_id,
        p_amount: refundAmount,
        p_order_item_id: orderItemId,
        // 流水展示用固定短文案；完整理由保留在 order_items.refund_reason
        p_description: "Refund to Store Credit",
      });

      if (rpcErr) {
        console.error('[execute-refund] add_store_credit (item) error:', rpcErr);
        return new Response(
          JSON.stringify({ error: 'Failed to add store credit' }),
          { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
        );
      }

      await serviceClient
        .from('order_items')
        .update({
          customer_status: 'refund_success',
          refunded_at: now,
          refund_amount: refundAmount,
          refund_method: 'store_credit',
          refund_reason: desc,
          updated_at: now,
        })
        .eq('id', orderItemId);

      await serviceClient
        .from('coupons')
        .update({ status: 'refunded', updated_at: now })
        .eq('order_item_id', orderItemId);

      const decidedField = approvedBy === 'admin' ? 'admin_decided_at' : 'merchant_decided_at';
      await serviceClient
        .from('refund_requests')
        .update({
          status: 'completed',
          [decidedField]: now,
          updated_at: now,
        })
        .eq('id', refundRequestId);

      return new Response(
        JSON.stringify({
          success: true,
          mode: 'store_credit_item',
          refundAmount,
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // ── Legacy：整单 Stripe 退款（original_payment 或旧格式争议单）────────────
    const order = refundReq.orders as {
      payment_intent_id: string;
      is_captured: boolean;
      total_amount: number;
    } | null;
    if (!order) {
      return new Response(
        JSON.stringify({ error: 'Order not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // Step 1: 先 reverse 商家的 transfer，再从平台账户出退款给用户
    if (order.is_captured) {
      if (orderItemId) {
        // 有 order_item_id：reverse 该 item 的 transfer
        const { data: itemForRev } = await serviceClient
          .from('order_items')
          .select('stripe_transfer_id, stripe_transfer_amount')
          .eq('id', orderItemId)
          .single();
        const revTransferId = itemForRev?.stripe_transfer_id as string | null;
        const revTransferAmt = Number(itemForRev?.stripe_transfer_amount ?? 0);
        if (revTransferId && revTransferAmt > 0) {
          try {
            await stripe.transfers.createReversal(revTransferId, {
              amount: Math.round(revTransferAmt * 100),
              metadata: { order_item_id: String(orderItemId), reason: 'original_payment_refund_dispute' },
            });
            console.log(`[execute-refund] Reversed $${revTransferAmt} from transfer ${revTransferId}`);
          } catch (revErr) {
            console.error('[execute-refund] Transfer reversal failed（不阻断，需人工核查）:', revErr);
          }
        }
      } else {
        // 旧格式争议单：遍历订单下所有 item，reverse 各自的 transfer
        const { data: allItems } = await serviceClient
          .from('order_items')
          .select('id, stripe_transfer_id, stripe_transfer_amount')
          .eq('order_id', refundReq.order_id);
        for (const it of (allItems ?? [])) {
          const tid = it.stripe_transfer_id as string | null;
          const tamt = Number(it.stripe_transfer_amount ?? 0);
          if (tid && tamt > 0) {
            try {
              await stripe.transfers.createReversal(tid, {
                amount: Math.round(tamt * 100),
                metadata: { order_item_id: String(it.id), reason: 'execute_refund_legacy' },
              });
              console.log(`[execute-refund] Legacy reversed $${tamt} from transfer ${tid}`);
            } catch (revErr) {
              console.error('[execute-refund] Legacy transfer reversal failed:', revErr);
            }
          }
        }
      }
    }

    let refundId: string;
    let refundStatus: string;

    try {
      if (!order.is_captured) {
        const cancelled = await stripe.paymentIntents.cancel(order.payment_intent_id);
        refundId = cancelled.id;
        refundStatus = cancelled.status;
        console.log(`[execute-refund] cancelled pre-auth pi=${order.payment_intent_id}`);
      } else {
        // Step 2: 从平台账户退款给用户（transfer 已在上方 reverse，平台净出 = commission + stripe_fee + tax）
        const refundAmountCents = Math.round(Number(refundReq.refund_amount) * 100);
        const refund = await stripe.refunds.create({
          payment_intent: order.payment_intent_id,
          amount: refundAmountCents,
          reason: 'requested_by_customer',
        });
        refundId = refund.id;
        refundStatus = refund.status;
        console.log(`[execute-refund] stripe refund created refund=${refundId}`);
      }
    } catch (stripeErr) {
      const message = stripeErr instanceof Error ? stripeErr.message : 'Stripe refund failed';
      console.error('[execute-refund] stripe error:', message);
      return new Response(
        JSON.stringify({ error: message }),
        { status: 502, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const decidedField = approvedBy === 'admin' ? 'admin_decided_at' : 'merchant_decided_at';
    await serviceClient
      .from('refund_requests')
      .update({
        status: 'completed',
        [decidedField]: now,
        updated_at: now,
      })
      .eq('id', refundRequestId);

    await serviceClient
      .from('orders')
      .update({
        status: 'refunded',
        refunded_at: now,
        updated_at: now,
      })
      .eq('id', refundReq.order_id);

    await serviceClient
      .from('payments')
      .update({
        status: 'refunded',
        refund_amount: refundReq.refund_amount,
      })
      .eq('order_id', refundReq.order_id);

    await serviceClient
      .from('coupons')
      .update({ status: 'refunded' })
      .eq('order_id', refundReq.order_id);

    return new Response(
      JSON.stringify({
        success: true,
        refundId,
        refundStatus,
        amount: Number(refundReq.refund_amount),
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  } catch (err) {
    console.error('[execute-refund] error:', err);
    return new Response(
      JSON.stringify({ error: err instanceof Error ? err.message : 'Unknown error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  }
});
