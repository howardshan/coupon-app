// =============================================================
// M4 — 商户认证拒绝通知（Admin Next.js 版本）
// 触发：rejectMerchant Server Action
// =============================================================

import { wrapInLayout, escapeHtml, buildInfoTable } from '../base-layout'

export interface M4VerificationRejectedData {
  merchantName:    string
  rejectionReason: string | null
  resubmitUrl?:    string
}

export function buildM4Email(data: M4VerificationRejectedData): { subject: string; html: string } {
  const subject = 'Update on your CrunchyPlum merchant application'
  const resubmitUrl = data.resubmitUrl ?? 'https://merchant.crunchyplum.com/register'

  const reasonBlock = data.rejectionReason
    ? `
      <table width="100%" cellpadding="0" cellspacing="0" border="0" style="margin:16px 0;">
        <tr>
          <td style="background:#FFF3E0;border-left:3px solid #FF6F00;
                     padding:14px 16px;border-radius:4px;
                     font-size:14px;color:#4E342E;line-height:1.6;">
            <strong>Reason for rejection:</strong><br />
            ${escapeHtml(data.rejectionReason)}
          </td>
        </tr>
      </table>`
    : `
      <p style="margin:16px 0;font-size:14px;color:#757575;">
        Our team will follow up with more details. If you have questions,
        please contact us at
        <a href="mailto:support@crunchyplum.com" style="color:#E53935;">support@crunchyplum.com</a>.
      </p>`

  const body = `
    <p style="margin:0 0 16px;font-size:22px;font-weight:700;color:#212121;">
      Application Update
    </p>

    <p style="margin:0 0 16px;color:#424242;line-height:1.7;">
      Hi ${escapeHtml(data.merchantName)}, thank you for applying to join CrunchyPlum as a merchant.
      After reviewing your application, we are unable to approve it at this time.
    </p>

    ${buildInfoTable([
      { label: 'Merchant Name',    value: escapeHtml(data.merchantName) },
      { label: 'Application Status', value: '<span style="color:#C62828;font-weight:600;">Not Approved</span>' },
    ])}

    ${reasonBlock}

    <p style="margin:20px 0 8px;font-size:14px;font-weight:600;color:#212121;">
      What you can do next:
    </p>
    <ul style="margin:0 0 20px;padding-left:20px;color:#424242;font-size:14px;line-height:2;">
      <li>Review the feedback above and update your application materials</li>
      <li>Ensure your business documents are complete and up to date</li>
      <li>Resubmit your application once the issues have been addressed</li>
    </ul>

    <p style="margin:0;font-size:13px;color:#757575;line-height:1.6;">
      Need help? Contact our merchant support team at
      <a href="mailto:support@crunchyplum.com" style="color:#E53935;">support@crunchyplum.com</a>.
    </p>
  `

  return {
    subject,
    html: wrapInLayout({
      subject,
      body,
      cta: { label: 'Resubmit Application', url: resubmitUrl },
    }),
  }
}
