import Stripe from 'https://esm.sh/stripe@14?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2?target=deno';
import { sendEmail, getAdminRecipients } from '../_shared/email.ts';
import { buildC7Email } from '../_shared/email-templates/customer/refund-requested.ts';
import { buildC6Email } from '../_shared/email-templates/customer/store-credit-added.ts';
import { buildM8Email } from '../_shared/email-templates/merchant/pre-redemption-refund.ts';
import { buildA4Email } from '../_shared/email-templates/admin/large-refund-alert.ts';

// 大额退款告警阈值（美元）
const LARGE_REFUND_THRESHOLD = 200;

/**
 * 计算本 order_item 应逆向的 Transfer 金额（美分）
 *
 * 原始 Transfer 总额 = sum(所有 item 的 merchant_net) - stripe_fee_estimate
 * 本 item 应逆向 = actualTransferCents × (item_merchant_net / total_merchant_net)
 *
 * 这样无论单张还是多张券，都不会超额逆向（Stripe fee 已在比例里摊薄）
 */
async function calcProportionalReversalCents(
  supabaseAdmin: ReturnType<typeof import('https://esm.sh/@supabase/supabase-js@2?target=deno').createClient>,
  orderId: string,
  itemMerchantNet: number,   // 本 item 的 merchant_net（美元）
  actualTransferCents: number, // Stripe PI expand 拿到的实际 transfer.amount（美分）
): Promise<number> {
  const { data: allItems } = await supabaseAdmin
    .from('order_items')
    .select('unit_price, commission_amount, promo_discount')
    .eq('order_id', orderId);

  const totalMerchantNet = (allItems ?? []).reduce((sum: number, it: Record<string, unknown>) => {
    return sum + (Number(it.unit_price ?? 0) - Number(it.commission_amount ?? 0) - Number(it.promo_discount ?? 0));
  }, 0);

  const proportion = totalMerchantNet > 0 ? itemMerchantNet / totalMerchantNet : 1;
  return Math.max(0, Math.round(actualTransferCents * proportion));
}

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
  apiVersion: '2024-04-10',
  httpClient: Stripe.createFetchHttpClient(),
});

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// ─── Stripe Reserves API 辅助函数 ────────────────────────────────────────────

/**
 * 释放 connected account 上的 ReserveHold
 * 退款前必须先释放，否则 reverse_transfer 可能因资金冻结而失败
 */
