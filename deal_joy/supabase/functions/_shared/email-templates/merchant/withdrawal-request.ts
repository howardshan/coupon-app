// =============================================================
// M14 — 提现申请已收到（发给商家）
// 触发：merchant-withdrawal handleWithdraw 成功后
// =============================================================

import { wrapInLayout, escapeHtml, formatCurrency, buildInfoTable } from "../base-layout.ts";

export interface M14WithdrawalRequestData {
  merchantName: string;
  withdrawalId: string;
  amount: number;
  requestedAt: string;       // ISO 时间字符串
  dashboardUrl?: string;
}

export function buildM14Email(data: M14WithdrawalRequestData): { subject: string; html: string } {
  const subject = `Withdrawal request received — ${formatCurrency(data.amount)}`;
  const dashboardUrl = data.dashboardUrl ?? "https://merchant.crunchyplum.com/earnings";

  const body = `
    <p style="margin:0 0 16px;font-size:22px;font-weight:700;color:#212121;">
      Withdrawal request received ✓
    </p>

    <p style="margin:0 0 16px;color:#424242;line-height:1.7;">
      Hi ${escapeHtml(data.merchantName)}, we've received your withdrawal request and it is
      now being reviewed by our finance team.
    </p>

    ${buildInfoTable([
      { label: "Request ID",   value: `<span style="font-family:monospace;">${escapeHtml(data.withdrawalId.slice(0, 8).toUpperCase())}</span>` },
      { label: "Amount",       value: `<strong style="font-size:18px;">${formatCurrency(data.amount)}</strong>` },
      { label: "Status",       value: '<span style="color:#F57C00;font-weight:600;">Pending Review</span>' },
    ])}

    <p style="margin:16px 0 0;font-size:13px;color:#757575;line-height:1.6;">
      Withdrawals are typically processed within 3–5 business days. You will receive
      a confirmation email once the transfer has been completed.
      Questions? Contact <a href="mailto:merchant@crunchyplum.com" style="color:#E53935;">merchant@crunchyplum.com</a>.
    </p>
  `;

  return {
    subject,
    html: wrapInLayout({ subject, body, cta: { label: "View Earnings", url: dashboardUrl } }),
  };
}
