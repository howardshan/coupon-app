// =============================================================
// M8 — 核销前退款通知（发给商家）
// 触发：create-refund 受理成功，且 customer_status 为 'unused'（券尚未被核销）
// =============================================================

import { wrapInLayout, escapeHtml, formatCurrency, buildInfoTable } from "../base-layout.ts";

export interface M8PreRedemptionRefundData {
  merchantName: string;
  dealTitle?: string;
  refundAmount: number;
  dashboardUrl?: string;
}

export function buildM8Email(data: M8PreRedemptionRefundData): { subject: string; html: string } {
  const subject = data.dealTitle
    ? `Voucher refunded before redemption — ${data.dealTitle}`
    : "A voucher was refunded before redemption";

  const dashboardUrl = data.dashboardUrl ?? "https://merchant.crunchyplum.com/orders";

  const body = `
    <p style="margin:0 0 16px;font-size:22px;font-weight:700;color:#212121;">
      Voucher refunded (not redeemed)
    </p>

    <p style="margin:0 0 16px;color:#424242;line-height:1.7;">
      Hi ${escapeHtml(data.merchantName)}, a customer has requested a refund for an
      <strong>unused</strong> voucher before redeeming it at your store.
      No action is required on your end.
    </p>

    ${buildInfoTable([
      ...(data.dealTitle ? [{ label: "Deal", value: escapeHtml(data.dealTitle) }] : []),
      { label: "Deal Value",     value: formatCurrency(data.refundAmount) },
      { label: "Voucher Status", value: '<span style="color:#757575;">Cancelled (not redeemed)</span>' },
    ])}

    <p style="margin:16px 0 0;font-size:13px;color:#757575;line-height:1.6;">
      This voucher will no longer be presented at your store.
      View your full order history in your dashboard.
    </p>
  `;

  return {
    subject,
    html: wrapInLayout({ subject, body, cta: { label: "View Orders", url: dashboardUrl } }),
  };
}
