// auto-refund-expired: 过期券自动退款 Edge Function（Order System V3）
// 由 Supabase Cron Job 定期触发（建议每小时一次）
//
// V3 逻辑：
//   基于 order_items + coupons 查找过期未使用的券，
//   原路退回 Stripe（不退 service_fee），
//   无 Stripe 支付信息时回退到 store credit。
//
// 退款金额 = unit_price + tax_amount（退商品价+税，手续费不退）
// 更新 order_items: customer_status = 'refund_pending'（等 webhook 确认）
// 更新 coupons: status = 'expired'

import Stripe from 'https://esm.sh/stripe@14?target=deno';
import { createClient } from 'npm:@supabase/supabase-js@2';
import { sendEmail } from '../_shared/email.ts';
import { buildC5Email } from '../_shared/email-templates/customer/auto-refund.ts';

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
  apiVersion: '2024-04-10',
  httpClient: Stripe.createFetchHttpClient(),
});

// CORS 响应头
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// 单次最多处理条数，防止单次执行超时
const BATCH_SIZE = 50;

// Cron 调用方共享密钥（在 Supabase Dashboard > Secrets 中配置 CRON_SECRET）
const CRON_SECRET = Deno.env.get('CRON_SECRET');

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
    }>;

    if (queryError) {
      // RPC 不可用时，直接通过 supabase-js 多表查询
      console.warn('auto-refund-expired: RPC get_expired_order_items 不可用，使用 fallback 查询', queryError.message);

      const { data: rawItems, error: rawErr } = await supabaseAdmin
        .from('order_items')
        .select(`
          id,
          order_id,
          unit_price,
          service_fee,
          tax_amount,
          coupon_id,
          coupons!inner ( id, expires_at ),
          orders!inner ( user_id, stripe_charge_id, payment_intent_id )
        `)
        .eq('customer_status', 'unused')
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
        };
      });
    } else {
      items = expiredItems ?? [];
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

        // 2. 尝试原路 Stripe 退款
        const chargeId = item.stripe_charge_id;
        const piId = item.payment_intent_id;

        if (chargeId || piId) {
          // 有 Stripe 支付信息 → 原路退回
          try {
            const refundParams: Record<string, unknown> = {
              amount: Math.round(refundAmount * 100), // Stripe 用分
              metadata: { order_item_id: itemId, reason: 'auto_expired' },
            };
            if (chargeId) {
              refundParams.charge = chargeId;
            } else {
              refundParams.payment_intent = piId;
            }

            const stripeRefund = await stripe.refunds.create(refundParams as any);
            console.log(`auto-refund-expired: Stripe refund 成功 refund_id=${stripeRefund.id} item=${itemId}`);

            // Stripe 退款发起成功 → 标记 refund_pending，等 webhook 确认
            const { error: itemUpdateErr } = await supabaseAdmin
              .from('order_items')
              .update({
                customer_status: 'refund_pending',
                refund_amount: refundAmount,
                refund_method: 'original_payment',
                refund_reason: 'auto_expired',
                updated_at: now,
              })
              .eq('id', itemId);

            if (itemUpdateErr) {
              throw new Error(`更新 order_items 状态失败: ${itemUpdateErr.message}`);
            }

            summary.succeeded += 1;
            console.log(`auto-refund-expired: item=${itemId} Stripe 原路退款 ${refundAmount}`);

          } catch (stripeErr: unknown) {
            // Stripe 退款失败 → 回退到 store credit
            const stripeMsg = stripeErr instanceof Error ? stripeErr.message : String(stripeErr);
            console.warn(`auto-refund-expired: item=${itemId} Stripe 退款失败，回退 store credit: ${stripeMsg}`);

            await fallbackToStoreCredit(supabaseAdmin, item, itemId, refundAmount, now);
            summary.succeeded += 1;
          }

        } else {
          // 没有 Stripe 支付信息（可能是 store credit 支付）→ 退 store credit
          console.log(`auto-refund-expired: item=${itemId} 无 Stripe 支付信息，退 store credit`);
          await fallbackToStoreCredit(supabaseAdmin, item, itemId, refundAmount, now);
          summary.succeeded += 1;
        }

        // 发送 C5 到期自动退款通知（即发即忘，不阻断批次）
        try {
          const { data: userInfo } = await supabaseAdmin
            .from('users')
            .select('email')
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

// 回退到 store credit 退款
async function fallbackToStoreCredit(
  supabaseAdmin: ReturnType<typeof createClient>,
  item: { user_id: string },
  itemId: string,
  refundAmount: number,
  now: string,
) {
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
