// =============================================================
// A7 — 提现申请待审（发给管理员）
// 触发：merchant-withdrawal handleWithdraw 成功后
// =============================================================

import { wrapInLayout, escapeHtml, formatCurrency, buildInfoTable } from "../base-layout.ts";

export interface A7WithdrawalPendingData {
  merchantName: string;
  merchantId: string;
  withdrawalId: string;
  amount: number;
  requestedAt: string;       // ISO 时间字符串
  dashboardUrl?: string;
}

export function buildA7Email(data: A7WithdrawalPendingData): { subject: string; html: string } {
  const subject = `[Action Required] Withdrawal request — ${data.merchantName} — ${formatCurrency(data.amount)}`;
  const dashboardUrl = data.dashboardUrl ?? `https://admin.crunchyplum.com/finance`;

  const body = `
    <p style="margin:0 0 16px;font-size:22px;font-weight:700;color:#212121;">
      New withdrawal request pending review
    </p>

    <p style="margin:0 0 16px;color:#424242;line-height:1.7;">
      A merchant has submitted a withdrawal request that requires manual review and processing.
    </p>

    ${buildInfoTable([
      { label: "Merchant",     value: escapeHtml(data.merchantName) },
      { label: "Merchant ID",  value: `<span style="font-family:monospace;font-size:12px;">${escapeHtml(data.merchantId)}</span>` },
      { label: "Request ID",   value: `<span style="font-family:monospace;">${escapeHtml(data.withdrawalId.slice(0, 8).toUpperCase())}</span>` },
      { label: "Amount",       value: `<strong style="font-size:18px;">${formatCurrency(data.amount)}</strong>` },
      { label: "Status",       value: '<span style="color:#F57C00;font-weight:600;">Pending Review</span>' },
    ])}

    <p style="margin:16px 0 0;font-size:13px;color:#757575;line-height:1.6;">
      Please review the merchant's balance and process the transfer in the admin dashboard.
    </p>
  `;

  return {
    subject,
    html: wrapInLayout({ subject, body, cta: { label: "Review in Dashboard", url: dashboardUrl } }),
  };
}
