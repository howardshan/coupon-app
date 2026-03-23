// =============================================================
// M9 — 收到售后申请通知（发给商家）
// 触发：after-sales-request handleCreateRequest 成功后
// =============================================================

import { wrapInLayout, escapeHtml, buildInfoTable } from "../base-layout.ts";

export interface M9AfterSalesReceivedData {
  merchantName: string;
  requestId: string;       // 短编号（前8位大写）
  reasonCode: string;
  reasonDetail: string;    // 客户描述
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

export function buildM9Email(data: M9AfterSalesReceivedData): { subject: string; html: string } {
  const subject = `After-sales request received — action required within 48 hours`;
  const dashboardUrl = data.dashboardUrl ?? "https://merchant.crunchyplum.com/after-sales";

  const body = `
    <p style="margin:0 0 16px;font-size:22px;font-weight:700;color:#212121;">
      New after-sales request
    </p>

    <p style="margin:0 0 16px;color:#424242;line-height:1.7;">
      Hi ${escapeHtml(data.merchantName)}, a customer has submitted an after-sales request
      related to your store. Please review and respond within <strong>48 hours</strong>.
    </p>

    ${buildInfoTable([
      { label: "Request ID",  value: `<span style="font-family:monospace;">${escapeHtml(data.requestId)}</span>` },
      ...(data.dealTitle ? [{ label: "Deal", value: escapeHtml(data.dealTitle) }] : []),
      { label: "Reason",      value: escapeHtml(formatReasonCode(data.reasonCode)) },
      { label: "Customer Note", value: `<em style="color:#424242;">"${escapeHtml(data.reasonDetail)}"</em>` },
      { label: "Respond By",  value: '<span style="color:#C62828;font-weight:600;">Within 48 hours</span>' },
    ])}

    <p style="margin:16px 0;font-size:14px;color:#424242;line-height:1.7;">
      You can <strong>approve</strong> the refund request or <strong>reject</strong> it with a written
      explanation. If you reject and the customer disagrees, the case may be escalated
      to CrunchyPlum for platform review.
    </p>

    <p style="margin:0;font-size:13px;color:#757575;line-height:1.6;">
      Please do not reply to this email. Manage the request in your merchant dashboard.
    </p>
  `;

  return {
    subject,
    html: wrapInLayout({ subject, body, cta: { label: "Review Request", url: dashboardUrl } }),
  };
}
