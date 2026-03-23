// =============================================================
// C10 — 售后审核通过通知（发给客户）
// 触发：platform-after-sales handleApprove 成功后
// =============================================================

import { wrapInLayout, escapeHtml, formatCurrency, buildInfoTable } from "../base-layout.ts";

export interface C10AfterSalesApprovedData {
  requestId: string;
  refundAmount: number;
  refundMethod: "store_credit" | "original_payment";
  dealTitle?: string;
}

export function buildC10Email(data: C10AfterSalesApprovedData): { subject: string; html: string } {
  const subject = "Your after-sales refund has been approved by CrunchyPlum";

  const refundMethodLabel = data.refundMethod === "store_credit"
    ? '<span style="color:#2E7D32;font-weight:600;">Store Credit</span> <span style="color:#757575;font-size:12px;">(available immediately)</span>'
    : '<span style="color:#1565C0;font-weight:600;">Original Payment Method</span> <span style="color:#757575;font-size:12px;">(3–5 business days)</span>';

  const body = `
    <p style="margin:0 0 16px;font-size:22px;font-weight:700;color:#212121;">
      Platform review approved — refund issued ✓
    </p>

    <p style="margin:0 0 16px;color:#424242;line-height:1.7;">
      After reviewing all evidence, CrunchyPlum has approved your after-sales request.
      Your refund is on its way.
    </p>

    ${buildInfoTable([
      { label: "Request ID",     value: `<span style="font-family:monospace;">${escapeHtml(data.requestId)}</span>` },
      ...(data.dealTitle ? [{ label: "Deal", value: escapeHtml(data.dealTitle) }] : []),
      { label: "Refund Amount",  value: `<strong style="font-size:18px;">${formatCurrency(data.refundAmount)}</strong>` },
      { label: "Refund Method",  value: refundMethodLabel },
    ])}

    <p style="margin:16px 0 0;font-size:13px;color:#757575;line-height:1.6;">
      Thank you for your patience. If you have further questions, contact
      <a href="mailto:support@crunchyplum.com" style="color:#E53935;">support@crunchyplum.com</a>.
    </p>
  `;

  return {
    subject,
    html: wrapInLayout({ subject, body, cta: { label: "View My Orders", url: "crunchyplum://orders" } }),
  };
}
