// =============================================================
// C14 — 管理员拒绝退款通知（发给客户）
// 触发：admin-refund Edge Function reject 分支
// 场景：用户核销后申请退款 → 商家拒绝 → 升级管理员 → 管理员最终拒绝
// =============================================================

import { wrapInLayout, escapeHtml, formatCurrency, buildInfoTable } from "../base-layout.ts";

export interface C14AdminRefundRejectedData {
  orderNumber:   string;
  refundAmount:  number;
  adminReason:   string;
  supportUrl?:   string;
}

export function buildC14Email(data: C14AdminRefundRejectedData): { subject: string; html: string } {
  const subject = `Update on your refund request — Order ${data.orderNumber}`;
  const supportUrl = data.supportUrl ?? "mailto:support@crunchyplum.com";

  const rows = [
    { label: "Order",          value: `<span style="font-family:monospace;">${escapeHtml(data.orderNumber)}</span>` },
    { label: "Refund Amount",  value: formatCurrency(data.refundAmount) },
    { label: "Decision",       value: '<span style="color:#C62828;font-weight:600;">Refund Request Declined</span>' },
  ];

  const body = `
    <p style="margin:0 0 16px;font-size:22px;font-weight:700;color:#212121;">
      Refund request outcome
    </p>

    <p style="margin:0 0 16px;color:#424242;line-height:1.7;">
      We have completed our review of your refund request. After careful consideration,
      we are unable to approve the refund for the following reason:
    </p>

    ${buildInfoTable(rows)}

    <table width="100%" cellpadding="0" cellspacing="0" border="0" style="margin:16px 0;">
      <tr>
        <td style="background:#FFF3E0;border-left:3px solid #FF6F00;
                   padding:14px 16px;border-radius:4px;
                   font-size:14px;color:#4E342E;line-height:1.6;">
          <strong>Reason for declining:</strong><br />
          ${escapeHtml(data.adminReason)}
        </td>
      </tr>
    </table>

    <p style="margin:16px 0 8px;font-size:14px;color:#424242;line-height:1.7;">
      This decision is final. If you believe this is a mistake or have additional
      information to share, please reach out to our support team — we are happy to help.
    </p>

    <p style="margin:0;font-size:13px;color:#757575;line-height:1.6;">
      Contact us at
      <a href="mailto:support@crunchyplum.com" style="color:#E53935;">support@crunchyplum.com</a>
      and reference your order number <strong>${escapeHtml(data.orderNumber)}</strong>.
    </p>
  `;

  return {
    subject,
    html: wrapInLayout({
      subject,
      body,
      cta: { label: "Contact Support", url: supportUrl },
    }),
  };
}
