// =============================================================
// M3 — 商户认证通过通知（Admin Next.js 版本）
// 触发：approveMerchant Server Action
// =============================================================

import { wrapInLayout, escapeHtml, formatDate, buildInfoTable } from '../base-layout'

export interface M3VerificationApprovedData {
  merchantName:        string
  commissionFreeUntil: string   // ISO 8601
  dashboardUrl?:       string
}

export function buildM3Email(data: M3VerificationApprovedData): { subject: string; html: string } {
  const subject = 'Your CrunchyPlum merchant account has been approved!'
  const dashboardUrl = data.dashboardUrl ?? 'https://merchant.crunchyplum.com'
  const freeUntilFormatted = formatDate(data.commissionFreeUntil)

  const body = `
    <p style="margin:0 0 16px;font-size:22px;font-weight:700;color:#212121;">
      Congratulations, ${escapeHtml(data.merchantName)}! 🎉
    </p>

    <p style="margin:0 0 16px;color:#424242;line-height:1.7;">
      Your CrunchyPlum merchant account has been <strong>approved</strong>.
      You can now publish deals and start reaching customers in the Dallas area.
    </p>

    ${buildInfoTable([
      { label: 'Merchant Name',         value: escapeHtml(data.merchantName) },
      { label: 'Account Status',        value: '<span style="color:#2E7D32;font-weight:600;">Approved ✓</span>' },
      { label: 'Commission-Free Until', value: `<strong>${escapeHtml(freeUntilFormatted)}</strong> <span style="color:#757575;font-size:12px;">(0% commission during this period)</span>` },
    ])}

    <p style="margin:20px 0 8px;font-size:14px;font-weight:600;color:#212121;">
      What you can do now:
    </p>
    <ul style="margin:0 0 20px;padding-left:20px;color:#424242;font-size:14px;line-height:2;">
      <li>Create and publish your first deal</li>
      <li>Upload photos and complete your store profile</li>
      <li>Set up your payout account in the Finance section</li>
      <li>Scan customer QR codes via the Scan page</li>
    </ul>

    <p style="margin:0;font-size:13px;color:#757575;line-height:1.6;">
      Questions? Contact us at
      <a href="mailto:support@crunchyplum.com" style="color:#E53935;">support@crunchyplum.com</a>.
    </p>
  `

  return {
    subject,
    html: wrapInLayout({ subject, body, cta: { label: 'Go to Merchant Dashboard', url: dashboardUrl } }),
  }
}
