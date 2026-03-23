// =============================================================
// M2 — 商家认证申请受理通知
// 触发：merchant-register 提交成功后（包含首次提交和重新提交）
// =============================================================

import { wrapInLayout, escapeHtml, buildInfoTable } from "../base-layout.ts";

export interface M2VerificationPendingData {
  merchantName: string;
  applicationId: string;  // merchantId
  isResubmission?: boolean;
}

export function buildM2Email(data: M2VerificationPendingData): { subject: string; html: string } {
  const subject = data.isResubmission
    ? "Your updated application has been received"
    : "Your merchant application has been received";

  const intro = data.isResubmission
    ? `Hi ${escapeHtml(data.merchantName)}, we've received your updated application materials. Our team will review them promptly.`
    : `Hi ${escapeHtml(data.merchantName)}, we've received your merchant application and it's now in our review queue.`;

  const body = `
    <p style="margin:0 0 16px;font-size:22px;font-weight:700;color:#212121;">
      Application received ✓
    </p>

    <p style="margin:0 0 16px;color:#424242;line-height:1.7;">
      ${intro}
    </p>

    ${buildInfoTable([
      { label: "Application ID", value: `<span style="font-family:monospace;">${escapeHtml(data.applicationId.substring(0, 8).toUpperCase())}</span>` },
      { label: "Status",         value: '<span style="color:#F57C00;font-weight:600;">Under Review</span>' },
      { label: "Expected Time",  value: "1–3 business days" },
    ])}

    <p style="margin:16px 0 0;font-size:13px;color:#757575;line-height:1.6;">
      We'll email you as soon as a decision has been made.
      If you have questions, reach us at
      <a href="mailto:merchants@crunchyplum.com" style="color:#E53935;">merchants@crunchyplum.com</a>.
    </p>
  `;

  return {
    subject,
    html: wrapInLayout({ subject, body }),
  };
}
