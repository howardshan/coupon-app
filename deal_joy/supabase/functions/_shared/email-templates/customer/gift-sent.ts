// =============================================================
// Gift Sent — 赠送方确认通知
// 触发：send-gift Edge Function 成功赠送后发给赠送人
// =============================================================

import { wrapInLayout, escapeHtml } from "../base-layout.ts";

export function buildGiftSentEmail(params: {
  dealTitle: string;
  recipientDisplay: string;
  giftMessage?: string;
}): { subject: string; htmlBody: string } {
  const { dealTitle, recipientDisplay, giftMessage } = params;

  const subject = `Gift sent! ${dealTitle} to ${recipientDisplay}`;

  // 留言预览区块（可选）
  const messagePreviewBlock = giftMessage
    ? `
      <table width="100%" cellpadding="0" cellspacing="0" border="0"
             style="margin:20px 0;background-color:#FFF8F8;border-left:4px solid #E53935;border-radius:4px;">
        <tr>
          <td style="padding:14px 16px;">
            <p style="margin:0 0 4px;font-size:12px;color:#757575;text-transform:uppercase;letter-spacing:0.5px;">
              Your message
            </p>
            <p style="margin:0;font-size:15px;color:#212121;line-height:1.6;font-style:italic;">
              "${escapeHtml(giftMessage)}"
            </p>
          </td>
        </tr>
      </table>`
    : "";

  const body = `
    <p style="margin:0 0 16px;font-size:22px;font-weight:700;color:#212121;">
      Your gift has been sent! 🎁
    </p>

    <p style="margin:0 0 16px;color:#424242;line-height:1.7;">
      Great news — your gift coupon is on its way.
      We've notified the recipient and they can claim it right away.
    </p>

    <table width="100%" cellpadding="0" cellspacing="0" border="0"
           style="margin:16px 0;border-top:1px solid #F0F0F0;">
      <tr>
        <td style="padding:8px 0;font-size:14px;color:#757575;width:40%;
                   border-bottom:1px solid #F0F0F0;vertical-align:top;">
          Deal
        </td>
        <td style="padding:8px 0 8px 16px;font-size:14px;color:#212121;
                   border-bottom:1px solid #F0F0F0;vertical-align:top;font-weight:500;">
          ${escapeHtml(dealTitle)}
        </td>
      </tr>
      <tr>
        <td style="padding:8px 0;font-size:14px;color:#757575;width:40%;
                   border-bottom:1px solid #F0F0F0;vertical-align:top;">
          Sent to
        </td>
        <td style="padding:8px 0 8px 16px;font-size:14px;color:#212121;
                   border-bottom:1px solid #F0F0F0;vertical-align:top;font-weight:500;">
          ${escapeHtml(recipientDisplay)}
        </td>
      </tr>
    </table>

    ${messagePreviewBlock}

    <table width="100%" cellpadding="0" cellspacing="0" border="0"
           style="margin:20px 0;background-color:#F5F5F5;border-radius:6px;">
      <tr>
        <td style="padding:14px 16px;">
          <p style="margin:0;font-size:14px;color:#424242;line-height:1.6;">
            💡 You can recall this gift anytime from your order details.
          </p>
        </td>
      </tr>
    </table>

    <p style="margin:16px 0 0;font-size:13px;color:#757575;line-height:1.6;">
      Need help? Contact us at
      <a href="mailto:support@crunchyplum.com" style="color:#E53935;">support@crunchyplum.com</a>
    </p>
  `;

  const htmlBody = wrapInLayout({ subject, body });

  return { subject, htmlBody };
}
