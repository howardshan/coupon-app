// =============================================================
// A6 — 售后案件结案通知（发给管理员）
// 触发：platform-after-sales handleApprove 或 handleReject 成功后
// =============================================================

import { wrapInLayout, escapeHtml, formatCurrency, buildInfoTable } from "../base-layout.ts";

export interface A6AfterSalesClosedData {
  requestId: string;
  decision: "approved" | "rejected";
  platformNote: string;
  adminReviewerName?: string;
  refundAmount?: number;
  dealTitle?: string;
  dashboardUrl?: string;
}

export function buildA6Email(data: A6AfterSalesClosedData): { subject: string; html: string } {
  const isApproved = data.decision === "approved";
  const subject = `[Closed] After-sales case ${data.requestId} — ${isApproved ? "Refund approved" : "Rejected"}`;
  const dashboardUrl = data.dashboardUrl ?? `https://admin.crunchyplum.com/after-sales/${data.requestId}`;

  const body = `
    <p style="margin:0 0 16px;font-size:22px;font-weight:700;color:#212121;">
      After-sales case closed
    </p>

    <p style="margin:0 0 16px;color:#424242;line-height:1.7;">
      A platform review has been completed and the case has been closed.
    </p>

    ${buildInfoTable([
      { label: "Request ID",   value: `<span style="font-family:monospace;">${escapeHtml(data.requestId)}</span>` },
      ...(data.dealTitle ? [{ label: "Deal", value: escapeHtml(data.dealTitle) }] : []),
      { label: "Final Decision", value: isApproved
          ? '<span style="color:#C62828;font-weight:600;">Approved (customer refunded)</span>'
          : '<span style="color:#2E7D32;font-weight:600;">Rejected (no refund)</span>' },
      { label: "Platform Note", value: `<em>"${escapeHtml(data.platformNote)}"</em>` },
      ...(data.adminReviewerName ? [{ label: "Reviewed By", value: escapeHtml(data.adminReviewerName) }] : []),
      ...(isApproved && data.refundAmount
        ? [{ label: "Refund Amount", value: formatCurrency(data.refundAmount) }]
        : []),
    ])}

    <p style="margin:16px 0 0;font-size:13px;color:#757575;line-height:1.6;">
      This is an automated archive notification. View full case history in the admin dashboard.
    </p>
  `;

  return {
    subject,
    html: wrapInLayout({ subject, body, cta: { label: "View Case", url: dashboardUrl } }),
  };
}
