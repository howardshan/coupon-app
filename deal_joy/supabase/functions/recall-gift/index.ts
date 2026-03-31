import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { sendEmail } from '../_shared/email.ts';

// CORS 头，允许跨域请求
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
    // 初始化 Supabase 客户端（service role 绕过 RLS，在函数内自行做权限校验）
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, serviceRoleKey);

    // ----------------------------------------------------------------
    // 1. 验证用户身份（从 Authorization header 中解析 JWT）
    // ----------------------------------------------------------------
    const authHeader = req.headers.get('Authorization');
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return new Response(
        JSON.stringify({ error: 'Missing or invalid Authorization header' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 401 },
      );
    }

    const token = authHeader.replace('Bearer ', '');

    // 使用 anon key 客户端验证 token，获取用户信息
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
    const anonClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: `Bearer ${token}` } },
    });

    const { data: { user }, error: authError } = await anonClient.auth.getUser();
    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: 'Unauthorized: invalid token' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 401 },
      );
    }

    const currentUserId = user.id;

    // ----------------------------------------------------------------
    // 2. 解析请求体
    // ----------------------------------------------------------------
    const body = await req.json();
    const { gift_id } = body as { gift_id?: string };

    if (!gift_id) {
      return new Response(
        JSON.stringify({ error: 'Missing required field: gift_id' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 },
      );
    }

    // ----------------------------------------------------------------
    // 3. 查询礼品记录，验证归属和状态（包含受赠方信息，用于发邮件）
    // ----------------------------------------------------------------
    const { data: gift, error: giftError } = await supabase
      .from('coupon_gifts')
      .select('id, gifter_user_id, status, order_item_id, recipient_email, recipient_phone, gift_type, recipient_user_id')
      .eq('id', gift_id)
      .single();

    if (giftError || !gift) {
      return new Response(
        JSON.stringify({ error: 'Gift not found' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 404 },
      );
    }

    // 验证当前用户是赠送者
    if (gift.gifter_user_id !== currentUserId) {
      return new Response(
        JSON.stringify({ error: 'Forbidden: you are not the gifter of this gift' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 403 },
      );
    }

    // ----------------------------------------------------------------
    // 4. 查询关联的 order_item 和 coupon，用于后续状态校验和恢复
    // ----------------------------------------------------------------
    const { data: orderItem, error: itemError } = await supabase
      .from('order_items')
      .select('id, coupon_id, deal_id')
      .eq('id', gift.order_item_id)
      .single();

    if (itemError || !orderItem) {
      return new Response(
        JSON.stringify({ error: 'Associated order item not found' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 404 },
      );
    }

    // ----------------------------------------------------------------
    // 4b. 扩展状态校验：
    //   - 外部赠送：只有 pending 状态可撤回
    //   - 好友赠送（in_app）：pending 或 claimed 状态均可撤回（但券必须未使用）
    // ----------------------------------------------------------------
    const isInAppGift = gift.gift_type === 'in_app';

    if (gift.status !== 'pending') {
      if (!(isInAppGift && gift.status === 'claimed')) {
        return new Response(
          JSON.stringify({ error: `Cannot recall gift with status: ${gift.status}` }),
          { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 422 },
        );
      }

      // 好友赠送 claimed 状态：检查券是否已使用，已使用则不允许撤回
      if (orderItem.coupon_id) {
        const { data: couponStatus } = await supabase
          .from('coupons')
          .select('status')
          .eq('id', orderItem.coupon_id)
          .single();

        if (couponStatus && couponStatus.status !== 'unused') {
          return new Response(
            JSON.stringify({ error: 'Cannot recall: coupon has already been used' }),
            { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 422 },
          );
        }
      }
    }

    // ----------------------------------------------------------------
    // 5. 原子执行撤回操作（使用 service role 绕过 RLS）
    // ----------------------------------------------------------------

    // 5a. 更新 coupon_gifts: status='recalled', recalled_at=now()
    const { error: recallGiftError } = await supabase
      .from('coupon_gifts')
      .update({
        status: 'recalled',
        recalled_at: new Date().toISOString(),
      })
      .eq('id', gift_id);

    if (recallGiftError) {
      throw new Error(`Failed to update gift status: ${recallGiftError.message}`);
    }

    // 5b. 恢复 order_items.customer_status = 'unused'
    const { error: itemUpdateError } = await supabase
      .from('order_items')
      .update({ customer_status: 'unused' })
      .eq('id', gift.order_item_id);

    if (itemUpdateError) {
      throw new Error(`Failed to restore order item status: ${itemUpdateError.message}`);
    }

    // 5c. 恢复 coupons: status='unused', 清除 void_reason, is_gifted=false, gifted_from_user_id=null
    if (orderItem.coupon_id) {
      const { error: couponUpdateError } = await supabase
        .from('coupons')
        .update({
          status: 'unused',
          void_reason: null,
          voided_at: null,
          is_gifted: false,
          current_holder_user_id: currentUserId,
          gifted_from_user_id: null,   // 清除赠送者信息
        })
        .eq('id', orderItem.coupon_id);

      if (couponUpdateError) {
        throw new Error(`Failed to restore coupon: ${couponUpdateError.message}`);
      }
    }

    // ----------------------------------------------------------------
    // 6. 异步发送撤回通知邮件给受赠方（即发即忘）
    //    - 外部赠送：直接使用 gift.recipient_email
    //    - 好友赠送（in_app）：通过 recipient_user_id 查询受赠人邮箱
    // ----------------------------------------------------------------
    // 先确定受赠人邮箱
    const recipientEmail = gift.recipient_email as string | null;
    let recipientEmailForNotify: string | null = recipientEmail;

    // 好友赠送且没有 recipient_email 时，通过 recipient_user_id 查询邮箱
    if (!recipientEmailForNotify && isInAppGift && gift.recipient_user_id) {
      const { data: recipientInfo } = await supabase
        .from('users')
        .select('email')
        .eq('id', gift.recipient_user_id)
        .single();
      recipientEmailForNotify = (recipientInfo?.email as string | undefined) ?? null;
    }

    if (recipientEmailForNotify) {
      (async () => {
        try {
          // 查询 deal 信息
          const { data: dealInfo } = await supabase
            .from('deals')
            .select('title, merchants(name)')
            .eq('id', orderItem.deal_id)
            .single();

          const dealTitle = (dealInfo?.title as string | undefined) ?? '';
          const merchantName = ((dealInfo as any)?.merchants?.name as string | undefined) ?? '';

          // 查询赠送人姓名
          const { data: gifterInfo } = await supabase
            .from('users')
            .select('full_name, email')
            .eq('id', currentUserId)
            .single();

          const gifterName = (gifterInfo?.full_name as string | undefined)
            || (gifterInfo?.email as string | undefined)
            || 'The sender';

          const subject = 'A gift you received has been recalled';
          const htmlBody = buildRecallNotificationEmail({
            gifterName,
            dealTitle,
            merchantName,
          });

          // 好友赠送使用 C16，外部赠送使用 C14
          const emailCode = isInAppGift ? 'C16' : 'C14';

          await sendEmail(supabase, {
            to: recipientEmailForNotify,
            subject,
            htmlBody,
            emailCode,
            referenceId: gift_id,
            recipientType: 'customer',
          });
        } catch (emailErr) {
          console.error('recall-gift: email notification error:', emailErr);
        }
      })();
    }

    // ----------------------------------------------------------------
    // 7. 返回成功
    // ----------------------------------------------------------------
    return new Response(
      JSON.stringify({ success: true }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 },
    );
  } catch (error) {
    // 捕获未预期的服务器错误
    return new Response(
      JSON.stringify({ error: (error as Error).message }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 },
    );
  }
});

// =============================================================
// 撤回通知邮件模板（C14: gift_recalled_notification）
// =============================================================

interface RecallNotificationParams {
  gifterName: string;
  dealTitle: string;
  merchantName: string;
}

function buildRecallNotificationEmail(params: RecallNotificationParams): string {
  const { gifterName, dealTitle, merchantName } = params;

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Gift Recalled</title>
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
                Gift Recalled
              </p>
              <p style="margin:0;font-size:15px;color:#424242;line-height:1.6;">
                <strong>${escapeHtml(gifterName)}</strong> has recalled the gift they sent you. This coupon is no longer available for you to claim.
              </p>
            </td>
          </tr>

          <!-- 礼物详情 -->
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

          <!-- 说明文字 -->
          <tr>
            <td style="padding:8px 24px 16px;">
              <p style="margin:0;font-size:13px;color:#757575;text-align:center;line-height:1.6;">
                If you have any questions, please contact the person who sent you this gift.
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

// HTML 特殊字符转义
function escapeHtml(str: string): string {
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}
