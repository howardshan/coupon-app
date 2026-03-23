// =============================================================
// C3 — Coupon 核销成功通知（发给客户）
// 触发：merchant-scan /redeem 核销成功后
// =============================================================

import { wrapInLayout, escapeHtml, formatCurrency, buildInfoTable } from "../base-layout.ts";

export interface C3CouponRedeemedData {
  dealTitle:      string;
  merchantName:   string;
  redeemedAt:     string;   // ISO 8601
  unitPrice:      number;
}

export function buildC3Email(data: C3CouponRedeemedData): { subject: string; html: string } {
  const subject = `Voucher redeemed at ${data.merchantName}`;

  const redeemedDate = new Date(data.redeemedAt).toLocaleString("en-US", {
    month: "short", day: "numeric", year: "numeric",
    hour: "numeric", minute: "2-digit", hour12: true,
    timeZone: "America/Chicago",
  });

  const body = `
    <p style="margin:0 0 16px;font-size:22px;font-weight:700;color:#212121;">
      Voucher redeemed successfully ✓
    </p>

    <p style="margin:0 0 16px;color:#424242;line-height:1.7;">
      Your CrunchyPlum voucher has been redeemed. We hope you enjoyed the experience!
    </p>

    ${buildInfoTable([
      { label: "Deal",         value: escapeHtml(data.dealTitle) },
      { label: "Redeemed at",  value: escapeHtml(data.merchantName) },
      { label: "Date & Time",  value: redeemedDate },
      { label: "Value",        value: formatCurrency(data.unitPrice) },
    ])}

    <p style="margin:16px 0 0;font-size:13px;color:#757575;line-height:1.6;">
      If you have any issues with your experience, please contact us at
      <a href="mailto:support@crunchyplum.com" style="color:#E53935;">support@crunchyplum.com</a>
      within 7 days.
    </p>
  `;

  return {
    subject,
    html: wrapInLayout({ subject, body }),
  };
}
