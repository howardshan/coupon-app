// =============================================================
// M13 — 月度结算报告（发给商家）
// 触发：monthly-settlement-report Cron Job（每月 1 日 UTC 02:00）
// user_configurable = true（商家可在设置中关闭）
// =============================================================

import { wrapInLayout, escapeHtml, formatCurrency, buildInfoTable } from "../base-layout.ts";

export interface M13MonthlySettlementData {
  merchantName: string;
  month: string;              // 格式: "March 2026"
  totalRevenue: number;       // 税前总收入
  platformFee: number;        // 平台抽成
  stripeFee: number;          // Stripe 手续费
  netAmount: number;          // 实际结算金额
  refundedAmount: number;     // 退款总额
  pendingSettlement: number;  // 待结算金额
  dashboardUrl?: string;
}

export function buildM13Email(data: M13MonthlySettlementData): { subject: string; html: string } {
  const subject = `Your monthly settlement report — ${data.month}`;
  const dashboardUrl = data.dashboardUrl ?? "https://merchant.crunchyplum.com/earnings";

  const body = `
    <p style="margin:0 0 16px;font-size:22px;font-weight:700;color:#212121;">
      Monthly Settlement Report
    </p>

    <p style="margin:0 0 16px;color:#424242;line-height:1.7;">
      Hi ${escapeHtml(data.merchantName)}, here is your earnings summary for
      <strong>${escapeHtml(data.month)}</strong>.
    </p>

    ${buildInfoTable([
      { label: "Gross Revenue",       value: formatCurrency(data.totalRevenue) },
      { label: "Platform Fee",        value: `<span style="color:#C62828;">− ${formatCurrency(data.platformFee)}</span>` },
      { label: "Processing Fee",      value: `<span style="color:#C62828;">− ${formatCurrency(data.stripeFee)}</span>` },
      { label: "Refunds",             value: `<span style="color:#C62828;">− ${formatCurrency(data.refundedAmount)}</span>` },
      { label: "Net Settlement",      value: `<strong style="font-size:18px;color:#2E7D32;">${formatCurrency(data.netAmount)}</strong>` },
      { label: "Pending Settlement",  value: formatCurrency(data.pendingSettlement) },
    ])}

    <p style="margin:16px 0 0;font-size:13px;color:#757575;line-height:1.6;">
      Settlement is processed within 7–10 business days after month end.
      For questions, contact <a href="mailto:merchant@crunchyplum.com" style="color:#E53935;">merchant@crunchyplum.com</a>.
    </p>
  `;

  return {
    subject,
    html: wrapInLayout({ subject, body, cta: { label: "View Full Report", url: dashboardUrl } }),
  };
}
