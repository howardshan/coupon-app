import Stripe from 'https://esm.sh/stripe@14?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2?target=deno';
import { sendEmail, getAdminRecipients } from '../_shared/email.ts';
import { buildC7Email } from '../_shared/email-templates/customer/refund-requested.ts';
import { buildC6Email } from '../_shared/email-templates/customer/store-credit-added.ts';
import { buildM8Email } from '../_shared/email-templates/merchant/pre-redemption-refund.ts';
import { buildA4Email } from '../_shared/email-templates/admin/large-refund-alert.ts';

// 大额退款告警阈值（美元）
const LARGE_REFUND_THRESHOLD = 200;

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
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'Unauthorized' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const body = await req.json();
    const { orderItemId, refundMethod, reason } = body;

    // 参数校验：orderItemId 必填
    if (!orderItemId || typeof orderItemId !== 'string' || orderItemId.trim() === '') {
      return new Response(
        JSON.stringify({ error: 'orderItemId is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // 参数校验：refundMethod 必填，只允许两种值
    if (refundMethod !== 'store_credit' && refundMethod !== 'original_payment') {
      return new Response(
        JSON.stringify({ error: 'refundMethod must be store_credit or original_payment' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // 防止 reason 超长（业务上限制 500 字符）
    if (reason !== undefined && reason !== null) {
      if (typeof reason !== 'string') {
        return new Response(
          JSON.stringify({ error: 'reason must be a string' }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
        );
      }
      if (reason.length > 500) {
        return new Response(
          JSON.stringify({ error: 'reason must not exceed 500 characters' }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
        );
      }
    }

    // 用户 JWT 客户端：用于查询 order_item，强制 RLS 行归属校验（确保只能退自己的券）
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: authHeader } } },
    );

    // Service role 客户端：绕过 RLS，用于写回 order_items / coupons 以及调用 RPC
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    );

    // 查询 order_item 以及关联 order 的信息
    // 通过用户 JWT 客户端查询，RLS 保证只能查到自己订单下的 item
    const { data: item, error: itemErr } = await supabase
      .from('order_items')
      .select(`
        id,
        deal_id,
        unit_price,
        service_fee,
        tax_amount,
        customer_status,
        orders!inner (
          id,
          user_id,
          stripe_charge_id,
          payment_intent_id,
          total_amount,
          store_credit_used
        )
      `)
      .eq('id', orderItemId)
      .single();

    if (itemErr || !item) {
      return new Response(
        JSON.stringify({ error: 'Order item not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const order = item.orders as {
      id: string;
      user_id: string;
      stripe_charge_id: string | null;
      payment_intent_id: string | null;
      total_amount: number;
      store_credit_used: number;
    };
    const customerStatus: string = item.customer_status ?? '';
    const storeCreditUsed = Number(order.store_credit_used ?? 0);
    const orderTotalAmount = Number(order.total_amount ?? 0);

    // 判断是否全额 Store Credit 支付（payment_intent_id 以 store_credit_ 开头）
    const isFullStoreCredit = (order.payment_intent_id ?? '').startsWith('store_credit_');
    // 判断是否混合支付（部分 Store Credit + 部分刷卡）
    const isPartialStoreCredit = !isFullStoreCredit && storeCreditUsed > 0;

    // 全额 Store Credit 支付时，不允许 original_payment 退款方式
    if (isFullStoreCredit && refundMethod === 'original_payment') {
      return new Response(
        JSON.stringify({ error: 'This order was fully paid with Store Credit. Please choose Store Credit refund.' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // 退款资格校验
    // - unused: 允许两种退款方式
    // - used: 核销后仅允许 store_credit（售后走线下）
    // - 其他状态（refund_success / refund_pending / expired 等）：拒绝
    if (customerStatus === 'used' && refundMethod === 'original_payment') {
      return new Response(
        JSON.stringify({ error: 'Used coupons can only be refunded via store credit' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    if (customerStatus !== 'unused' && customerStatus !== 'used') {
      return new Response(
        JSON.stringify({ error: `Cannot refund item with status: ${customerStatus}` }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const unitPrice = Number(item.unit_price ?? 0);
    const serviceFee = Number(item.service_fee ?? 0);
    // tax_amount：购买时收取的税款，退款时需要一并退还
    const taxAmount = Number(item.tax_amount ?? 0);
    const now = new Date().toISOString();

    if (refundMethod === 'store_credit') {
      // ── store_credit 退款流程 ──────────────────────────────────────────────
      // 退款金额包含 service fee 和 tax（平台承担手续费补偿用户，税款全额退还）
      const refundAmount = unitPrice + serviceFee + taxAmount;

      // 调用 RPC 增加用户 store credit 余额
      const { error: rpcErr } = await supabaseAdmin.rpc('add_store_credit', {
        p_user_id: order.user_id,
        p_amount: refundAmount,
        p_order_item_id: orderItemId,
        p_description: reason ?? 'Refund for order item',
      });

      if (rpcErr) {
        console.error('add_store_credit rpc error:', rpcErr);
        return new Response(
          JSON.stringify({ error: 'Failed to add store credit' }),
          { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
        );
      }

      // 更新 order_items
      await supabaseAdmin
        .from('order_items')
        .update({
          customer_status: 'refund_success',
          refunded_at: now,
          refund_amount: refundAmount,
          refund_method: 'store_credit',
          refund_reason: reason ?? null,
          updated_at: now,
        })
        .eq('id', orderItemId);

      // 将关联优惠券标记为已退款
      await supabaseAdmin
        .from('coupons')
        .update({ status: 'refunded', updated_at: now })
        .eq('order_item_id', orderItemId);

      // 发送邮件（真正的即发即忘，不 await，不阻断核心流程）
      (async () => {
        try {
          const { data: userInfo } = await supabaseAdmin
            .from('users').select('email').eq('id', order.user_id).single();
          const { data: dealInfo } = await supabaseAdmin
            .from('deals').select('title, merchant_id, merchants(name, user_id)').eq('id', (item as any).deal_id).single();
          const dealTitle = (dealInfo?.title as string | undefined);

          const emailPromises: Promise<void>[] = [];

          if (userInfo?.email) {
            const { subject: c6Subject, html: c6Html } = buildC6Email({ creditAmount: refundAmount, dealTitle });
            emailPromises.push(sendEmail(supabaseAdmin, {
              to: userInfo.email, subject: c6Subject, htmlBody: c6Html,
              emailCode: 'C6', referenceId: orderItemId, recipientType: 'customer', userId: order.user_id,
            }));

            const { subject: c7Subject, html: c7Html } = buildC7Email({ refundAmount, refundMethod: 'store_credit', dealTitle });
            emailPromises.push(sendEmail(supabaseAdmin, {
              to: userInfo.email, subject: c7Subject, htmlBody: c7Html,
              emailCode: 'C7', referenceId: orderItemId, recipientType: 'customer', userId: order.user_id,
            }));
          }

          if (customerStatus === 'unused') {
            const merchantData = (dealInfo as any)?.merchants;
            const merchantUserId = merchantData?.user_id as string | null;
            const merchantName   = (merchantData?.name as string | undefined) ?? '';
            if (merchantUserId) {
              const { data: merchantUser } = await supabaseAdmin
                .from('users').select('email').eq('id', merchantUserId).single();
              const { data: merchantRow } = await supabaseAdmin
                .from('merchants').select('id').eq('user_id', merchantUserId).single();
              if (merchantUser?.email) {
                const { subject: m8Subject, html: m8Html } = buildM8Email({ merchantName, dealTitle, refundAmount });
                emailPromises.push(sendEmail(supabaseAdmin, {
                  to: merchantUser.email, subject: m8Subject, htmlBody: m8Html,
                  emailCode: 'M8', referenceId: orderItemId, recipientType: 'merchant',
                  merchantId: (merchantRow as any)?.id,
                }));
              }
            }
          }

          if (refundAmount >= LARGE_REFUND_THRESHOLD) {
            const adminEmails = await getAdminRecipients(supabaseAdmin, 'A4');
            if (adminEmails.length > 0) {
              const { subject: a4Subject, html: a4Html } = buildA4Email({
                orderId: (item as any).order_id ?? orderItemId,
                refundAmount, refundMethod: 'store_credit',
                dealTitle, threshold: LARGE_REFUND_THRESHOLD,
              });
              emailPromises.push(sendEmail(supabaseAdmin, {
                to: adminEmails, subject: a4Subject, htmlBody: a4Html,
                emailCode: 'A4', referenceId: orderItemId, recipientType: 'admin',
              }));
            }
          }

          await Promise.allSettled(emailPromises);
        } catch (emailErr) {
          console.error('create-refund: email error (store_credit):', emailErr);
        }
      })();

      return new Response(
        JSON.stringify({
          success: true,
          refundMethod: 'store_credit',
          refundAmount,
          status: 'refund_success',
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );

    } else {
      // ── original_payment 退款流程 ─────────────────────────────────────────
      // 退款商品价 + 税，不含 service fee（service fee 不退）
      const itemRefundable = unitPrice + taxAmount;

      // 混合支付时优先退 store credit：先退完 credit 部分，剩余退信用卡
      let cardRefundAmount = itemRefundable;
      let creditRefundAmount = 0;

      if (isPartialStoreCredit && storeCreditUsed > 0) {
        // 查询该订单下已退款 items 中已退还的 store credit 总额
        const { data: refundedItems } = await supabaseAdmin
          .from('order_items')
          .select('refund_credit_amount')
          .eq('order_id', order.id)
          .in('customer_status', ['refund_success', 'refund_pending']);

        const alreadyRefundedCredit = (refundedItems ?? [])
          .reduce((sum: number, r: { refund_credit_amount: number | null }) =>
            sum + Number(r.refund_credit_amount ?? 0), 0);

        // 剩余可退的 store credit 额度
        const remainingCredit = Math.max(0, storeCreditUsed - alreadyRefundedCredit);
        // 优先退 store credit，不超过本 item 的可退金额
        creditRefundAmount = Math.round(Math.min(remainingCredit, itemRefundable) * 100) / 100;
        cardRefundAmount = Math.round((itemRefundable - creditRefundAmount) * 100) / 100;
      }

      // 信用卡部分退款（如果有的话）
      let stripeRefundId: string | null = null;
      if (cardRefundAmount > 0) {
        if (!order.stripe_charge_id && !order.payment_intent_id) {
          return new Response(
            JSON.stringify({ error: 'No Stripe payment found for this order' }),
            { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
          );
        }

        try {
          // 向 Stripe 发起信用卡部分退款
          const refundParams: Record<string, unknown> = {
            amount: Math.round(cardRefundAmount * 100),
            metadata: { order_item_id: orderItemId },
          };
          if (order.stripe_charge_id) {
            refundParams.charge = order.stripe_charge_id;
          } else {
            refundParams.payment_intent = order.payment_intent_id;
          }
          const refund = await stripe.refunds.create(refundParams as any);
          stripeRefundId = refund.id;
        } catch (stripeErr: unknown) {
          const message = stripeErr instanceof Error ? stripeErr.message : 'Stripe refund failed';
          console.error('Stripe refund error:', stripeErr);
          return new Response(
            JSON.stringify({ error: message }),
            { status: 502, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
          );
        }
      }

      // Store Credit 部分退回余额（混合支付时）
      if (creditRefundAmount > 0) {
        const { error: rpcErr } = await supabaseAdmin.rpc('add_store_credit', {
          p_user_id: order.user_id,
          p_amount: creditRefundAmount,
          p_order_item_id: orderItemId,
          p_description: reason ?? 'Partial refund (store credit portion)',
        });
        if (rpcErr) {
          console.error('add_store_credit rpc error (partial refund):', rpcErr);
          // Store Credit 退回失败不阻断，但记录警告
        }
      }

      // 标记退款状态
      // 有 Stripe 退款则 refund_pending（等 webhook），纯 store credit 退回则直接 refund_success
      const refundStatus = stripeRefundId ? 'refund_pending' : 'refund_success';
      const totalRefundAmount = cardRefundAmount + creditRefundAmount;

      await supabaseAdmin
        .from('order_items')
        .update({
          customer_status: refundStatus,
          refunded_at: refundStatus === 'refund_success' ? now : null,
          refund_amount: totalRefundAmount,
          refund_credit_amount: creditRefundAmount, // 记录本 item 退了多少 store credit
          refund_method: 'original_payment',
          refund_reason: reason ?? null,
          updated_at: now,
        })
        .eq('id', orderItemId);

      // 将关联优惠券标记为已退款
      await supabaseAdmin
        .from('coupons')
        .update({ status: 'refunded', updated_at: now })
        .eq('order_item_id', orderItemId);

      // 发送邮件（真正的即发即忘，不 await，不阻断核心流程）
      (async () => {
        try {
          const { data: userInfo } = await supabaseAdmin
            .from('users').select('email').eq('id', order.user_id).single();
          const { data: dealInfo } = await supabaseAdmin
            .from('deals').select('title, merchant_id, merchants(name, user_id)').eq('id', (item as any).deal_id).single();
          const dealTitle = (dealInfo?.title as string | undefined);

          const emailPromises: Promise<void>[] = [];

          if (userInfo?.email) {
            const { subject: c7Subject, html: c7Html } = buildC7Email({ refundAmount: totalRefundAmount, refundMethod: 'original_payment', dealTitle });
            emailPromises.push(sendEmail(supabaseAdmin, {
              to: userInfo.email, subject: c7Subject, htmlBody: c7Html,
              emailCode: 'C7', referenceId: orderItemId, recipientType: 'customer', userId: order.user_id,
            }));
          }

          const merchantData = (dealInfo as any)?.merchants;
          const merchantUserId = merchantData?.user_id as string | null;
          const merchantName   = (merchantData?.name as string | undefined) ?? '';
          if (merchantUserId) {
            const { data: merchantUser } = await supabaseAdmin
              .from('users').select('email').eq('id', merchantUserId).single();
            const { data: merchantRow } = await supabaseAdmin
              .from('merchants').select('id').eq('user_id', merchantUserId).single();
            if (merchantUser?.email) {
              const { subject: m8Subject, html: m8Html } = buildM8Email({ merchantName, dealTitle, refundAmount: totalRefundAmount });
              emailPromises.push(sendEmail(supabaseAdmin, {
                to: merchantUser.email, subject: m8Subject, htmlBody: m8Html,
                emailCode: 'M8', referenceId: orderItemId, recipientType: 'merchant',
                merchantId: (merchantRow as any)?.id,
              }));
            }
          }

          if (totalRefundAmount >= LARGE_REFUND_THRESHOLD) {
            const adminEmails = await getAdminRecipients(supabaseAdmin, 'A4');
            if (adminEmails.length > 0) {
              const { subject: a4Subject, html: a4Html } = buildA4Email({
                orderId: (item as any).order_id ?? orderItemId,
                refundAmount: totalRefundAmount, refundMethod: 'original_payment',
                dealTitle, threshold: LARGE_REFUND_THRESHOLD,
              });
              emailPromises.push(sendEmail(supabaseAdmin, {
                to: adminEmails, subject: a4Subject, htmlBody: a4Html,
                emailCode: 'A4', referenceId: orderItemId, recipientType: 'admin',
              }));
            }
          }

          await Promise.allSettled(emailPromises);
        } catch (emailErr) {
          console.error('create-refund: email error (original_payment):', emailErr);
        }
      })();

      return new Response(
        JSON.stringify({
          success: true,
          refundMethod: 'original_payment',
          refundAmount: totalRefundAmount,
          cardRefundAmount,
          creditRefundAmount,
          stripeRefundId,
          status: refundStatus,
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

  } catch (err) {
    console.error('create-refund error:', err);
    return new Response(
      JSON.stringify({ error: err instanceof Error ? err.message : 'Unknown error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  }
});
