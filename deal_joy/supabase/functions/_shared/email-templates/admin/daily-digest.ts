// =============================================================
// A3 — 管理员日报（发给管理员）
// 触发：admin-daily-digest Cron Job（每日 UTC 08:00）
// =============================================================

import { wrapInLayout, escapeHtml, formatCurrency, buildInfoTable } from "../base-layout.ts";

export interface A3DailyDigestData {
  date: string;               // YYYY-MM-DD（昨天）
  newOrders: number;
  totalRevenue: number;
  refundCount: number;
  refundAmount: number;
  newUsers: number;
  newMerchants: number;
  openAfterSales: number;     // 当前待处理售后数
  closedAfterSalesYesterday: number;
  dashboardUrl?: string;
}

export function buildA3Email(data: A3DailyDigestData): { subject: string; html: string } {
  const subject = `CrunchyPlum Daily Digest — ${data.date}`;
  const dashboardUrl = data.dashboardUrl ?? "https://admin.crunchyplum.com";

  const body = `
    <p style="margin:0 0 16px;font-size:22px;font-weight:700;color:#212121;">
      Daily Digest — ${escapeHtml(data.date)}
    </p>

    <p style="margin:0 0 16px;color:#424242;line-height:1.7;">
      Here is a summary of yesterday's platform activity.
    </p>

    <p style="margin:0 0 8px;font-size:14px;font-weight:600;color:#616161;text-transform:uppercase;letter-spacing:0.5px;">
      Orders &amp; Revenue
    </p>
    ${buildInfoTable([
      { label: "New Orders",     value: `<strong>${data.newOrders}</strong>` },
      { label: "Total Revenue",  value: `<strong style="color:#2E7D32;">${formatCurrency(data.totalRevenue)}</strong>` },
      { label: "Refunds",        value: `${data.refundCount} refunds — ${formatCurrency(data.refundAmount)}` },
    ])}

    <p style="margin:16px 0 8px;font-size:14px;font-weight:600;color:#616161;text-transform:uppercase;letter-spacing:0.5px;">
      Users &amp; Merchants
    </p>
    ${buildInfoTable([
      { label: "New Users",      value: `<strong>${data.newUsers}</strong>` },
      { label: "New Merchants",  value: `<strong>${data.newMerchants}</strong>` },
    ])}

    <p style="margin:16px 0 8px;font-size:14px;font-weight:600;color:#616161;text-transform:uppercase;letter-spacing:0.5px;">
      After-Sales
    </p>
    ${buildInfoTable([
      { label: "Open Cases",            value: data.openAfterSales > 0
          ? `<span style="color:#C62828;font-weight:600;">${data.openAfterSales} pending</span>`
          : `<span style="color:#2E7D32;">None</span>` },
      { label: "Closed Yesterday",      value: `${data.closedAfterSalesYesterday}` },
    ])}

    <p style="margin:16px 0 0;font-size:13px;color:#757575;line-height:1.6;">
      This is an automated daily summary. View full analytics in the admin dashboard.
    </p>
  `;

  return {
    subject,
    html: wrapInLayout({ subject, body, cta: { label: "Open Dashboard", url: dashboardUrl } }),
  };
}
