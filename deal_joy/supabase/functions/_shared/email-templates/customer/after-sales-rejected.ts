// =============================================================
// C11 — 售后审核拒绝通知（发给客户）
// 触发：platform-after-sales handleReject 成功后
// =============================================================

import { wrapInLayout, escapeHtml, buildInfoTable } from "../base-layout.ts";

export interface C11AfterSalesRejectedData {
  requestId: string;
  rejectionNote: string;
  dealTitle?: string;
}

export function buildC11Email(data: C11AfterSalesRejectedData): { subject: string; html: string } {
  const subject = "Update on your after-sales request — decision from CrunchyPlum";

  const body = `
    <p style="margin:0 0 16px;font-size:22px;font-weight:700;color:#212121;">
      Platform review decision
    </p>

    <p style="margin:0 0 16px;color:#424242;line-height:1.7;">
      After carefully reviewing all evidence submitted by both parties, CrunchyPlum
      has reached a final decision on your after-sales request.
    </p>

    ${buildInfoTable([
      { label: "Request ID", value: `<span style="font-family:monospace;">${escapeHtml(data.requestId)}</span>` },
      ...(data.dealTitle ? [{ label: "Deal", value: escapeHtml(data.dealTitle) }] : []),
      { label: "Decision",   value: '<span style="color:#C62828;font-weight:600;">Not approved</span>' },
      { label: "Reason",     value: `<em>"${escapeHtml(data.rejectionNote)}"</em>` },
    ])}

    <p style="margin:16px 0;color:#424242;line-height:1.7;">
      This is a final decision and the case has been closed. We understand this may be
      disappointing, and we appreciate your patience throughout the review process.
    </p>

    <p style="margin:0;font-size:13px;color:#757575;line-height:1.6;">
      If you believe this decision was made in error, contact us at
      <a href="mailto:support@crunchyplum.com" style="color:#E53935;">support@crunchyplum.com</a>
      within 7 days and reference your Request ID.
    </p>
  `;

  return {
    subject,
    html: wrapInLayout({ subject, body }),
  };
}
