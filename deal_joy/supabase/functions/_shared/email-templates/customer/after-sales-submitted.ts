// =============================================================
// C9 — 售后申请提交确认（发给客户）
// 触发：after-sales-request handleCreateRequest 成功后
// =============================================================

import { wrapInLayout, escapeHtml, buildInfoTable } from "../base-layout.ts";

export interface C9AfterSalesSubmittedData {
  requestId: string;       // 短编号（前8位大写）
  reasonCode: string;      // 原因代码
  dealTitle?: string;
}

// 将 reason_code 转为易读英文
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

export function buildC9Email(data: C9AfterSalesSubmittedData): { subject: string; html: string } {
  const subject = "Your after-sales request has been received";

  const body = `
    <p style="margin:0 0 16px;font-size:22px;font-weight:700;color:#212121;">
      After-sales request received ✓
    </p>

    <p style="margin:0 0 16px;color:#424242;line-height:1.7;">
      We've received your after-sales request and it has been forwarded to the merchant
      for review. Here's a summary of your submission:
    </p>

    ${buildInfoTable([
      { label: "Request ID",    value: `<span style="font-family:monospace;">${escapeHtml(data.requestId)}</span>` },
      ...(data.dealTitle ? [{ label: "Deal", value: escapeHtml(data.dealTitle) }] : []),
      { label: "Reason",        value: escapeHtml(formatReasonCode(data.reasonCode)) },
      { label: "Review Time",   value: "Up to 7 business days" },
    ])}

    <p style="margin:16px 0;color:#424242;line-height:1.7;">
      The merchant has <strong>48 hours</strong> to respond. If they don't, or if you're
      unsatisfied with their decision, you can request a platform review and our team
      will step in within 3 business days.
    </p>

    <p style="margin:0;font-size:13px;color:#757575;line-height:1.6;">
      Questions? Contact us at
      <a href="mailto:support@crunchyplum.com" style="color:#E53935;">support@crunchyplum.com</a>
      and reference your Request ID.
    </p>
  `;

  return {
    subject,
    html: wrapInLayout({ subject, body }),
  };
}
