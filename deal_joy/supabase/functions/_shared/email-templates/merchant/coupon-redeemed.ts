// =============================================================
// M7 — Coupon 核销成功通知（发给商家）
// 触发：merchant-scan /redeem 核销成功后
// =============================================================

import { wrapInLayout, escapeHtml, formatCurrency, buildInfoTable } from "../base-layout.ts";

export interface M7CouponRedeemedData {
  merchantName:  string;
  dealTitle:     string;
  couponCode:    string;    // 已脱敏，如 "****1234"
  redeemedAt:    string;    // ISO 8601
  unitPrice:     number;
  dashboardUrl?: string;
}

export function buildM7Email(data: M7CouponRedeemedData): { subject: string; html: string } {
  const subject = `Voucher redeemed — ${data.dealTitle}`;
  const dashboardUrl = data.dashboardUrl ?? "https://merchant.crunchyplum.com/orders";

  const redeemedDate = new Date(data.redeemedAt).toLocaleString("en-US", {
    month: "short", day: "numeric", year: "numeric",
    hour: "numeric", minute: "2-digit", hour12: true,
    timeZone: "America/Chicago",
  });

  const body = `
    <p style="margin:0 0 16px;font-size:22px;font-weight:700;color:#212121;">
      Voucher redeemed ✓
    </p>

    <p style="margin:0 0 16px;color:#424242;line-height:1.7;">
      Hi ${escapeHtml(data.merchantName)}, a customer voucher has just been redeemed at your store.
    </p>

    ${buildInfoTable([
      { label: "Deal",         value: escapeHtml(data.dealTitle) },
      { label: "Voucher Code", value: `<span style="font-family:monospace;">${escapeHtml(data.couponCode)}</span>` },
      { label: "Redeemed At",  value: redeemedDate },
      { label: "Deal Value",   value: formatCurrency(data.unitPrice) },
    ])}

    <p style="margin:16px 0 0;font-size:13px;color:#757575;line-height:1.6;">
      This redemption has been recorded. You can view your full redemption history
      and earnings in your dashboard.
    </p>
  `;

  return {
    subject,
    html: wrapInLayout({ subject, body, cta: { label: "View Redemption History", url: dashboardUrl } }),
  };
}
