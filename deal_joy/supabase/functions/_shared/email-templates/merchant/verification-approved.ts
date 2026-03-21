// =============================================================
// M3 — 商户认证通过通知
// 触发：管理员在 Admin Dashboard 点击「Approve」审核通过
// 收件人：商家注册邮箱
// =============================================================

import { wrapInLayout, escapeHtml, formatDate, buildInfoTable } from '../../base-layout.ts'

export interface M3VerificationApprovedData {
  merchantName:          string   // 商家名称
  merchantEmail:         string   // 收件人邮箱
  commissionFreeUntil:   string   // 免佣期截止日（ISO 8601）
  dashboardUrl?:         string   // 商家端 Dashboard 链接（可选，默认值见下方）
}

export function buildM3Email(data: M3VerificationApprovedData): { subject: string; html: string } {
  const subject = 'Your DealJoy merchant account has been approved!'

  const dashboardUrl = data.dashboardUrl ?? 'https://merchant.crunchyplum.com'
  const freeUntilFormatted = formatDate(data.commissionFreeUntil)

  const body = `
    <p style="margin:0 0 16px;font-size:22px;font-weight:700;color:#212121;">
      Congratulations, ${escapeHtml(data.merchantName)}! 🎉
    </p>

    <p style="margin:0 0 16px;color:#424242;line-height:1.7;">
      Your DealJoy merchant account has been <strong>approved</strong>.
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
      If you have any questions, reply to this email or contact us at
      <a href="mailto:support@crunchyplum.com" style="color:#E53935;">support@crunchyplum.com</a>.
    </p>
  `

  const html = wrapInLayout({
    subject,
    body,
    cta: {
      label: 'Go to Merchant Dashboard',
      url:   dashboardUrl,
    },
  })

  return { subject, html }
}
