// auto-refund-expired: 过期券自动退款 Edge Function（Order System V3）
// 由 Supabase Cron Job 定期触发（建议每小时一次）
//
// V3 逻辑：
//   基于 order_items + coupons 查找过期未使用的券，
//   原路退回 Stripe（不退 service_fee），
//   无 Stripe 支付信息时回退到 store credit。
//
// 退款金额 = unit_price + tax_amount（退商品价+税，手续费不退）
// 混合支付：与同单 create-refund 一致，先退满本单应付的 store credit 部分，剩余再走 Stripe
// Stripe 已发起：customer_status = 'refund_processing'（等 webhook）；人工审核仍为 refund_review / refund_pending
// 更新 coupons: status = 'expired'

import { createClient } from 'npm:@supabase/supabase-js@2';
import { sendEmail } from '../_shared/email.ts';
import { buildC5Email } from '../_shared/email-templates/customer/auto-refund.ts';

const STRIPE_SECRET_KEY = Deno.env.get('STRIPE_SECRET_KEY') ?? '';
const STRIPE_API_BASE = 'https://api.stripe.com/v1';

// CORS 响应头
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// 单次最多处理条数，防止单次执行超时
const BATCH_SIZE = 50;

// Cron 调用方共享密钥（在 Supabase Dashboard > Secrets 中配置 CRON_SECRET）
const CRON_SECRET = Deno.env.get('CRON_SECRET');

function isAlreadyRefundedError(message: string): boolean {
  return /already been refunded|charge_already_refunded/i.test(message);
}

/** 本单已退款 items 累计退回的 store credit（与 create-refund 口径一致） */
async function sumAlreadyRefundedCreditForOrder(
  supabaseAdmin: ReturnType<typeof createClient>,
  orderId: string,
): Promise<number> {
  const { data: rows } = await supabaseAdmin
    .from('order_items')
    .select('refund_credit_amount')
    .eq('order_id', orderId)
    .in('customer_status', ['refund_success', 'refund_pending', 'refund_processing']);

  return (rows ?? []).reduce(
    (sum, r: { refund_credit_amount: number | null }) => sum + Number(r.refund_credit_amount ?? 0),
    0,
  );
}

async function stripeCreateRefund(params: {
  amount: number;
  charge?: string;
  payment_intent?: string;
  metadata: Record<string, string>;
}): Promise<{ id?: string }> {
  if (!STRIPE_SECRET_KEY) {
    throw new Error('STRIPE_SECRET_KEY is not configured');
  }

  const form = new URLSearchParams();
  form.set('amount', String(params.amount));
  if (params.charge) form.set('charge', params.charge);
  if (params.payment_intent) form.set('payment_intent', params.payment_intent);
  for (const [key, value] of Object.entries(params.metadata)) {
    form.set(`metadata[${key}]`, value);
  }

  const res = await fetch(`${STRIPE_API_BASE}/refunds`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${STRIPE_SECRET_KEY}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: form.toString(),
  });

  const json = await res.json() as {
    id?: string;
    error?: { message?: string };
  };

  if (!res.ok) {
    throw new Error(json.error?.message ?? `Stripe refund failed with status ${res.status}`);
  }

  return { id: json.id };
}

