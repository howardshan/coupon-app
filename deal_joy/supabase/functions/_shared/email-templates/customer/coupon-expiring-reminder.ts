// =============================================================
// C4 — 券即将过期提醒（发给客户）
// 触发：notify-expiring-coupons Cron Job（每日一次）
// user_configurable = true（客户可在设置中关闭）
// =============================================================

import { wrapInLayout, escapeHtml, formatDate, buildInfoTable } from "../base-layout.ts";

export interface C4ExpiringCoupon {
  dealTitle: string;
  merchantName: string;
  expiresAt: string;   // ISO 时间字符串
  daysLeft: number;
}

export interface C4CouponExpiringData {
  coupons: C4ExpiringCoupon[];
}

export function buildC4Email(data: C4CouponExpiringData): { subject: string; html: string } {
  const count = data.coupons.length;
  const subject = count === 1
    ? `Reminder: your coupon expires in ${data.coupons[0].daysLeft} day${data.coupons[0].daysLeft === 1 ? "" : "s"}`
    : `Reminder: ${count} of your coupons are expiring soon`;

  // 为每张券生成一行 info table
  const couponRows = data.coupons.map((c) => {
    const daysLabel = c.daysLeft <= 1
      ? '<span style="color:#C62828;font-weight:600;">Expires tomorrow</span>'
      : `<span style="color:#E65100;font-weight:600;">Expires in ${c.daysLeft} days</span>`;
    return `
      <tr>
        <td style="padding:10px 16px;border-bottom:1px solid #F5F5F5;">
          <div style="font-weight:600;color:#212121;">${escapeHtml(c.dealTitle)}</div>
          <div style="font-size:12px;color:#757575;margin-top:2px;">${escapeHtml(c.merchantName)}</div>
        </td>
        <td style="padding:10px 16px;border-bottom:1px solid #F5F5F5;text-align:right;white-space:nowrap;">
          ${daysLabel}<br>
          <span style="font-size:12px;color:#9E9E9E;">${formatDate(c.expiresAt)}</span>
        </td>
      </tr>`;
  }).join("");

  const body = `
    <p style="margin:0 0 16px;font-size:22px;font-weight:700;color:#212121;">
      Don't let your coupon${count > 1 ? "s" : ""} expire!
    </p>

    <p style="margin:0 0 16px;color:#424242;line-height:1.7;">
      You have ${count} coupon${count > 1 ? "s" : ""} expiring soon. Use ${count > 1 ? "them" : "it"} before ${count > 1 ? "they expire" : "it expires"}.
    </p>

    <table style="width:100%;border-collapse:collapse;border:1px solid #EEEEEE;border-radius:6px;overflow:hidden;margin-bottom:16px;">
      <thead>
        <tr style="background:#FAFAFA;">
          <th style="padding:10px 16px;text-align:left;font-size:12px;color:#757575;font-weight:600;text-transform:uppercase;letter-spacing:0.5px;">Deal</th>
          <th style="padding:10px 16px;text-align:right;font-size:12px;color:#757575;font-weight:600;text-transform:uppercase;letter-spacing:0.5px;">Expires</th>
        </tr>
      </thead>
      <tbody>
        ${couponRows}
      </tbody>
    </table>

    <p style="margin:0;font-size:13px;color:#757575;line-height:1.6;">
      Open the CrunchyPlum app to view and use your coupons.
      Expired coupons are automatically refunded to your account.
    </p>
  `;

  return {
    subject,
    html: wrapInLayout({ subject, body, cta: { label: "View My Coupons", url: "crunchyplum://coupons" } }),
  };
}
