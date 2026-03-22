// =============================================================
// C13 — 商家已回复售后通知（发给客户）
// 触发：merchant-after-sales approve 或 reject 成功后
// user_configurable = true（客户可在设置中关闭）
// =============================================================

import { wrapInLayout, escapeHtml, formatCurrency, buildInfoTable } from "../base-layout.ts";

export interface C13MerchantRepliedData {
  requestId: string;
  merchantName: string;
  decision: "approved" | "rejected";
  merchantNote?: string;
  refundAmount?: number;   // approve 时有值
  dealTitle?: string;
}

export function buildC13Email(data: C13MerchantRepliedData): { subject: string; html: string } {
  const isApproved = data.decision === "approved";

  const subject = isApproved
    ? `Your after-sales request has been approved by ${data.merchantName}`
    : `Update on your after-sales request from ${data.merchantName}`;

  const statusRow = isApproved
    ? { label: "Decision", value: '<span style="color:#2E7D32;font-weight:600;">Approved ✓</span>' }
    : { label: "Decision", value: '<span style="color:#C62828;font-weight:600;">Rejected</span>' };

  const rows = [
    { label: "Request ID",   value: `<span style="font-family:monospace;">${escapeHtml(data.requestId)}</span>` },
    ...(data.dealTitle ? [{ label: "Deal", value: escapeHtml(data.dealTitle) }] : []),
    statusRow,
    ...(isApproved && data.refundAmount
      ? [{ label: "Refund Amount", value: `<strong>${formatCurrency(data.refundAmount)}</strong>` }]
      : []),
    ...(data.merchantNote
      ? [{ label: "Merchant Note", value: `<em>"${escapeHtml(data.merchantNote)}"</em>` }]
      : []),
  ];

  const nextStep = isApproved
    ? `Your refund of <strong>${formatCurrency(data.refundAmount ?? 0)}</strong> is being processed.
       You will receive a separate notification once the refund has been issued.`
    : `If you disagree with this decision, you can request a <strong>platform review</strong>
       through the CrunchyPlum app. Our team will step in and make a final decision within 3 business days.`;

  const body = `
    <p style="margin:0 0 16px;font-size:22px;font-weight:700;color:#212121;">
      ${isApproved ? "After-sales request approved ✓" : "Merchant has responded to your request"}
    </p>

    <p style="margin:0 0 16px;color:#424242;line-height:1.7;">
      ${escapeHtml(data.merchantName)} has reviewed your after-sales request and provided a response.
    </p>

    ${buildInfoTable(rows)}

    <p style="margin:16px 0 0;color:#424242;line-height:1.7;">
      ${nextStep}
    </p>

    <p style="margin:16px 0 0;font-size:13px;color:#757575;line-height:1.6;">
      Questions? Contact us at
      <a href="mailto:support@crunchyplum.com" style="color:#E53935;">support@crunchyplum.com</a>.
    </p>
  `;

  return {
    subject,
    html: wrapInLayout({ subject, body }),
  };
}
