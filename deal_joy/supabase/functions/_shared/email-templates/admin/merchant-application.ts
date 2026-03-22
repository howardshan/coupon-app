// =============================================================
// A2 — 新商户认证申请提醒（发给管理员）
// 触发：merchant-register 提交成功后
// =============================================================

import { wrapInLayout, escapeHtml, formatDate, buildInfoTable } from "../base-layout.ts";

export interface A2MerchantApplicationData {
  merchantName: string;
  contactEmail: string;
  submittedAt: string;       // ISO 8601
  merchantId: string;
  isResubmission?: boolean;
  dashboardUrl?: string;
}

export function buildA2Email(data: A2MerchantApplicationData): { subject: string; html: string } {
  const subject = data.isResubmission
    ? `[Resubmission] Merchant application updated — ${data.merchantName}`
    : `New merchant application — ${data.merchantName}`;

  const dashboardUrl = data.dashboardUrl
    ?? `https://admin.crunchyplum.com/merchants/${data.merchantId}`;

  const submittedDate = formatDate(data.submittedAt);

  const body = `
    <p style="margin:0 0 16px;font-size:22px;font-weight:700;color:#212121;">
      ${data.isResubmission ? "Merchant resubmitted application" : "New merchant application received"}
    </p>

    <p style="margin:0 0 16px;color:#424242;line-height:1.7;">
      A merchant has ${data.isResubmission ? "updated and resubmitted" : "submitted"} their application
      and is awaiting review.
    </p>

    ${buildInfoTable([
      { label: "Business Name",  value: escapeHtml(data.merchantName) },
      { label: "Contact Email",  value: escapeHtml(data.contactEmail) },
      { label: "Submitted At",   value: submittedDate },
      { label: "Merchant ID",    value: `<span style="font-family:monospace;font-size:12px;">${escapeHtml(data.merchantId)}</span>` },
      { label: "Type",           value: data.isResubmission
          ? '<span style="color:#F57C00;font-weight:600;">Resubmission</span>'
          : '<span style="color:#1565C0;font-weight:600;">New Application</span>' },
    ])}

    <p style="margin:16px 0 0;font-size:13px;color:#757575;line-height:1.6;">
      Please review the application within 1–3 business days.
    </p>
  `;

  return {
    subject,
    html: wrapInLayout({ subject, body, cta: { label: "Review Application", url: dashboardUrl } }),
  };
}
