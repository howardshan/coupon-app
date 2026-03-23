// =============================================================
// M15 — 提现已完成（发给商家）
// 触发：提现完成（Stripe Transfer webhook 或管理员手动确认）
// =============================================================

import { wrapInLayout, escapeHtml, formatCurrency, buildInfoTable } from "../base-layout.ts";

export interface M15WithdrawalCompletedData {
  merchantName: string;
  withdrawalId: string;
  amount: number;
  completedAt: string;       // ISO 时间字符串
  last4?: string;            // 银行账户末四位（可选）
  dashboardUrl?: string;
}

export function buildM15Email(data: M15WithdrawalCompletedData): { subject: string; html: string } {
  const subject = `Your withdrawal of ${formatCurrency(data.amount)} has been sent`;
  const dashboardUrl = data.dashboardUrl ?? "https://merchant.crunchyplum.com/earnings";

  const accountLabel = data.last4
    ? `Bank account ending in <strong>${escapeHtml(data.last4)}</strong>`
    : "Your registered bank account";

  const body = `
    <p style="margin:0 0 16px;font-size:22px;font-weight:700;color:#212121;">
      Withdrawal completed ✓
    </p>

    <p style="margin:0 0 16px;color:#424242;line-height:1.7;">
      Hi ${escapeHtml(data.merchantName)}, your withdrawal has been processed and the
      funds are on their way.
    </p>

    ${buildInfoTable([
      { label: "Request ID",  value: `<span style="font-family:monospace;">${escapeHtml(data.withdrawalId.slice(0, 8).toUpperCase())}</span>` },
      { label: "Amount",      value: `<strong style="font-size:18px;color:#2E7D32;">${formatCurrency(data.amount)}</strong>` },
      { label: "Sent To",     value: accountLabel },
      { label: "Status",      value: '<span style="color:#2E7D32;font-weight:600;">Completed ✓</span>' },
    ])}

    <p style="margin:16px 0 0;font-size:13px;color:#757575;line-height:1.6;">
      Funds typically arrive within 1–3 business days depending on your bank.
      View your full earnings history in the merchant dashboard.
    </p>
  `;

  return {
    subject,
    html: wrapInLayout({ subject, body, cta: { label: "View Earnings", url: dashboardUrl } }),
  };
}
