// =============================================================
// A4 — 大额退款告警（发给管理员）
// 触发：create-refund 中退款金额超过阈值（$200）时
// =============================================================

import { wrapInLayout, escapeHtml, formatCurrency, buildInfoTable } from "../base-layout.ts";

export interface A4LargeRefundAlertData {
  orderId: string;
  refundAmount: number;
  refundMethod: "store_credit" | "original_payment";
  dealTitle?: string;
  threshold: number;         // 触发阈值（如 200）
  dashboardUrl?: string;
}

export function buildA4Email(data: A4LargeRefundAlertData): { subject: string; html: string } {
  const subject = `[Alert] Large refund issued — ${formatCurrency(data.refundAmount)}`;
  const dashboardUrl = data.dashboardUrl ?? `https://admin.crunchyplum.com/orders`;

  const refundMethodLabel = data.refundMethod === "store_credit"
    ? '<span style="color:#1565C0;font-weight:600;">Store Credit</span>'
    : '<span style="color:#E65100;font-weight:600;">Original Payment Method</span>';

  const body = `
    <p style="margin:0 0 16px;font-size:22px;font-weight:700;color:#C62828;">
      ⚠️ Large refund alert
    </p>

    <p style="margin:0 0 16px;color:#424242;line-height:1.7;">
      A refund exceeding the alert threshold of <strong>${formatCurrency(data.threshold)}</strong>
      has been automatically issued. Please review this transaction.
    </p>

    ${buildInfoTable([
      { label: "Order ID",      value: `<span style="font-family:monospace;">${escapeHtml(data.orderId.slice(0, 8).toUpperCase())}</span>` },
      ...(data.dealTitle ? [{ label: "Deal", value: escapeHtml(data.dealTitle) }] : []),
      { label: "Refund Amount", value: `<strong style="font-size:18px;color:#C62828;">${formatCurrency(data.refundAmount)}</strong>` },
      { label: "Method",        value: refundMethodLabel },
    ])}

    <p style="margin:16px 0 0;font-size:13px;color:#757575;line-height:1.6;">
      This is an automated alert. No immediate action is required unless the refund
      appears fraudulent or erroneous.
    </p>
  `;

  return {
    subject,
    html: wrapInLayout({ subject, body, cta: { label: "View Order", url: dashboardUrl } }),
  };
}
