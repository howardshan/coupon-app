// =============================================================
// C6 — Store Credit 余额到账通知
// 触发：create-refund（store_credit 路径）退款成功后
// =============================================================

import { wrapInLayout, escapeHtml, formatCurrency, buildInfoTable } from "../base-layout.ts";

export interface C6StoreCreditAddedData {
  creditAmount:  number;
  dealTitle?:    string;
}

export function buildC6Email(data: C6StoreCreditAddedData): { subject: string; html: string } {
  const subject = `${formatCurrency(data.creditAmount)} store credit added to your account`;

  const body = `
    <p style="margin:0 0 16px;font-size:22px;font-weight:700;color:#212121;">
      Store credit added! 💰
    </p>

    <p style="margin:0 0 16px;color:#424242;line-height:1.7;">
      Your refund has been processed as CrunchyPlum Store Credit.
      It's available to use immediately on your next purchase.
    </p>

    ${buildInfoTable([
      ...(data.dealTitle ? [{ label: "Item Refunded", value: escapeHtml(data.dealTitle) }] : []),
      { label: "Credit Added", value: `<strong style="font-size:18px;color:#2E7D32;">${formatCurrency(data.creditAmount)}</strong>` },
      { label: "Status",       value: '<span style="color:#2E7D32;font-weight:600;">Available immediately</span>' },
    ])}

    <p style="margin:0;font-size:13px;color:#757575;line-height:1.6;">
      Store credit never expires and can be applied to any deal on CrunchyPlum.
      Questions? Contact us at
      <a href="mailto:support@crunchyplum.com" style="color:#E53935;">support@crunchyplum.com</a>.
    </p>
  `;

  return {
    subject,
    html: wrapInLayout({ subject, body, cta: { label: "Browse Deals", url: "crunchyplum://home" } }),
  };
}
