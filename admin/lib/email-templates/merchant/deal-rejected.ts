// =============================================================
// M16 — Deal 被管理员驳回通知（Admin Next.js 版本）
// 触发：rejectDeal Server Action
// =============================================================

import { wrapInLayout, escapeHtml, buildInfoTable } from '../base-layout'

export interface M16DealRejectedData {
  merchantName:    string
  dealTitle:       string
  rejectionReason: string | null
  resubmitUrl?:    string
}

export function buildM16Email(data: M16DealRejectedData): { subject: string; html: string } {
  const subject = `Your deal "${data.dealTitle}" needs revision`
  const resubmitUrl = data.resubmitUrl ?? 'https://merchant.crunchyplum.com/deals'

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
      <p style="margin:16px 0;font-size:14px;color:#757575;line-height:1.6;">
        Our team will reach out with more details. In the meantime, feel free to contact us at
        <a href="mailto:support@crunchyplum.com" style="color:#E53935;">support@crunchyplum.com</a>.
      </p>`

  const body = `
    <p style="margin:0 0 16px;font-size:22px;font-weight:700;color:#212121;">
      Deal Revision Required
    </p>

    <p style="margin:0 0 16px;color:#424242;line-height:1.7;">
      Hi ${escapeHtml(data.merchantName)}, your deal has been reviewed and requires
      some changes before it can go live on CrunchyPlum.
    </p>

    ${buildInfoTable([
      { label: 'Deal Name', value: `<strong>${escapeHtml(data.dealTitle)}</strong>` },
      { label: 'Status',    value: '<span style="color:#C62828;font-weight:600;">Rejected — Revision Required</span>' },
    ])}

    ${reasonBlock}

    <p style="margin:20px 0 8px;font-size:14px;font-weight:600;color:#212121;">
      Next steps:
    </p>
    <ul style="margin:0 0 20px;padding-left:20px;color:#424242;font-size:14px;line-height:2;">
      <li>Review the feedback above carefully</li>
      <li>Edit your deal to address the issues mentioned</li>
      <li>Resubmit the deal for review — it typically takes 1–2 business days</li>
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
      cta: { label: 'Edit My Deal', url: resubmitUrl },
    }),
  }
}
