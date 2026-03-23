// =============================================================
// M6 — Deal 即将过期提醒（发给商家）
// 触发：notify-expiring-deals Cron Job（每日一次）
// user_configurable = true（商家可在设置中关闭）
// =============================================================

import { wrapInLayout, escapeHtml, formatDate, buildInfoTable } from "../base-layout.ts";

export interface M6ExpiringDeal {
  dealTitle: string;
  expiresAt: string;   // ISO 时间字符串
  daysLeft: number;
  totalSold: number;
  stockLimit: number;
}

export interface M6DealExpiringData {
  merchantName: string;
  deals: M6ExpiringDeal[];
  dashboardUrl?: string;
}

export function buildM6Email(data: M6DealExpiringData): { subject: string; html: string } {
  const count = data.deals.length;
  const dashboardUrl = data.dashboardUrl ?? "https://merchant.crunchyplum.com/deals";

  const subject = count === 1
    ? `Your deal "${data.deals[0].dealTitle}" expires in ${data.deals[0].daysLeft} day${data.deals[0].daysLeft === 1 ? "" : "s"}`
    : `${count} of your deals are expiring soon`;

  const dealRows = data.deals.map((d) => {
    const daysLabel = d.daysLeft <= 1
      ? '<span style="color:#C62828;font-weight:600;">Tomorrow</span>'
      : `<span style="color:#E65100;font-weight:600;">${d.daysLeft} days</span>`;
    const soldPct = d.stockLimit > 0 ? Math.round((d.totalSold / d.stockLimit) * 100) : 0;
    return `
      <tr>
        <td style="padding:10px 16px;border-bottom:1px solid #F5F5F5;">
          <div style="font-weight:600;color:#212121;">${escapeHtml(d.dealTitle)}</div>
          <div style="font-size:12px;color:#757575;margin-top:2px;">Sold: ${d.totalSold} / ${d.stockLimit} (${soldPct}%)</div>
        </td>
        <td style="padding:10px 16px;border-bottom:1px solid #F5F5F5;text-align:right;white-space:nowrap;">
          ${daysLabel}<br>
          <span style="font-size:12px;color:#9E9E9E;">${formatDate(d.expiresAt)}</span>
        </td>
      </tr>`;
  }).join("");

  const body = `
    <p style="margin:0 0 16px;font-size:22px;font-weight:700;color:#212121;">
      Your deal${count > 1 ? "s are" : " is"} expiring soon
    </p>

    <p style="margin:0 0 16px;color:#424242;line-height:1.7;">
      Hi ${escapeHtml(data.merchantName)}, the following deal${count > 1 ? "s" : ""} will expire soon.
      Consider extending or renewing ${count > 1 ? "them" : "it"} to keep attracting customers.
    </p>

    <table style="width:100%;border-collapse:collapse;border:1px solid #EEEEEE;border-radius:6px;overflow:hidden;margin-bottom:16px;">
      <thead>
        <tr style="background:#FAFAFA;">
          <th style="padding:10px 16px;text-align:left;font-size:12px;color:#757575;font-weight:600;text-transform:uppercase;letter-spacing:0.5px;">Deal</th>
          <th style="padding:10px 16px;text-align:right;font-size:12px;color:#757575;font-weight:600;text-transform:uppercase;letter-spacing:0.5px;">Expires</th>
        </tr>
      </thead>
      <tbody>
        ${dealRows}
      </tbody>
    </table>

    <p style="margin:0;font-size:13px;color:#757575;line-height:1.6;">
      Manage your deals in the merchant dashboard. Extending a deal keeps existing
      sold coupons valid and allows new customers to purchase.
    </p>
  `;

  return {
    subject,
    html: wrapInLayout({ subject, body, cta: { label: "Manage Deals", url: dashboardUrl } }),
  };
}
