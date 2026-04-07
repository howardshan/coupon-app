// Edge Function: submit-refund-dispute
// 已核销券（order_item.customer_status=used）在核销后 24h 内提交争议退款申请
// 每张券一条 refund_requests（order_item_id），商家审批 → 可选升级管理员 → execute-refund 执行 Store Credit
//
// 与 create-refund 区别：用户不能直接对 used 发起即时退款，必须走本接口。

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2?target=deno';

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
    const { orderItemId, reason } = body as {
      orderItemId?: string;
      reason?: string;
    };

    if (!orderItemId || typeof orderItemId !== 'string' || orderItemId.trim() === '') {
      return new Response(JSON.stringify({ error: 'orderItemId is required' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
    if (!reason || typeof reason !== 'string' || reason.trim().length < 10) {
      return new Response(JSON.stringify({ error: 'Reason must be at least 10 characters' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
    if (reason.trim().length > 500) {
      return new Response(JSON.stringify({ error: 'Reason must not exceed 500 characters' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: userData, error: userError } = await userClient.auth.getUser();
    if (userError || !userData?.user) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
    const userId = userData.user.id;

    const serviceClient = createClient(supabaseUrl, serviceRoleKey);

    const { data: item, error: itemErr } = await serviceClient
      .from('order_items')
      .select(`
        id,
        order_id,
        deal_id,
        unit_price,
        service_fee,
        tax_amount,
        customer_status,
        redeemed_at,
        redeemed_merchant_id,
        purchased_merchant_id,
        orders!inner ( user_id )
      `)
      .eq('id', orderItemId.trim())
      .single();

    if (itemErr || !item) {
      return new Response(JSON.stringify({ error: 'Order item not found' }), {
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const order = item.orders as { user_id: string };
    if (order.user_id !== userId) {
      return new Response(JSON.stringify({ error: 'Order item not found' }), {
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const cust = String(item.customer_status ?? '');
    if (cust !== 'used') {
      return new Response(
        JSON.stringify({
          error: `Only redeemed coupons can submit a dispute refund (current status: ${cust})`,
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const redeemedAtRaw = item.redeemed_at as string | null;
    if (!redeemedAtRaw) {
      return new Response(JSON.stringify({ error: 'Redemption time not found for this coupon' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const redeemedAt = new Date(redeemedAtRaw);
    const now = new Date();
    const hoursSince = (now.getTime() - redeemedAt.getTime()) / (1000 * 60 * 60);
    if (hoursSince > 24) {
      return new Response(
        JSON.stringify({
          error:
            'Dispute refund window expired (24 hours after redemption). Use After-sales within 7 days instead.',
          code: 'dispute_window_expired',
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const merchantId =
      (item.redeemed_merchant_id as string | null) ?? (item.purchased_merchant_id as string | null);
    if (!merchantId) {
      return new Response(JSON.stringify({ error: 'Merchant not found for this coupon' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const { data: pending } = await serviceClient
      .from('refund_requests')
      .select('id')
      .eq('order_item_id', orderItemId.trim())
      .in('status', ['pending_merchant', 'pending_admin'])
      .maybeSingle();

    if (pending) {
      return new Response(
        JSON.stringify({ error: 'A refund dispute is already pending for this coupon', requestId: pending.id }),
        { status: 409, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const unitPrice = Number(item.unit_price ?? 0);
    const serviceFee = Number(item.service_fee ?? 0);
    const taxAmount = Number(item.tax_amount ?? 0);
    const refundAmount = Math.round((unitPrice + serviceFee + taxAmount) * 100) / 100;

    const nowIso = now.toISOString();
    const trimmedReason = reason.trim();

    const { data: inserted, error: insertErr } = await serviceClient
      .from('refund_requests')
      .insert({
        order_id: item.order_id as string,
        order_item_id: orderItemId.trim(),
        user_id: userId,
        merchant_id: merchantId,
        status: 'pending_merchant',
        refund_amount: refundAmount,
        refund_method: 'store_credit',
        user_reason: trimmedReason,
        reason: trimmedReason,
        created_at: nowIso,
        updated_at: nowIso,
      })
      .select('id')
      .single();

    if (insertErr || !inserted) {
      console.error('[submit-refund-dispute] insert error:', insertErr);
      return new Response(JSON.stringify({ error: 'Failed to create refund request' }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    return new Response(
      JSON.stringify({
        refundRequestId: inserted.id,
        status: 'pending_merchant',
        message: 'Refund dispute submitted. The merchant will review your request.',
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  } catch (err) {
    console.error('[submit-refund-dispute] error:', err);
    return new Response(
      JSON.stringify({ error: err instanceof Error ? err.message : 'Unknown error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  }
});
