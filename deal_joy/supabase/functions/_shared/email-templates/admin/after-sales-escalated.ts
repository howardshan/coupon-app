// =============================================================
// A5 — 售后案件升级审核通知（发给管理员）
// 触发：merchant-after-sales handleReject 后，案件状态变为 awaiting_platform
// =============================================================

import { wrapInLayout, escapeHtml, buildInfoTable } from "../base-layout.ts";

export interface A5AfterSalesEscalatedData {
  requestId: string;
  reasonCode: string;
  reasonDetail: string;
  merchantRejectionNote?: string;
  dealTitle?: string;
  dashboardUrl?: string;
}

function formatReasonCode(code: string): string {
  const map: Record<string, string> = {
    mistaken_redemption: "Mistaken redemption",
    bad_experience:      "Bad experience",
    service_issue:       "Service issue",
    quality_issue:       "Quality issue",
    other:               "Other",
  };
  return map[code] ?? code;
}

export function buildA5Email(data: A5AfterSalesEscalatedData): { subject: string; html: string } {
  const subject = `[Action Required] After-sales case escalated — ${data.requestId}`;
  const dashboardUrl = data.dashboardUrl ?? `https://admin.crunchyplum.com/after-sales/${data.requestId}`;

  const body = `
    <p style="margin:0 0 16px;font-size:22px;font-weight:700;color:#212121;">
      After-sales case escalated for platform review
    </p>

    <p style="margin:0 0 16px;color:#424242;line-height:1.7;">
      A customer has escalated their after-sales request after the merchant rejected it.
      Platform review is required within <strong>3 business days</strong>.
    </p>

    ${buildInfoTable([
      { label: "Request ID",    value: `<span style="font-family:monospace;">${escapeHtml(data.requestId)}</span>` },
      ...(data.dealTitle ? [{ label: "Deal", value: escapeHtml(data.dealTitle) }] : []),
      { label: "Reason",        value: escapeHtml(formatReasonCode(data.reasonCode)) },
      { label: "Customer Note", value: `<em>"${escapeHtml(data.reasonDetail)}"</em>` },
      ...(data.merchantRejectionNote
        ? [{ label: "Merchant Rejection Note", value: `<em>"${escapeHtml(data.merchantRejectionNote)}"</em>` }]
        : []),
      { label: "Status",        value: '<span style="color:#F57C00;font-weight:600;">Awaiting Platform Review</span>' },
    ])}

    <p style="margin:16px 0 0;font-size:13px;color:#757575;line-height:1.6;">
      Please review all evidence and make a final decision in the admin dashboard.
    </p>
  `;

  return {
    subject,
    html: wrapInLayout({ subject, body, cta: { label: "Review Case", url: dashboardUrl } }),
  };
}
