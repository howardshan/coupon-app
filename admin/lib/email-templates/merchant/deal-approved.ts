// =============================================================
// M17 — Deal 审批通过通知（Admin Next.js 版本）
// 触发：setDealActive Server Action（active = true 时）
// =============================================================

import { wrapInLayout, escapeHtml, buildInfoTable, formatDate } from '../base-layout'

export interface M17DealApprovedData {
  merchantName: string
  dealTitle:    string
  publishedAt?: string   // ISO 字符串，有则显示上线时间
  dashboardUrl?: string
}

export function buildM17Email(data: M17DealApprovedData): { subject: string; html: string } {
  const subject = `Your deal "${data.dealTitle}" is now live!`
  const dashboardUrl = data.dashboardUrl ?? 'https://merchant.crunchyplum.com/deals'

  const tableRows = [
    { label: 'Deal Name', value: `<strong>${escapeHtml(data.dealTitle)}</strong>` },
    { label: 'Status',    value: '<span style="color:#2E7D32;font-weight:600;">✓ Live — visible to customers</span>' },
    ...(data.publishedAt
      ? [{ label: 'Published', value: formatDate(data.publishedAt) }]
      : []),
  ]

  const body = `
    <p style="margin:0 0 16px;font-size:22px;font-weight:700;color:#212121;">
      Your deal is live! 🎉
    </p>

    <p style="margin:0 0 16px;color:#424242;line-height:1.7;">
      Hi ${escapeHtml(data.merchantName)}, great news — your deal has been reviewed and
      approved by our team. It is now visible to customers on CrunchyPlum.
    </p>

    ${buildInfoTable(tableRows)}

    <p style="margin:20px 0 8px;font-size:14px;font-weight:600;color:#212121;">
      What happens next:
    </p>
    <ul style="margin:0 0 20px;padding-left:20px;color:#424242;font-size:14px;line-height:2;">
      <li>Customers can now discover and purchase vouchers for your deal</li>
      <li>You will receive an email notification for each new order</li>
      <li>Use the Scan page in your dashboard to redeem vouchers</li>
    </ul>

    <p style="margin:0;font-size:13px;color:#757575;line-height:1.6;">
      Questions? Contact us at
      <a href="mailto:support@crunchyplum.com" style="color:#E53935;">support@crunchyplum.com</a>.
    </p>
  `

  return {
    subject,
    html: wrapInLayout({
      subject,
      body,
      cta: { label: 'View My Deals', url: dashboardUrl },
    }),
  }
}
