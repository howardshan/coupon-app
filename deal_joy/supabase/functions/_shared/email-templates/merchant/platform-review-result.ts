// =============================================================
// M12 — 平台最终裁决通知（发给商家）
// 触发：platform-after-sales handleApprove 或 handleReject 成功后
// =============================================================

import { wrapInLayout, escapeHtml, formatCurrency, buildInfoTable } from "../base-layout.ts";

export interface M12PlatformReviewResultData {
  merchantName: string;
  requestId: string;
  decision: "approved" | "rejected";
  platformNote: string;
  refundAmount?: number;    // approved 时有值
  dashboardUrl?: string;
}

export function buildM12Email(data: M12PlatformReviewResultData): { subject: string; html: string } {
  const isApproved = data.decision === "approved";
  const subject = `Platform review result — after-sales request ${data.requestId}`;
  const dashboardUrl = data.dashboardUrl ?? "https://merchant.crunchyplum.com/after-sales";

  const decisionLabel = isApproved
    ? '<span style="color:#C62828;font-weight:600;">Approved in customer\'s favour</span>'
    : '<span style="color:#2E7D32;font-weight:600;">Rejected — case closed</span>';

  const rows = [
    { label: "Request ID",   value: `<span style="font-family:monospace;">${escapeHtml(data.requestId)}</span>` },
    { label: "Decision",     value: decisionLabel },
    { label: "Platform Note", value: `<em>"${escapeHtml(data.platformNote)}"</em>` },
    ...(isApproved && data.refundAmount
      ? [{ label: "Refund Amount", value: formatCurrency(data.refundAmount) + " <span style=\"color:#757575;font-size:12px;\">(deducted from your next settlement)</span>" }]
      : []),
  ];

  const body = `
    <p style="margin:0 0 16px;font-size:22px;font-weight:700;color:#212121;">
      Platform review decision
    </p>

    <p style="margin:0 0 16px;color:#424242;line-height:1.7;">
      Hi ${escapeHtml(data.merchantName)}, CrunchyPlum has completed its platform review
      of the escalated after-sales case. This is a final decision.
    </p>

    ${buildInfoTable(rows)}

    <p style="margin:16px 0 0;font-size:13px;color:#757575;line-height:1.6;">
      ${isApproved
        ? "The refund amount will be deducted from your next settlement report."
        : "No further action is required on your end."}
      View full case history in your dashboard.
    </p>
  `;

  return {
    subject,
    html: wrapInLayout({ subject, body, cta: { label: "View Case", url: dashboardUrl } }),
  };
}
