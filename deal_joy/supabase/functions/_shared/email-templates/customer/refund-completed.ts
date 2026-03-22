// =============================================================
// C8 — Stripe 退款到账通知（原支付方式退款成功，发给客户）
// 触发：stripe-webhook charge.refunded 事件处理完成后
// =============================================================

import { wrapInLayout, escapeHtml, formatCurrency, buildInfoTable } from "../base-layout.ts";

export interface C8RefundCompletedData {
  refundAmount: number;
  cardLast4?: string;   // 银行卡末四位，从 Stripe charge 对象获取
  dealTitle?: string;   // 可选，有则显示
}

export function buildC8Email(data: C8RefundCompletedData): { subject: string; html: string } {
  const subject = `Your refund of ${formatCurrency(data.refundAmount)} is on its way`;

  const rows = [
    ...(data.dealTitle ? [{ label: "Item", value: escapeHtml(data.dealTitle) }] : []),
    { label: "Refund Amount", value: `<strong style="font-size:18px;">${formatCurrency(data.refundAmount)}</strong>` },
    {
      label: "Refund To",
      value: data.cardLast4
        ? `Original payment method ending in <span style="font-family:monospace;">${escapeHtml(data.cardLast4)}</span>`
        : "Original payment method",
    },
    {
      label: "Timeline",
      value: '<span style="color:#1565C0;">3–5 business days</span> <span style="color:#757575;font-size:12px;">(depending on your bank)</span>',
    },
  ];

  const body = `
    <p style="margin:0 0 16px;font-size:22px;font-weight:700;color:#212121;">
      Refund processed ✓
    </p>

    <p style="margin:0 0 16px;color:#424242;line-height:1.7;">
      Good news! Your refund has been approved and sent to your card.
      Please allow 3–5 business days for it to appear on your statement.
    </p>

    ${buildInfoTable(rows)}

    <p style="margin:16px 0 0;font-size:13px;color:#757575;line-height:1.6;">
      Questions about your refund? Contact us at
      <a href="mailto:support@crunchyplum.com" style="color:#E53935;">support@crunchyplum.com</a>.
    </p>
  `;

  return {
    subject,
    html: wrapInLayout({ subject, body, cta: { label: "Browse Deals", url: "crunchyplum://home" } }),
  };
}
