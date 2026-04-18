// =============================================================
// send-gift Edge Function
// POST /send-gift
//
// 将某张 order_item 下的券作为礼物发送给他人。
// 流程：
//   1. 验证用户身份（JWT）
//   2. 查询 order_item，校验归属和状态（必须为 unused）
//   3. 若该 item 已存在 pending 礼物，先自动撤回（recalled）
//   4. 创建新 coupon_gifts 记录（pending 状态）
//   5. 更新 order_items.customer_status = 'gifted'
//   6. 更新 coupons.is_gifted = true
//   7. 异步发送礼物通知邮件给受赠方（如有 email）
//   8. 返回 { gift_id, claim_token }
// =============================================================

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { sendEmail } from '../_shared/email.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
  // 处理 CORS 预检请求
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // ──────────────────────────────────────────────────────────
    // 初始化 Supabase 客户端
    // ──────────────────────────────────────────────────────────
    const supabaseUrl     = Deno.env.get('SUPABASE_URL') ?? '';
    const anonKey         = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
    const serviceRoleKey  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

    // 用户 JWT 客户端：用于身份验证和 RLS 保护的查询
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'Unauthorized' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const supabaseUser = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    // Service role 客户端：绕过 RLS，用于写操作
    const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey);

    // ──────────────────────────────────────────────────────────
    // 1. 验证用户身份
    // ──────────────────────────────────────────────────────────
    const { data: { user }, error: authError } = await supabaseUser.auth.getUser();
    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: 'Unauthorized' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // ──────────────────────────────────────────────────────────
    // 解析请求体，进行参数校验
    // ──────────────────────────────────────────────────────────
    const body = await req.json();
    const { order_item_id, recipient_email, recipient_phone, recipient_user_id, gift_message } = body;

    // order_item_id 必填
    if (!order_item_id || typeof order_item_id !== 'string' || order_item_id.trim() === '') {
      return new Response(
        JSON.stringify({ error: 'order_item_id is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // recipient_email、recipient_phone、recipient_user_id 三选一（匹配 DB 约束）
    if (!recipient_email && !recipient_phone && !recipient_user_id) {
      return new Response(
        JSON.stringify({ error: 'recipient_email, recipient_phone, or recipient_user_id is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // recipient_email 格式简单校验
    if (recipient_email && (typeof recipient_email !== 'string' || !recipient_email.includes('@'))) {
      return new Response(
        JSON.stringify({ error: 'Invalid recipient_email format' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // gift_message 长度限制（最多 500 字符）
    if (gift_message !== undefined && gift_message !== null) {
      if (typeof gift_message !== 'string') {
        return new Response(
          JSON.stringify({ error: 'gift_message must be a string' }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
        );
      }
      if (gift_message.length > 500) {
        return new Response(
          JSON.stringify({ error: 'gift_message must not exceed 500 characters' }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
        );
      }
    }

    // ──────────────────────────────────────────────────────────
    // 2. 查询 order_item，通过用户 JWT 客户端确保 RLS 归属校验
    // ──────────────────────────────────────────────────────────
    const { data: item, error: itemErr } = await supabaseUser
      .from('order_items')
      .select(`
        id,
        deal_id,
        customer_status,
        orders!inner (
          id,
          user_id
        )
      `)
      .eq('id', order_item_id)
      .single();

    if (itemErr || !item) {
      return new Response(
        JSON.stringify({ error: 'Order item not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const order = item.orders as { id: string; user_id: string };

    // 验证 order_item 归属当前用户
    if (order.user_id !== user.id) {
      return new Response(
        JSON.stringify({ error: 'Forbidden: this item does not belong to you' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // 只有 unused 状态的券才能发送礼物
    const customerStatus: string = item.customer_status ?? '';
    if (customerStatus !== 'unused') {
      return new Response(
        JSON.stringify({ error: `Cannot gift item with status: ${customerStatus}` }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const now = new Date().toISOString();

    // ──────────────────────────────────────────────────────────
    // 3. 若该 item 已存在 pending 礼物，自动撤回
    // ──────────────────────────────────────────────────────────
    const { data: existingGifts } = await supabaseAdmin
      .from('coupon_gifts')
      .select('id')
      .eq('order_item_id', order_item_id)
      .eq('status', 'pending');

    if (existingGifts && existingGifts.length > 0) {
      const pendingIds = existingGifts.map((g: { id: string }) => g.id);
      await supabaseAdmin
        .from('coupon_gifts')
        .update({ status: 'recalled', recalled_at: now, updated_at: now })
        .in('id', pendingIds);
    }

    // ──────────────────────────────────────────────────────────
    // 好友赠送（in_app）模式：recipient_user_id 存在时走此分支
    // ──────────────────────────────────────────────────────────
    const isInAppGift = !!recipient_user_id;

    if (isInAppGift) {
      // 3a. 防止自赠
      if (recipient_user_id === user.id) {
        return new Response(
          JSON.stringify({ error: 'Cannot gift to yourself' }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
        );
      }

      // 3b. 验证受赠人存在
      const { data: recipientUser, error: recipientErr } = await supabaseAdmin
        .from('users')
        .select('id, email, full_name')
        .eq('id', recipient_user_id)
        .single();
      if (recipientErr || !recipientUser) {
        return new Response(
          JSON.stringify({ error: 'Recipient user not found' }),
          { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
        );
      }

      // 3c. 验证双方是好友
      const { data: friendship } = await supabaseAdmin
        .from('friendships')
        .select('id')
        .eq('user_id', user.id)
        .eq('friend_id', recipient_user_id)
        .maybeSingle();
      if (!friendship) {
        return new Response(
          JSON.stringify({ error: 'You can only gift to friends' }),
          { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
        );
      }

      // 4a. 创建 coupon_gifts 记录（直接 claimed，无需 claim_token）
      const { data: newGift, error: giftErr } = await supabaseAdmin
        .from('coupon_gifts')
        .insert({
          order_item_id,
          gifter_user_id:     user.id,
          recipient_user_id,
          recipient_email:    (recipientUser.email as string | null) ?? null,
          gift_message:       gift_message ?? null,
          status:             'claimed',
          claimed_at:         now,
          gift_type:          'in_app',
        })
        .select('id')
        .single();

      if (giftErr || !newGift) {
        console.error('send-gift: failed to create in_app coupon_gifts record:', giftErr);
        return new Response(
          JSON.stringify({ error: 'Failed to create gift record' }),
          { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
        );
      }

      // 5a. 先更新 coupons（转移持有人至受赠方）
      // 注意：必须在更新 order_items 之前执行，因为 order_items 上的
      // trg_sync_coupon_status 触发器会把券设为 voided
      await supabaseAdmin
        .from('coupons')
        .update({
          is_gifted:              true,
          current_holder_user_id: recipient_user_id,
          gifted_from_user_id:    user.id,
          status:                 'unused',
        })
        .eq('order_item_id', order_item_id);

      // 6a. 更新 order_items.customer_status = 'gifted'
      // 触发器会把 coupon status 设为 voided，之后再修正回 unused
      await supabaseAdmin
        .from('order_items')
        .update({ customer_status: 'gifted', updated_at: now })
        .eq('id', order_item_id);

      // 6b. 修正触发器副作用：好友赠送的券应保持 unused（可被受赠方使用）
      await supabaseAdmin
        .from('coupons')
        .update({ status: 'unused', void_reason: null, voided_at: null })
        .eq('order_item_id', order_item_id);

      // 7a. 异步发送好友赠送通知邮件（C15），即发即忘
      if (recipientUser.email) {
        (async () => {
          try {
            const { data: dealInfo } = await supabaseAdmin
              .from('deals')
              .select('title, merchants(name)')
              .eq('id', (item as any).deal_id)
              .single();

            const dealTitle    = (dealInfo?.title as string | undefined) ?? '';
            const merchantName = ((dealInfo as any)?.merchants?.name as string | undefined) ?? '';

            // 获取赠送人姓名（优先 display_name，其次 full_name，最后 email）
            const { data: gifterInfo } = await supabaseAdmin
              .from('users')
              .select('display_name, full_name, email')
              .eq('id', user.id)
              .single();

            const gifterName = (gifterInfo?.display_name as string | undefined)
              || (gifterInfo?.full_name as string | undefined)
              || (gifterInfo?.email as string | undefined)
              || 'A friend';

            const subject  = `${gifterName} gifted you a coupon!`;
            const htmlBody = buildFriendGiftEmail({
              gifterName,
              dealTitle,
              merchantName,
              giftMessage:   gift_message ?? null,
              recipientName: (recipientUser.full_name as string | undefined) || 'there',
            });

            await sendEmail(supabaseAdmin, {
              to:            recipientUser.email as string,
              subject,
              htmlBody,
              emailCode:     'C15',
              referenceId:   newGift.id as string,
              recipientType: 'customer',
            });
          } catch (emailErr) {
            console.error('send-gift: friend gift email error:', emailErr);
          }
        })();
      }

      // 8a. 返回（in_app 模式不返回 claim_token）
      return new Response(
        JSON.stringify({ gift_id: newGift.id, gift_type: 'in_app' }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // ──────────────────────────────────────────────────────────
    // 4. 创建新 coupon_gifts 记录（external 赠送模式）
    // ──────────────────────────────────────────────────────────
    const { data: newGift, error: giftErr } = await supabaseAdmin
      .from('coupon_gifts')
      .insert({
        order_item_id:   order_item_id,
        gifter_user_id:  user.id,
        recipient_email: recipient_email ?? null,
        recipient_phone: recipient_phone ?? null,
        gift_message:    gift_message ?? null,
        status:          'pending',
      })
      .select('id, claim_token')
      .single();

    if (giftErr || !newGift) {
      console.error('send-gift: failed to create coupon_gifts record:', giftErr);
      return new Response(
        JSON.stringify({ error: 'Failed to create gift record' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const giftId    = newGift.id as string;
    const claimToken = newGift.claim_token as string;

    // ──────────────────────────────────────────────────────────
    // 5. 更新 order_items.customer_status = 'gifted'
    // ──────────────────────────────────────────────────────────
    await supabaseAdmin
      .from('order_items')
      .update({ customer_status: 'gifted', updated_at: now })
      .eq('id', order_item_id);

    // ──────────────────────────────────────────────────────────
    // 6. 更新 coupons.is_gifted = true（按 order_item_id 关联）
    // ──────────────────────────────────────────────────────────
    await supabaseAdmin
      .from('coupons')
      .update({ is_gifted: true })
      .eq('order_item_id', order_item_id);

    // ──────────────────────────────────────────────────────────
    // 7. 异步发送礼物通知邮件（即发即忘，不阻断核心流程）
    // ──────────────────────────────────────────────────────────
    if (recipient_email) {
      (async () => {
        try {
          // 获取 deal 信息用于邮件内容
          const { data: dealInfo } = await supabaseAdmin
            .from('deals')
            .select('title, merchants(name)')
            .eq('id', (item as any).deal_id)
            .single();

          const dealTitle    = (dealInfo?.title as string | undefined) ?? '';
          const merchantName = ((dealInfo as any)?.merchants?.name as string | undefined) ?? '';

          // 获取赠送人姓名（优先 display_name，其次 email）
          const { data: gifterInfo } = await supabaseAdmin
            .from('users')
            .select('display_name, email')
            .eq('id', user.id)
            .single();

          const gifterName = (gifterInfo?.display_name as string | undefined)
            || (gifterInfo?.email as string | undefined)
            || 'Someone';

          // claim URL
          const claimUrl = `https://crunchyplum.com/gift/${claimToken}`;

          // 构建礼物通知邮件（C13: gift_received_notification）
          // 邮件模板稍后创建，这里先动态构建 HTML
          const subject  = `${gifterName} sent you a gift!`;
          const htmlBody = buildGiftNotificationEmail({
            gifterName,
            dealTitle,
            merchantName,
            giftMessage: gift_message ?? null,
            claimUrl,
          });

          await sendEmail(supabaseAdmin, {
            to:             recipient_email,
            subject,
            htmlBody,
            emailCode:      'C13',
            referenceId:    giftId,
            recipientType:  'customer',
          });
        } catch (emailErr) {
          console.error('send-gift: email notification error:', emailErr);
        }
      })();
    }

    // ──────────────────────────────────────────────────────────
    // 8. 返回成功响应
    // ──────────────────────────────────────────────────────────
    return new Response(
      JSON.stringify({ gift_id: giftId, claim_token: claimToken }),
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      },
    );

  } catch (err) {
    console.error('send-gift: unexpected error:', err);
    return new Response(
      JSON.stringify({ error: err instanceof Error ? err.message : 'Unknown error' }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      },
    );
  }
});

// =============================================================
// 临时内联邮件模板
// 正式 C13 模板文件稍后在 _shared/email-templates/customer/ 中创建
// =============================================================

interface GiftNotificationParams {
  gifterName:   string;
  dealTitle:    string;
  merchantName: string;
  giftMessage:  string | null;
  claimUrl:     string;
}

function buildGiftNotificationEmail(params: GiftNotificationParams): string {
  const { gifterName, dealTitle, merchantName, giftMessage, claimUrl } = params;

  // 可选：礼物留言区块
  const messageBlock = giftMessage
    ? `
      <tr>
        <td style="padding: 12px 24px;">
          <div style="background:#FFF8E1;border-left:4px solid #FFC107;padding:12px 16px;border-radius:4px;">
            <p style="margin:0;font-size:13px;color:#5D4037;font-style:italic;">
              "${escapeHtml(giftMessage)}"
            </p>
            <p style="margin:6px 0 0;font-size:12px;color:#8D6E63;">— ${escapeHtml(gifterName)}</p>
          </div>
        </td>
      </tr>`
    : '';

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>You received a gift!</title>
</head>
<body style="margin:0;padding:0;background-color:#F5F5F5;font-family:Arial,sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background:#F5F5F5;padding:32px 0;">
    <tr>
      <td align="center">
        <table width="600" cellpadding="0" cellspacing="0"
               style="background:#FFFFFF;border-radius:8px;overflow:hidden;
                      box-shadow:0 2px 8px rgba(0,0,0,0.08);">

          <!-- 头部品牌色条 -->
          <tr>
            <td style="background:#E53935;padding:20px 24px;">
              <p style="margin:0;font-size:22px;font-weight:700;color:#FFFFFF;letter-spacing:0.5px;">
                CrunchyPlum
              </p>
            </td>
          </tr>

          <!-- 主体内容 -->
          <tr>
            <td style="padding:28px 24px 8px;">
              <p style="margin:0 0 8px;font-size:22px;font-weight:700;color:#212121;">
                You received a gift!
              </p>
              <p style="margin:0;font-size:15px;color:#424242;line-height:1.6;">
                <strong>${escapeHtml(gifterName)}</strong> sent you a gift coupon on CrunchyPlum.
              </p>
            </td>
          </tr>

          <!-- 礼物详情表格 -->
          <tr>
            <td style="padding:16px 24px;">
              <table width="100%" cellpadding="0" cellspacing="0"
                     style="background:#FAFAFA;border:1px solid #E0E0E0;border-radius:6px;">
                <tr>
                  <td style="padding:10px 16px;font-size:13px;color:#757575;width:35%;border-bottom:1px solid #E0E0E0;">
                    Deal
                  </td>
                  <td style="padding:10px 16px;font-size:13px;color:#212121;font-weight:600;border-bottom:1px solid #E0E0E0;">
                    ${escapeHtml(dealTitle)}
                  </td>
                </tr>
                <tr>
                  <td style="padding:10px 16px;font-size:13px;color:#757575;">
                    Merchant
                  </td>
                  <td style="padding:10px 16px;font-size:13px;color:#212121;">
                    ${escapeHtml(merchantName)}
                  </td>
                </tr>
              </table>
            </td>
          </tr>

          <!-- 可选留言 -->
          ${messageBlock}

          <!-- Claim 按钮 -->
          <tr>
            <td align="center" style="padding:24px 24px 8px;">
              <a href="${claimUrl}"
                 style="display:inline-block;background:#E53935;color:#FFFFFF;
                        font-size:15px;font-weight:600;text-decoration:none;
                        padding:14px 36px;border-radius:6px;letter-spacing:0.3px;">
                Claim Your Gift
              </a>
            </td>
          </tr>

          <!-- 说明文字 -->
          <tr>
            <td style="padding:8px 24px 16px;">
              <p style="margin:0;font-size:13px;color:#757575;text-align:center;line-height:1.6;">
                This gift link expires in 30 days. You'll need a CrunchyPlum account to claim it.
              </p>
            </td>
          </tr>

          <!-- 分割线 + 页脚 -->
          <tr>
            <td style="padding:0 24px 24px;">
              <hr style="border:none;border-top:1px solid #E0E0E0;margin:0 0 16px;" />
              <p style="margin:0;font-size:12px;color:#9E9E9E;text-align:center;line-height:1.6;">
                Questions? Contact us at
                <a href="mailto:support@crunchyplum.com"
                   style="color:#E53935;text-decoration:none;">support@crunchyplum.com</a>
              </p>
            </td>
          </tr>

        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;
}

// HTML 特殊字符转义，防止 XSS
function escapeHtml(str: string): string {
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

// =============================================================
// C15 好友赠送通知邮件模板（in_app 模式，无 claim 链接）
// =============================================================

interface FriendGiftEmailParams {
  gifterName:   string;
  dealTitle:    string;
  merchantName: string;
  giftMessage:  string | null;
  recipientName: string;
}

function buildFriendGiftEmail(params: FriendGiftEmailParams): string {
  const { gifterName, dealTitle, merchantName, giftMessage, recipientName } = params;

  // 可选：礼物留言区块
  const messageBlock = giftMessage
    ? `<tr><td style="padding:12px 24px;">
        <div style="background:#FFF8E1;border-left:4px solid #FFC107;padding:12px 16px;border-radius:4px;">
          <p style="margin:0;font-size:13px;color:#5D4037;font-style:italic;">"${escapeHtml(giftMessage)}"</p>
          <p style="margin:6px 0 0;font-size:12px;color:#8D6E63;">— ${escapeHtml(gifterName)}</p>
        </div>
      </td></tr>`
    : '';

  return `<!DOCTYPE html>
<html lang="en">
<head><meta charset="UTF-8"/><meta name="viewport" content="width=device-width,initial-scale=1.0"/><title>You received a gift!</title></head>
<body style="margin:0;padding:0;background-color:#F5F5F5;font-family:Arial,sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background:#F5F5F5;padding:32px 0;">
    <tr><td align="center">
      <table width="600" cellpadding="0" cellspacing="0" style="background:#FFFFFF;border-radius:8px;overflow:hidden;box-shadow:0 2px 8px rgba(0,0,0,0.08);">
        <tr><td style="background:#E53935;padding:20px 24px;">
          <p style="margin:0;font-size:22px;font-weight:700;color:#FFFFFF;letter-spacing:0.5px;">CrunchyPlum</p>
        </td></tr>
        <tr><td style="padding:28px 24px 8px;">
          <p style="margin:0 0 8px;font-size:22px;font-weight:700;color:#212121;">You received a gift!</p>
          <p style="margin:0;font-size:15px;color:#424242;line-height:1.6;">
            Hi ${escapeHtml(recipientName)}, <strong>${escapeHtml(gifterName)}</strong> gifted you a coupon on CrunchyPlum. It's already in your account — check your <strong>Unused Coupons</strong> tab!
          </p>
        </td></tr>
        <tr><td style="padding:16px 24px;">
          <table width="100%" cellpadding="0" cellspacing="0" style="background:#FAFAFA;border:1px solid #E0E0E0;border-radius:6px;">
            <tr>
              <td style="padding:10px 16px;font-size:13px;color:#757575;width:35%;border-bottom:1px solid #E0E0E0;">Deal</td>
              <td style="padding:10px 16px;font-size:13px;color:#212121;font-weight:600;border-bottom:1px solid #E0E0E0;">${escapeHtml(dealTitle)}</td>
            </tr>
            <tr>
              <td style="padding:10px 16px;font-size:13px;color:#757575;">Merchant</td>
              <td style="padding:10px 16px;font-size:13px;color:#212121;">${escapeHtml(merchantName)}</td>
            </tr>
          </table>
        </td></tr>
        ${messageBlock}
        <tr><td style="padding:8px 24px 16px;">
          <p style="margin:0;font-size:13px;color:#757575;text-align:center;line-height:1.6;">
            Open the CrunchyPlum app to view and use your coupon.
          </p>
        </td></tr>
        <tr><td style="padding:0 24px 24px;">
          <hr style="border:none;border-top:1px solid #E0E0E0;margin:0 0 16px;"/>
          <p style="margin:0;font-size:12px;color:#9E9E9E;text-align:center;line-height:1.6;">
            Questions? Contact us at <a href="mailto:support@crunchyplum.com" style="color:#E53935;text-decoration:none;">support@crunchyplum.com</a>
          </p>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>`;
}
