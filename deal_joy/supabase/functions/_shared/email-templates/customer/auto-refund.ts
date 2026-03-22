// =============================================================
// C5 — 到期自动退款通知（含 Store Credit 到账信息）
// 触发：auto-refund-expired Cron Job 每条成功退款后
// =============================================================

import { wrapInLayout, escapeHtml, formatCurrency, buildInfoTable } from "../base-layout.ts";

export interface C5AutoRefundData {
  refundAmount: number;
  dealTitle?:   string;    // 可选，有则显示
}

export function buildC5Email(data: C5AutoRefundData): { subject: string; html: string } {
  const subject = "Your expired voucher has been refunded";

  const body = `
    <p style="margin:0 0 16px;font-size:22px;font-weight:700;color:#212121;">
      Voucher expired — refund added to your account
    </p>

    <p style="margin:0 0 16px;color:#424242;line-height:1.7;">
      One of your vouchers has passed its expiry date. As part of our
      <strong>"buy now, refund anytime"</strong> promise, we've automatically added
      the full amount back to your CrunchyPlum Store Credit balance.
    </p>

    ${buildInfoTable([
      ...(data.dealTitle ? [{ label: "Voucher", value: escapeHtml(data.dealTitle) }] : []),
      { label: "Refund Amount", value: `<strong>${formatCurrency(data.refundAmount)}</strong>` },
      { label: "Refund Method", value: '<span style="color:#2E7D32;font-weight:600;">Store Credit</span> <span style="color:#757575;font-size:12px;">(available immediately)</span>' },
    ])}

    <p style="margin:16px 0;font-size:14px;color:#424242;line-height:1.7;">
      Your store credit is ready to use on any deal — no expiry on the credit itself.
    </p>

    <p style="margin:0;font-size:13px;color:#757575;line-height:1.6;">
      Questions? Contact us at
      <a href="mailto:support@crunchyplum.com" style="color:#E53935;">support@crunchyplum.com</a>.
    </p>
  `;

  return {
    subject,
    html: wrapInLayout({ subject, body, cta: { label: "Browse Deals", url: "crunchyplum://home" } }),
  };
}