async function releaseReserveHold(
  connectedAccountId: string,
  holdId: string,
  stripeKey: string,
): Promise<void> {
  const body = new URLSearchParams({ reserve_hold: holdId });
  try {
    const res = await fetch('https://api.stripe.com/v1/reserve/releases', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${stripeKey}`,
        'Stripe-Version': '2025-08-27.preview',
        'Stripe-Account': connectedAccountId,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: body.toString(),
    });
    if (!res.ok) {
      const errText = await res.text();
      console.error(`[ReserveRelease] 释放失败 hold=${holdId}:`, errText);
    } else {
      console.log(`[ReserveRelease] 释放成功 hold=${holdId}`);
    }
  } catch (err) {
    console.error(`[ReserveRelease] 网络异常 hold=${holdId}:`, err);
  }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  // 热身请求：pg_cron 每 4 分钟调用，快速返回以保持函数热态
  if (req.headers.get('x-warmup') === 'true') {
    return new Response(JSON.stringify({ warmed: true }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
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
        tax_rate,
        commission_amount,
        stripe_fee_amount,
        promo_discount,
        purchased_merchant_id,
        stripe_reserve_hold_id,
        stripe_transfer_amount,
        stripe_transfer_id,
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

    // 退款资格：仅未使用券可走本函数即时退款；已核销须 submit-refund-dispute + 商家/平台审批后再由 execute-refund 入账
    if (customerStatus === 'used') {
      return new Response(
        JSON.stringify({
          error:
            'Redeemed coupons require merchant approval. Submit a refund dispute in the app within 24 hours of redemption.',
          code: 'use_submit_refund_dispute',
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    if (customerStatus !== 'unused') {
      return new Response(
        JSON.stringify({ error: `Cannot refund item with status: ${customerStatus}` }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const unitPrice = Number(item.unit_price ?? 0);
    const serviceFee = Number(item.service_fee ?? 0);
    const taxAmount = Number(item.tax_amount ?? 0);
    const taxRate = Number((item as any).tax_rate ?? 0);
    // 原路径退款只退 unit_price 部分的税，service fee 的税不退
    const unitPriceTax = taxRate > 0
      ? Math.round(unitPrice * taxRate * 100) / 100
      : taxAmount;
    // commission_amount：下单时快照的佣金，退款时退还给商家（via reverse_transfer）
    const commissionAmount = Number((item as any).commission_amount ?? 0);
    const promoDiscount = Number((item as any).promo_discount ?? 0);
    const now = new Date().toISOString();

    // 查询商家的 Stripe Connect 账户（用于 reverse_transfer）
    // purchased_merchant_id 优先；若无则通过 deal_id 查 merchant_id
    const merchantIdForRefund = (item as any).purchased_merchant_id ?? null;
    let merchantStripeAccountId: string | null = null;
    if (merchantIdForRefund) {
      const { data: merchantData } = await supabaseAdmin
        .from('merchants')
        .select('stripe_account_id, stripe_account_status')
        .eq('id', merchantIdForRefund)
        .single();
      if (merchantData?.stripe_account_status === 'connected' && merchantData.stripe_account_id) {
        merchantStripeAccountId = merchantData.stripe_account_id;
      }
    } else if ((item as any).deal_id) {
      // 兜底：通过 deal_id 查 merchant
      const { data: dealData } = await supabaseAdmin
        .from('deals')
        .select('merchant_id, merchants(stripe_account_id, stripe_account_status)')
        .eq('id', (item as any).deal_id)
        .single();
      const m = (dealData?.merchants as any);
      if (m?.stripe_account_status === 'connected' && m?.stripe_account_id) {
        merchantStripeAccountId = m.stripe_account_id;
      }
    }

    // 是否走 Stripe Connect 分账路径（Phase 1B 上线后的订单）
    const hasConnectRouting = !!merchantStripeAccountId && !isFullStoreCredit;

    if (refundMethod === 'store_credit') {
      // ── store_credit 退款流程 ──────────────────────────────────────────────
      // 退款金额包含 service fee 和 tax（平台承担手续费补偿用户，税款全额退还）
      const refundAmount = unitPrice + serviceFee + taxAmount;

      // Store Credit 分账路径预计算
      const storedTransferAmount = Number((item as any).stripe_transfer_amount ?? 0);
      const storedTransferId = (item as any).stripe_transfer_id as string | null;
      const isStoreCreditOrder = (order.payment_intent_id ?? '').startsWith('store_credit_');

      // 退款前：releaseReserveHold 与 PI retrieve 并行（两者互不依赖）
      const holdIdSC = (item as any).stripe_reserve_hold_id as string | null;
      const reservesEnabledSC = Deno.env.get('STRIPE_RESERVES_ENABLED') !== 'false';
      const stripeKey = Deno.env.get('STRIPE_SECRET_KEY') ?? '';

      const needsRetrieve = order.payment_intent_id && !isStoreCreditOrder;
      const [, piResult] = await Promise.allSettled([
        // releaseReserveHold（仅 Store Credit 订单无 transfer_id 时需要，SC 订单直接 reverse 不需提前 release）
        holdIdSC && merchantStripeAccountId && reservesEnabledSC
          ? releaseReserveHold(merchantStripeAccountId, holdIdSC, stripeKey)
          : Promise.resolve(),
        // paymentIntents.retrieve（仅刷卡订单需要）
        needsRetrieve
          ? stripe.paymentIntents.retrieve(order.payment_intent_id!, {
              expand: ['latest_charge.transfer'],
            })
          : Promise.resolve(null),
      ]);

      if (isStoreCreditOrder && storedTransferId && storedTransferAmount > 0) {
        // ── Store Credit 订单：直接用 stripe_transfer_id reverse ──
        try {
          const reversalCents = Math.round(storedTransferAmount * 100);
          await stripe.transfers.createReversal(storedTransferId, {
            amount: reversalCents,
            metadata: { order_item_id: orderItemId, reason: 'store_credit_refund' },
          });
          console.log(`[SC Refund] Reversed $${storedTransferAmount} from transfer ${storedTransferId}`);
        } catch (transferErr) {
          console.error('[SC Refund] Store Credit transfer reversal 失败:', transferErr);
        }
      } else if (needsRetrieve) {
        // ── 刷卡订单：使用已并行获取的 PI 数据 ──
        try {
          const pi = piResult.status === 'fulfilled' ? piResult.value : null;
          const transfer = (pi as any)?.latest_charge?.transfer;
          const transferId = typeof transfer === 'string' ? transfer : transfer?.id;

          if (transferId) {
            let reversalCents: number;

            if (storedTransferAmount > 0) {
              reversalCents = Math.round(storedTransferAmount * 100);
            } else {
              const transferAmountCents: number | null =
                transfer && typeof transfer === 'object' ? Number(transfer.amount) : null;
              if (transferAmountCents !== null && transferAmountCents > 0) {
                const itemMerchantNet = unitPrice - promoDiscount - commissionAmount;
                reversalCents = await calcProportionalReversalCents(
                  supabaseAdmin, order.id, itemMerchantNet, transferAmountCents,
                );
              } else {
                reversalCents = 0;
              }
            }

            if (reversalCents > 0) {
              await stripe.transfers.createReversal(transferId, {
                amount: reversalCents,
                metadata: { order_item_id: orderItemId, reason: 'store_credit_refund' },
              });
            }
          }
        } catch (transferErr) {
          console.error('SC 退款 transfer reversal 失败（不阻断，需人工核查）:', transferErr);
        }
      }

      // 调用 RPC 增加用户 store credit 余额
      const { error: rpcErr } = await supabaseAdmin.rpc('add_store_credit', {
        p_user_id: order.user_id,
        p_amount: refundAmount,
        p_order_item_id: orderItemId,
        p_description: reason?.trim() || "Refund to Store Credit",
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
      // 退款分配原则：
      //   - 退给用户：unitPrice + unitPriceTax（不退 service fee 及其税）
      //   - 从商家 Connect reverse：stripe_transfer_amount（商家实收部分）
      //   - 从平台出：commission + stripe_fee + unitPriceTax（这些钱在平台手里）
      //   - service fee 及其税不退

      const stripeFeeAmount = Number((item as any).stripe_fee_amount ?? 0);
      const itemRefundable = unitPrice + unitPriceTax; // 退给用户的总额（只含 unit_price 的税）

      // 混合支付时优先退 store credit
      let cardRefundAmount = itemRefundable;
      let creditRefundAmount = 0;

      if (isPartialStoreCredit && storeCreditUsed > 0) {
        const { data: refundedItems } = await supabaseAdmin
          .from('order_items')
          .select('refund_credit_amount')
          .eq('order_id', order.id)
          .in('customer_status', ['refund_success', 'refund_pending', 'refund_processing']);

        const alreadyRefundedCredit = (refundedItems ?? [])
          .reduce((sum: number, r: { refund_credit_amount: number | null }) =>
            sum + Number(r.refund_credit_amount ?? 0), 0);

        const remainingCredit = Math.max(0, storeCreditUsed - alreadyRefundedCredit);
        creditRefundAmount = Math.round(Math.min(remainingCredit, itemRefundable) * 100) / 100;
        cardRefundAmount = Math.round((itemRefundable - creditRefundAmount) * 100) / 100;
      }

      // 信用卡部分退款
      let stripeRefundId: string | null = null;
      if (cardRefundAmount > 0) {
        if (!order.stripe_charge_id && !order.payment_intent_id) {
          return new Response(
            JSON.stringify({ error: 'No Stripe payment found for this order' }),
            { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
          );
        }

        try {
          // ── Step 1: 从商家 Connect 账户 reverse 商家实收部分 ──
          // 只逆向 stripe_transfer_amount（商家的 net），其余（commission + stripe_fee + tax）由平台出
          // 两种路径：A. Store Credit 订单用 stripe_transfer_id 直接 reverse
          //           B. 刷卡订单通过 PI → charge → transfer 查 transfer ID
          const storedTransferAmountOP = Number((item as any).stripe_transfer_amount ?? 0);
          const storedTransferIdOP = (item as any).stripe_transfer_id as string | null;
          const isStoreCreditOrderOP = (order.payment_intent_id ?? '').startsWith('store_credit_');
          const holdIdOP = (item as any).stripe_reserve_hold_id as string | null;
          const reservesEnabledOP = Deno.env.get('STRIPE_RESERVES_ENABLED') !== 'false';
          const stripeKeyOP = Deno.env.get('STRIPE_SECRET_KEY') ?? '';

          // releaseReserveHold 与 PI retrieve 并行（两者互不依赖）
          const needsRetrieveOP = hasConnectRouting && order.payment_intent_id && !isStoreCreditOrderOP;
          const [, piOPResult] = await Promise.allSettled([
            holdIdOP && merchantStripeAccountId && reservesEnabledOP
              ? releaseReserveHold(merchantStripeAccountId, holdIdOP, stripeKeyOP)
              : Promise.resolve(),
            needsRetrieveOP
              ? stripe.paymentIntents.retrieve(order.payment_intent_id!, {
                  expand: ['latest_charge.transfer'],
                })
              : Promise.resolve(null),
          ]);

          if (isStoreCreditOrderOP && storedTransferIdOP && storedTransferAmountOP > 0) {
            // Store Credit 订单：直接用 stripe_transfer_id reverse
            try {
              const reversalCents = Math.round(storedTransferAmountOP * 100);
              await stripe.transfers.createReversal(storedTransferIdOP, {
                amount: reversalCents,
                metadata: { order_item_id: orderItemId, reason: 'original_payment_refund_sc' },
              });
              console.log(`[OP Refund] SC order reversed $${storedTransferAmountOP} from transfer ${storedTransferIdOP}`);
            } catch (reversalErr) {
              console.error('[OP Refund] SC transfer reversal failed:', reversalErr);
            }
          } else if (needsRetrieveOP) {
            // 刷卡订单：使用已并行获取的 PI 数据
            try {
              const piForReversal = piOPResult.status === 'fulfilled' ? piOPResult.value : null;
              const transferObj = (piForReversal as any)?.latest_charge?.transfer;
              const transferId = typeof transferObj === 'string' ? transferObj : transferObj?.id;

              if (transferId) {
                let reversalCents: number;

                if (storedTransferAmountOP > 0) {
                  reversalCents = Math.round(storedTransferAmountOP * 100);
                } else {
                  const actualTransferCents: number | null =
                    transferObj && typeof transferObj === 'object' ? Number(transferObj.amount) : null;
                  if (actualTransferCents !== null && actualTransferCents > 0) {
                    const itemMerchantNet = unitPrice - promoDiscount - commissionAmount;
                    reversalCents = await calcProportionalReversalCents(
                      supabaseAdmin, order.id, itemMerchantNet, actualTransferCents,
                    );
                  } else {
                    reversalCents = 0;
                  }
                }

                if (reversalCents > 0) {
                  await stripe.transfers.createReversal(transferId, {
                    amount: reversalCents,
                    metadata: {
                      order_item_id: orderItemId,
                      reason: 'original_payment_refund',
                      merchant_portion: reversalCents.toString(),
                      platform_portion: (Math.round(cardRefundAmount * 100) - reversalCents).toString(),
                    },
                  });
                  console.log(`[OP Refund] Reversed $${(reversalCents / 100).toFixed(2)} from merchant`);
                }
              }
            } catch (reversalErr) {
              console.error('[OP Refund] Transfer reversal failed:', reversalErr);
            }
          }

          // ── Step 2: 从平台 Stripe 账户退款给用户（不带 reverse_transfer） ──
          // 平台先 reverse 了商家的 transfer，再统一退给用户
          const refundParams: Record<string, unknown> = {
            amount: Math.round(cardRefundAmount * 100),
            metadata: {
              order_item_id: orderItemId,
              merchant_reversed: storedTransferAmountOP > 0 ? storedTransferAmountOP.toFixed(2) : 'proportional',
              platform_covered: (commissionAmount + stripeFeeAmount + taxAmount).toFixed(2),
            },
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
          p_description: reason?.trim() || "Partial refund to Store Credit",
        });
        if (rpcErr) {
          console.error('add_store_credit rpc error (partial refund):', rpcErr);
          // Store Credit 退回失败不阻断，但记录警告
        }
      }

      // 标记退款状态
      // 有 Stripe 退款则 refund_processing（等 webhook），纯 store credit 退回则直接 refund_success
      const refundStatus = stripeRefundId ? 'refund_processing' : 'refund_success';
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