Deno.serve(async (req) => {
  // 处理 CORS 预检请求
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  // -------------------------------------------------------------
  // 调用方身份验证：若配置了 CRON_SECRET 则校验请求头
  // -------------------------------------------------------------
  if (CRON_SECRET) {
    const incomingSecret = req.headers.get('x-cron-secret');
    if (incomingSecret !== CRON_SECRET) {
      return new Response(
        JSON.stringify({ error: 'Unauthorized' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }
  }

  // Service role 客户端：绕过 RLS，读写所有行
  const supabaseAdmin = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  );

  // 汇总结果，返回给调用方
  const summary = {
    processed: 0,
    succeeded: 0,
    failed: 0,
    errors: [] as Array<{ orderItemId: string; error: string }>,
  };

  try {
    // -------------------------------------------------------------
    // 查找过期未使用的 order_items
    // 条件：customer_status = 'unused' 且关联 coupon 已过期
    // 每批最多处理 BATCH_SIZE 条
    // -------------------------------------------------------------
    const { data: expiredItems, error: queryError } = await supabaseAdmin.rpc(
      'get_expired_order_items',
      { p_limit: BATCH_SIZE },
    );

    // 若 RPC 不存在则回退到直接 SQL 查询
    let items: Array<{
      id: string;
      order_id: string;
      user_id: string;
      unit_price: number;
      service_fee: number;
      tax_amount: number;
      coupon_id: string;
      expires_at: string;
      stripe_charge_id: string | null;
      payment_intent_id: string | null;
      store_credit_used: number;
      customer_status: string;
      deal_id: string;
    }>;

    if (queryError) {
      // RPC 不可用时，直接通过 supabase-js 多表查询
      console.warn('auto-refund-expired: RPC get_expired_order_items 不可用，使用 fallback 查询', queryError.message);

      const { data: rawItems, error: rawErr } = await supabaseAdmin
        .from('order_items')
        .select(`
          id,
          order_id,
          deal_id,
          customer_status,
          unit_price,
          service_fee,
          tax_amount,
          coupon_id,
          coupons!inner ( id, expires_at ),
          orders!inner ( user_id, stripe_charge_id, payment_intent_id, store_credit_used )
        `)
        .in('customer_status', ['unused', 'gifted'])
        .lt('coupons.expires_at', new Date().toISOString())
        .limit(BATCH_SIZE);

      if (rawErr) {
        throw new Error(`查询过期 order_items 失败: ${rawErr.message}`);
      }

      // 把嵌套结构展开
      items = (rawItems ?? []).map((row: Record<string, unknown>) => {
        const coupon = row.coupons as Record<string, unknown> | null;
        const order = row.orders as Record<string, unknown> | null;
        return {
          id: row.id as string,
          order_id: row.order_id as string,
          user_id: (order?.user_id ?? '') as string,
          unit_price: (row.unit_price ?? 0) as number,
          service_fee: (row.service_fee ?? 0) as number,
          // tax_amount：购买时收取的税款，退款时需要一并退还
          tax_amount: (row.tax_amount ?? 0) as number,
          coupon_id: (coupon?.id ?? row.coupon_id ?? '') as string,
          expires_at: (coupon?.expires_at ?? '') as string,
          stripe_charge_id: (order?.stripe_charge_id ?? null) as string | null,
          payment_intent_id: (order?.payment_intent_id ?? null) as string | null,
          store_credit_used: Number((order as Record<string, unknown>)?.store_credit_used ?? 0),
          customer_status: (row.customer_status ?? 'unused') as string,
          deal_id: (row.deal_id ?? '') as string,
        };
      });
    } else {
      // RPC 返回含 store_credit_used（见 migration get_expired_order_items）
      items = (expiredItems ?? []) as typeof items;
    }

    if (!items || items.length === 0) {
      console.log('auto-refund-expired: 没有找到过期待处理的 order_items');
      return new Response(
        JSON.stringify({ ...summary, message: 'No expired order items found' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    console.log(`auto-refund-expired: 找到 ${items.length} 个过期待退款 order_item`);
    summary.processed = items.length;

    // -------------------------------------------------------------
    // 逐条处理，单条失败不中断批次
    // -------------------------------------------------------------
    for (const item of items) {
      const itemId = item.id;

      try {
        const now = new Date().toISOString();
        // 退款金额 = unit_price + tax_amount（退商品价+税，手续费不退）
        const refundAmount = Number(item.unit_price ?? 0) + Number(item.tax_amount ?? 0);

        // 1. 先将 coupon 标记为 expired
        if (item.coupon_id) {
          const { error: couponErr } = await supabaseAdmin
            .from('coupons')
            .update({ status: 'expired' })
            .eq('id', item.coupon_id);

          if (couponErr) {
            console.warn(`auto-refund-expired: coupon ${item.coupon_id} 状态更新失败`, couponErr.message);
          }
        }

        // 2. 退款：纯 Store Credit 订单 / 无卡信息 → 仅 SC；否则先 SC 份额再 Stripe（与 create-refund 一致）
        const chargeId = item.stripe_charge_id;
        const piId = item.payment_intent_id;
        const piStr = piId ?? '';
        const isFullStoreCredit = piStr.startsWith('store_credit_');
        const storeCreditUsed = Number(item.store_credit_used ?? 0);

        if (isFullStoreCredit || (!chargeId && !piId)) {
          console.log(`auto-refund-expired: item=${itemId} 全额/无卡支付，退 store credit`);
          await fallbackToStoreCredit(supabaseAdmin, item, itemId, refundAmount, now);
          summary.succeeded += 1;
        } else {
          let creditRefundAmount = 0;
          let cardRefundAmount = refundAmount;

          if (storeCreditUsed > 0 && !isFullStoreCredit) {
            const alreadyRefundedCredit = await sumAlreadyRefundedCreditForOrder(supabaseAdmin, item.order_id);
            const remainingCredit = Math.max(0, storeCreditUsed - alreadyRefundedCredit);
            creditRefundAmount = Math.round(Math.min(remainingCredit, refundAmount) * 100) / 100;
            cardRefundAmount = Math.round((refundAmount - creditRefundAmount) * 100) / 100;
          }

          if (creditRefundAmount > 0) {
            const { error: creditErr } = await supabaseAdmin.rpc('add_store_credit', {
              p_user_id: item.user_id,
              p_amount: creditRefundAmount,
              p_order_item_id: itemId,
              p_description: `Auto refund (store credit portion) for expired coupon (order_item: ${itemId})`,
            });
            if (creditErr) {
              throw new Error(`add_store_credit 失败: ${creditErr.message}`);
            }
            console.log(
              `auto-refund-expired: item=${itemId} 已退 store credit 部分 ${creditRefundAmount}，待卡部分 ${cardRefundAmount}`,
            );
          }

          if (cardRefundAmount <= 0) {
            const { error: itemUpdateErr } = await supabaseAdmin
              .from('order_items')
              .update({
                customer_status: 'refund_success',
                refunded_at: now,
                refund_amount: refundAmount,
                refund_credit_amount: creditRefundAmount,
                refund_method: 'store_credit',
                refund_reason: 'auto_expired',
                updated_at: now,
              })
              .eq('id', itemId);

            if (itemUpdateErr) {
              throw new Error(`更新 order_items 状态失败: ${itemUpdateErr.message}`);
            }
            summary.succeeded += 1;
          } else {
            try {
              const refundParams: {
                amount: number;
                metadata: Record<string, string>;
                charge?: string;
                payment_intent?: string;
              } = {
                amount: Math.round(cardRefundAmount * 100),
                metadata: { order_item_id: itemId, reason: 'auto_expired' },
              };
              if (chargeId) refundParams.charge = chargeId;
              else refundParams.payment_intent = piId!;

              const stripeRefund = await stripeCreateRefund(refundParams);
              console.log(`auto-refund-expired: Stripe 卡部分退款成功 refund_id=${stripeRefund.id} item=${itemId}`);

              const { error: itemUpdateErr } = await supabaseAdmin
                .from('order_items')
                .update({
                  customer_status: 'refund_processing',
                  refund_amount: refundAmount,
                  refund_credit_amount: creditRefundAmount,
                  refund_method: 'original_payment',
                  refund_reason: 'auto_expired',
                  updated_at: now,
                })
                .eq('id', itemId);

              if (itemUpdateErr) {
                throw new Error(`更新 order_items 状态失败: ${itemUpdateErr.message}`);
              }

              summary.succeeded += 1;
            } catch (stripeErr: unknown) {
              const stripeMsg = stripeErr instanceof Error ? stripeErr.message : String(stripeErr);
              if (isAlreadyRefundedError(stripeMsg)) {
                console.log(`auto-refund-expired: item=${itemId} Stripe 显示卡部分已退款，同步成功`);
                const { error: itemUpdateErr } = await supabaseAdmin
                  .from('order_items')
                  .update({
                    customer_status: 'refund_success',
                    refunded_at: now,
                    refund_amount: refundAmount,
                    refund_credit_amount: creditRefundAmount,
                    refund_method: 'original_payment',
                    refund_reason: 'auto_expired',
                    updated_at: now,
                  })
                  .eq('id', itemId);

                if (itemUpdateErr) {
                  throw new Error(`更新 order_items 状态失败: ${itemUpdateErr.message}`);
                }
                summary.succeeded += 1;
              } else {
                console.warn(`auto-refund-expired: item=${itemId} Stripe 卡部分失败，差额改退 SC: ${stripeMsg}`);
                const { error: creditErr2 } = await supabaseAdmin.rpc('add_store_credit', {
                  p_user_id: item.user_id,
                  p_amount: cardRefundAmount,
                  p_order_item_id: itemId,
                  p_description: `Auto refund (card fallback to store credit) for expired coupon (order_item: ${itemId})`,
                });
                if (creditErr2) {
                  throw new Error(`add_store_credit 失败: ${creditErr2.message}`);
                }

                const { error: itemUpdateErr } = await supabaseAdmin
                  .from('order_items')
                  .update({
                    customer_status: 'refund_success',
                    refunded_at: now,
                    refund_amount: refundAmount,
                    refund_credit_amount: refundAmount,
                    refund_method: 'store_credit',
                    refund_reason: 'auto_expired',
                    updated_at: now,
                  })
                  .eq('id', itemId);

                if (itemUpdateErr) {
                  throw new Error(`更新 order_items 状态失败: ${itemUpdateErr.message}`);
                }
                summary.succeeded += 1;
              }
            }
          }
        }

        // 发送 C5 到期自动退款通知给购买者（即发即忘，不阻断批次）
        try {
          const { data: userInfo } = await supabaseAdmin
            .from('users')
            .select('email, full_name')
            .eq('id', item.user_id)
            .single();
          if (userInfo?.email) {
            const { subject, html } = buildC5Email({ refundAmount });
            await sendEmail(supabaseAdmin, {
              to:            userInfo.email,
              subject,
              htmlBody:      html,
              emailCode:     'C5',
              referenceId:   itemId,
              recipientType: 'customer',
              userId:        item.user_id,
            });
          }
        } catch (emailErr) {
          console.error(`auto-refund-expired: C5 email error item=${itemId}:`, emailErr);
        }

        // gifted 券过期特殊处理：更新 gift 状态 + 通知受赠方
        if (item.customer_status === 'gifted') {
          try {
            // 将 coupon_gifts.status 更新为 expired
            await supabaseAdmin
              .from('coupon_gifts')
              .update({ status: 'expired', updated_at: now })
              .eq('order_item_id', itemId)
              .eq('status', 'pending');

            // 查询 gift 受赠方信息和 deal 信息
            const { data: giftRecord } = await supabaseAdmin
              .from('coupon_gifts')
              .select('recipient_email')
              .eq('order_item_id', itemId)
              .order('created_at', { ascending: false })
              .limit(1)
              .maybeSingle();

            const { data: dealInfo } = await supabaseAdmin
              .from('deals')
              .select('title, merchants(name)')
              .eq('id', item.deal_id)
              .single();

            const dealTitle = (dealInfo?.title as string | undefined) ?? '';
            const merchantName = ((dealInfo as any)?.merchants?.name as string | undefined) ?? '';

            // 发送 C15 邮件给受赠方：告知 gifted 券已过期
            if (giftRecord?.recipient_email) {
              const { data: gifterInfo } = await supabaseAdmin
                .from('users')
                .select('full_name, email')
                .eq('id', item.user_id)
                .single();

              const gifterName = (gifterInfo?.full_name as string | undefined)
                || (gifterInfo?.email as string | undefined)
                || 'The sender';

              await sendEmail(supabaseAdmin, {
                to: giftRecord.recipient_email,
                subject: 'A gift coupon you received has expired',
                htmlBody: buildGiftExpiredEmail({ gifterName, dealTitle, merchantName }),
                emailCode: 'C15',
                referenceId: itemId,
                recipientType: 'customer',
              });
            }
          } catch (giftErr) {
            console.error(`auto-refund-expired: gifted item processing error item=${itemId}:`, giftErr);
          }
        }

      } catch (err) {
        const errMsg = err instanceof Error ? err.message : String(err);
        console.error(`auto-refund-expired: item=${itemId} 处理失败 —`, errMsg);
        summary.failed += 1;
        summary.errors.push({ orderItemId: itemId, error: errMsg });
      }
    }

    return new Response(
      JSON.stringify(summary),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  } catch (err) {
    console.error('auto-refund-expired: 未预期的错误', err);
    return new Response(
      JSON.stringify({
        error: err instanceof Error ? err.message : 'Unknown error',
        ...summary,
      }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  }
});

// 回退到 store credit 全额退款（refundCreditAmount 默认可退总额，写入 refund_credit_amount）
async function fallbackToStoreCredit(
  supabaseAdmin: ReturnType<typeof createClient>,
  item: { user_id: string },
  itemId: string,
  refundAmount: number,
  now: string,
  refundCreditAmount?: number,
) {
  const creditPortion = refundCreditAmount ?? refundAmount;

  const { error: creditErr } = await supabaseAdmin.rpc('add_store_credit', {
    p_user_id: item.user_id,
    p_amount: refundAmount,
    p_order_item_id: itemId,
    p_description: `Auto refund for expired coupon (order_item: ${itemId})`,
  });

  if (creditErr) {
    throw new Error(`add_store_credit 失败: ${creditErr.message}`);
  }

  const { error: itemUpdateErr } = await supabaseAdmin
    .from('order_items')
    .update({
      customer_status: 'refund_success',
      refunded_at: now,
      refund_amount: refundAmount,
      refund_credit_amount: creditPortion,
      refund_method: 'store_credit',
      refund_reason: 'auto_expired',
      updated_at: now,
    })
    .eq('id', itemId);

  if (itemUpdateErr) {
    throw new Error(`更新 order_items 状态失败: ${itemUpdateErr.message}`);
  }

  console.log(`auto-refund-expired: item=${itemId} store credit 退款成功 ${refundAmount}`);
}

// =============================================================
// C15: gifted 券过期通知邮件模板（发给受赠方）
// =============================================================

function buildGiftExpiredEmail(params: {
  gifterName: string;
  dealTitle: string;
  merchantName: string;
}): string {
  const { gifterName, dealTitle, merchantName } = params;
  const esc = (s: string) => s
    .replace(/&/g, '&amp;').replace(/</g, '&lt;')
    .replace(/>/g, '&gt;').replace(/"/g, '&quot;');

  return `<!DOCTYPE html>
<html lang="en">
<head><meta charset="UTF-8"/><meta name="viewport" content="width=device-width,initial-scale=1.0"/></head>
<body style="margin:0;padding:0;background:#F5F5F5;font-family:Arial,sans-serif;">
<table width="100%" cellpadding="0" cellspacing="0" style="background:#F5F5F5;padding:32px 0;">
<tr><td align="center">
<table width="600" cellpadding="0" cellspacing="0" style="background:#FFF;border-radius:8px;overflow:hidden;box-shadow:0 2px 8px rgba(0,0,0,0.08);">
  <tr><td style="background:#E53935;padding:20px 24px;">
    <p style="margin:0;font-size:22px;font-weight:700;color:#FFF;">CrunchyPlum</p>
  </td></tr>
  <tr><td style="padding:28px 24px 8px;">
    <p style="margin:0 0 8px;font-size:22px;font-weight:700;color:#212121;">Gift Coupon Expired</p>
    <p style="margin:0;font-size:15px;color:#424242;line-height:1.6;">
      The gift coupon that <strong>${esc(gifterName)}</strong> sent you has expired and is no longer available. The purchase amount has been automatically refunded to the sender.
    </p>
  </td></tr>
  <tr><td style="padding:16px 24px;">
    <table width="100%" cellpadding="0" cellspacing="0" style="background:#FAFAFA;border:1px solid #E0E0E0;border-radius:6px;">
      <tr>
        <td style="padding:10px 16px;font-size:13px;color:#757575;width:35%;border-bottom:1px solid #E0E0E0;">Deal</td>
        <td style="padding:10px 16px;font-size:13px;color:#212121;font-weight:600;border-bottom:1px solid #E0E0E0;">${esc(dealTitle)}</td>
      </tr>
      <tr>
        <td style="padding:10px 16px;font-size:13px;color:#757575;">Merchant</td>
        <td style="padding:10px 16px;font-size:13px;color:#212121;">${esc(merchantName)}</td>
      </tr>
    </table>
  </td></tr>
  <tr><td style="padding:0 24px 24px;">
    <hr style="border:none;border-top:1px solid #E0E0E0;margin:0 0 16px;"/>
    <p style="margin:0;font-size:12px;color:#9E9E9E;text-align:center;">
      Questions? <a href="mailto:support@crunchyplum.com" style="color:#E53935;text-decoration:none;">support@crunchyplum.com</a>
    </p>
  </td></tr>
</table>
</td></tr></table>
</body></html>`;
}
