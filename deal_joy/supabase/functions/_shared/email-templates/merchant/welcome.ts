// =============================================================
// M1 — 商家注册欢迎邮件
// 触发：merchant-register 新商家首次提交注册后（非重新提交）
// =============================================================

import { wrapInLayout, escapeHtml, buildInfoTable } from "../base-layout.ts";

export interface M1MerchantWelcomeData {
  merchantName: string;
  applicationId: string;  // merchantId，作为申请参考编号
  dashboardUrl?: string;
}

export function buildM1Email(data: M1MerchantWelcomeData): { subject: string; html: string } {
  const subject = "Welcome to CrunchyPlum — your application is being reviewed";
  const dashboardUrl = data.dashboardUrl ?? "https://merchant.crunchyplum.com";

  const body = `
    <p style="margin:0 0 16px;font-size:22px;font-weight:700;color:#212121;">
      Welcome to CrunchyPlum! 🍒
    </p>

    <p style="margin:0 0 16px;color:#424242;line-height:1.7;">
      Hi ${escapeHtml(data.merchantName)}, thank you for applying to join CrunchyPlum!
      We're excited to have you on board. Our team will review your application
      and get back to you within <strong>1–3 business days</strong>.
    </p>

    ${buildInfoTable([
      { label: "Application ID", value: `<span style="font-family:monospace;">${escapeHtml(data.applicationId.substring(0, 8).toUpperCase())}</span>` },
      { label: "Status",         value: '<span style="color:#F57C00;font-weight:600;">Under Review</span>' },
      { label: "Review Time",    value: "1–3 business days" },
    ])}

    <p style="margin:16px 0;color:#424242;line-height:1.7;">
      While you wait, here's what happens next:
    </p>

    <ol style="margin:0 0 16px;padding-left:20px;color:#424242;line-height:2;">
      <li>Our team verifies your business documents</li>
      <li>You'll receive an approval or follow-up email</li>
      <li>Once approved, your merchant dashboard becomes fully active</li>
    </ol>

    <p style="margin:0;font-size:13px;color:#757575;line-height:1.6;">
      Questions? Contact us at
      <a href="mailto:merchants@crunchyplum.com" style="color:#E53935;">merchants@crunchyplum.com</a>.
    </p>
  `;

  return {
    subject,
    html: wrapInLayout({ subject, body, cta: { label: "View Merchant Dashboard", url: dashboardUrl } }),
  };
}
