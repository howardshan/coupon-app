// =============================================================
// M11 — 商家拒绝售后——案件升级至平台（发给商家）
// 触发：merchant-after-sales handleReject 成功后
// =============================================================

import { wrapInLayout, escapeHtml, buildInfoTable } from "../base-layout.ts";

export interface M11AfterSalesRejectedData {
  merchantName: string;
  requestId: string;
  dashboardUrl?: string;
}

export function buildM11Email(data: M11AfterSalesRejectedData): { subject: string; html: string } {
  const subject = `After-sales case may be escalated to platform review — request ${data.requestId}`;
  const dashboardUrl = data.dashboardUrl ?? "https://merchant.crunchyplum.com/after-sales";

  const body = `
    <p style="margin:0 0 16px;font-size:22px;font-weight:700;color:#212121;">
      Rejection recorded — case may escalate
    </p>

    <p style="margin:0 0 16px;color:#424242;line-height:1.7;">
      Hi ${escapeHtml(data.merchantName)}, your rejection of the after-sales request has been recorded.
      The customer has been notified and may choose to request a <strong>platform review</strong>.
    </p>

    ${buildInfoTable([
      { label: "Request ID", value: `<span style="font-family:monospace;">${escapeHtml(data.requestId)}</span>` },
      { label: "Your Decision", value: '<span style="color:#C62828;font-weight:600;">Rejected</span>' },
      { label: "Next Step",     value: "Customer may escalate to CrunchyPlum platform review" },
    ])}

    <p style="margin:16px 0;color:#424242;line-height:1.7;">
      If the customer escalates, our team will review all evidence from both sides
      and make a final binding decision within <strong>3 business days</strong>.
    </p>

    <p style="margin:0;font-size:13px;color:#757575;line-height:1.6;">
      Please ensure all relevant evidence is available in your dashboard.
    </p>
  `;

  return {
    subject,
    html: wrapInLayout({ subject, body, cta: { label: "View Case", url: dashboardUrl } }),
  };
}
