// =============================================================
// M10 — 商家同意售后退款确认（发给商家）
// 触发：merchant-after-sales handleApprove 成功后
// =============================================================

import { wrapInLayout, escapeHtml, formatCurrency, buildInfoTable } from "../base-layout.ts";

export interface M10AfterSalesApprovedData {
  merchantName: string;
  requestId: string;
  refundAmount: number;
  dashboardUrl?: string;
}

export function buildM10Email(data: M10AfterSalesApprovedData): { subject: string; html: string } {
  const subject = `After-sales refund approved — request ${data.requestId}`;
  const dashboardUrl = data.dashboardUrl ?? "https://merchant.crunchyplum.com/after-sales";

  const body = `
    <p style="margin:0 0 16px;font-size:22px;font-weight:700;color:#212121;">
      Refund approved ✓
    </p>

    <p style="margin:0 0 16px;color:#424242;line-height:1.7;">
      Hi ${escapeHtml(data.merchantName)}, you have approved the after-sales refund request.
      The customer has been notified and the refund is being processed.
    </p>

    ${buildInfoTable([
      { label: "Request ID",     value: `<span style="font-family:monospace;">${escapeHtml(data.requestId)}</span>` },
      { label: "Refund Amount",  value: `<strong>${formatCurrency(data.refundAmount)}</strong>` },
      { label: "Status",         value: '<span style="color:#2E7D32;font-weight:600;">Resolved</span>' },
    ])}

    <p style="margin:16px 0 0;font-size:13px;color:#757575;line-height:1.6;">
      The refund will be reflected in your next settlement report.
      View full details in your merchant dashboard.
    </p>
  `;

  return {
    subject,
    html: wrapInLayout({ subject, body, cta: { label: "View After-Sales", url: dashboardUrl } }),
  };
}
