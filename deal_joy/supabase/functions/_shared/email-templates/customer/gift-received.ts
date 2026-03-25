// =============================================================
// Gift Received — 受赠方收到礼品券通知
// 触发：send-gift Edge Function 成功赠送后发给收件人
// =============================================================

import { wrapInLayout, escapeHtml, formatDate, buildInfoTable } from "../base-layout.ts";

export function buildGiftReceivedEmail(params: {
  gifterName: string;
  dealTitle: string;
  merchantName: string;
  merchantAddress?: string;
  usageNotes?: string;
  expiresAt: string;
  giftMessage?: string;
  claimUrl: string;
}): { subject: string; htmlBody: string } {
  const {
    gifterName,
    dealTitle,
    merchantName,
    merchantAddress,
    usageNotes,
    expiresAt,
    giftMessage,
    claimUrl,
  } = params;

  const subject = `🎁 ${gifterName} sent you a coupon from ${merchantName}!`;

  // 构建信息行（条件性添加地址和使用说明）
  const infoRows: Array<{ label: string; value: string }> = [
    { label: "Deal",      value: escapeHtml(dealTitle) },
    { label: "Merchant",  value: escapeHtml(merchantName) },
  ];
  if (merchantAddress) {
    infoRows.push({ label: "Address", value: escapeHtml(merchantAddress) });
  }
  infoRows.push({ label: "Expires", value: escapeHtml(formatDate(expiresAt)) });
  if (usageNotes) {
    infoRows.push({ label: "Usage Notes", value: escapeHtml(usageNotes) });
  }

  // 赠送人留言区块（可选）
  const messageBlock = giftMessage
    ? `
      <table width="100%" cellpadding="0" cellspacing="0" border="0"
             style="margin:20px 0;background-color:#FFF8F8;border-left:4px solid #E53935;border-radius:4px;">
        <tr>
          <td style="padding:14px 16px;">
            <p style="margin:0 0 4px;font-size:12px;color:#757575;text-transform:uppercase;letter-spacing:0.5px;">
              Message from ${escapeHtml(gifterName)}
            </p>
            <p style="margin:0;font-size:15px;color:#212121;line-height:1.6;font-style:italic;">
              "${escapeHtml(giftMessage)}"
            </p>
          </td>
        </tr>
      </table>`
    : "";

  // App 下载引导区块
  const appDownloadBlock = `
    <p style="margin:24px 0 8px;font-size:13px;color:#757575;line-height:1.6;text-align:center;">
      Don't have the CrunchyPlum app yet?<br />
      Download it to manage your coupons easily.
    </p>
    <table cellpadding="0" cellspacing="0" border="0" style="margin:0 auto;">
      <tr>
        <td style="padding:0 6px;">
          <a href="https://apps.apple.com/app/crunchyplum"
             style="display:inline-block;background:#000000;color:#FFFFFF;
                    font-size:13px;font-weight:600;text-decoration:none;
                    padding:10px 20px;border-radius:6px;">
            App Store
          </a>
        </td>
        <td style="padding:0 6px;">
          <a href="https://play.google.com/store/apps/crunchyplum"
             style="display:inline-block;background:#1A1A2E;color:#FFFFFF;
                    font-size:13px;font-weight:600;text-decoration:none;
                    padding:10px 20px;border-radius:6px;">
            Google Play
          </a>
        </td>
      </tr>
    </table>`;

  const body = `
    <p style="margin:0 0 16px;font-size:22px;font-weight:700;color:#212121;">
      You've received a gift! 🎁
    </p>

    <p style="margin:0 0 16px;color:#424242;line-height:1.7;">
      <strong>${escapeHtml(gifterName)}</strong> has sent you a coupon as a gift.
      Tap the button below to claim it and enjoy your experience!
    </p>

    ${messageBlock}

    ${buildInfoTable(infoRows)}

    ${appDownloadBlock}

    <p style="margin:20px 0 0;font-size:13px;color:#757575;line-height:1.6;">
      Need help? Contact us at
      <a href="mailto:support@crunchyplum.com" style="color:#E53935;">support@crunchyplum.com</a>
    </p>
  `;

  const htmlBody = wrapInLayout({
    subject,
    body,
    cta: {
      label: "View My Coupon",
      url: claimUrl,
    },
  });

  return { subject, htmlBody };
}
