// =============================================================
// C7 — 退款申请受理确认
// 触发：create-refund 退款请求处理成功后
// =============================================================

import { wrapInLayout, escapeHtml, formatCurrency, buildInfoTable } from "../base-layout.ts";

export interface C7RefundRequestedData {
  refundAmount:  number;
  refundMethod:  "store_credit" | "original_payment";
  dealTitle?:    string;
}

export function buildC7Email(data: C7RefundRequestedData): { subject: string; html: string } {
  const subject = "Your refund has been processed";

  const isStoreCredit = data.refundMethod === "store_credit";

  const methodDetail = isStoreCredit
    ? `<span style="color:#2E7D32;font-weight:600;">Store Credit</span>
       <span style="color:#757575;font-size:12px;">(added to your CrunchyPlum balance instantly)</span>`
    : `<span style="color:#1565C0;font-weight:600;">Original Payment Method</span>
       <span style="color:#757575;font-size:12px;">(3–5 business days)</span>`;

  const timeline = isStoreCredit
    ? `<p style="margin:16px 0;font-size:14px;color:#424242;line-height:1.7;">
         Your store credit has been added to your account and is available to use immediately
         on your next purchase.
       </p>`
    : `<p style="margin:16px 0;font-size:14px;color:#424242;line-height:1.7;">
         Your refund has been submitted to your card issuer. It typically takes
         <strong>3–5 business days</strong> to appear on your statement, depending on your bank.
       </p>`;

  const body = `
    <p style="margin:0 0 16px;font-size:22px;font-weight:700;color:#212121;">
      Refund processed ✓
    </p>

    ${buildInfoTable([
      ...(data.dealTitle ? [{ label: "Item", value: escapeHtml(data.dealTitle) }] : []),
      { label: "Refund Amount",  value: `<strong>${formatCurrency(data.refundAmount)}</strong>` },
      { label: "Refund Method",  value: methodDetail },
    ])}

    ${timeline}

    <p style="margin:0;font-size:13px;color:#757575;line-height:1.6;">
      Questions? Contact us at
      <a href="mailto:support@crunchyplum.com" style="color:#E53935;">support@crunchyplum.com</a>.
    </p>
  `;

  return {
    subject,
    html: wrapInLayout({ subject, body }),
  };
}
