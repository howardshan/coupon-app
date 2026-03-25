// =============================================================
// M18 — 提现失败通知（发给商家）
// 触发：Stripe Transfer 失败（transfer.failed Webhook）
// =============================================================

import { wrapInLayout, escapeHtml, formatCurrency, buildInfoTable } from "../base-layout.ts";

export interface M18WithdrawalFailedData {
  merchantName: string;
  withdrawalId: string;
  amount: number;
  failedAt: string;        // ISO 时间字符串
  failureReason?: string;  // Stripe 失败原因（可选）
  dashboardUrl?: string;
}

export function buildM18Email(data: M18WithdrawalFailedData): { subject: string; html: string } {
  const subject = `Action required: Your withdrawal of ${formatCurrency(data.amount)} could not be processed`;
  const dashboardUrl = data.dashboardUrl ?? "https://merchant.crunchyplum.com/earnings";

  const reasonText = data.failureReason
    ? escapeHtml(data.failureReason)
    : "An unexpected error occurred while processing the transfer.";

  const body = `
    <p style="margin:0 0 16px;font-size:22px;font-weight:700;color:#212121;">
      Withdrawal failed
    </p>

    <p style="margin:0 0 16px;color:#424242;line-height:1.7;">
      Hi ${escapeHtml(data.merchantName)}, we were unable to process your recent withdrawal request.
      No funds have been deducted from your balance.
    </p>

    ${buildInfoTable([
      { label: "Request ID",  value: `<span style="font-family:monospace;">${escapeHtml(data.withdrawalId.slice(0, 8).toUpperCase())}</span>` },
      { label: "Amount",      value: `<strong style="font-size:18px;color:#E53935;">${formatCurrency(data.amount)}</strong>` },
      { label: "Status",      value: '<span style="color:#E53935;font-weight:600;">Failed ✗</span>' },
      { label: "Reason",      value: `<span style="color:#757575;">${reasonText}</span>` },
    ])}

    <p style="margin:16px 0 8px;color:#424242;line-height:1.7;">
      <strong>What to do next:</strong>
    </p>
    <ul style="margin:0 0 16px;padding-left:20px;color:#424242;line-height:1.8;">
      <li>Verify your Stripe account is fully connected and your bank account details are correct.</li>
      <li>Return to the merchant dashboard and try submitting a new withdrawal request.</li>
      <li>If the issue persists, please contact our support team.</li>
    </ul>

    <p style="margin:0;font-size:13px;color:#757575;line-height:1.6;">
      Your available balance remains unchanged and can be withdrawn once the issue is resolved.
    </p>
  `;

  return {
    subject,
    html: wrapInLayout({ subject, body, cta: { label: "Go to Earnings", url: dashboardUrl } }),
  };
}
