// M21 — Stripe 解绑申请被拒（必含理由，英文）
// 触发：rejectStripeUnlinkRequest

import { wrapInLayout, escapeHtml, buildInfoTable } from '../base-layout'

export interface M21StripeUnlinkRejectedData {
  addresseeName: string
  requestId: string
  scopeLabel: string
  adminReason: string
  settingsUrl?: string
}

function shortId(id: string) {
  return id.replace(/-/g, '').slice(0, 8).toUpperCase()
}

export function buildM21Email(data: M21StripeUnlinkRejectedData): { subject: string; html: string } {
  const subject = `Update on your Stripe disconnection request — ${data.scopeLabel}`
  const settingsUrl = data.settingsUrl ?? 'https://merchant.crunchyplum.com/earnings'
  const body = `
    <p style="margin:0 0 16px;font-size:22px;font-weight:700;color:#212121;">
      Request not approved
    </p>
    <p style="margin:0 0 12px;color:#424242;line-height:1.7;">
      Hi ${escapeHtml(data.addresseeName)}, we reviewed your request to remove the payment account
      connection for <strong>${escapeHtml(data.scopeLabel)}</strong>. This request is not being approved at this time.
    </p>
    <p style="margin:0 0 16px;padding:12px 14px;background:#F5F5F5;border-left:3px solid #C62828;color:#424242;font-size:14px;line-height:1.6;">
      <strong>Reason from our team:</strong><br/>
      ${escapeHtml(data.adminReason)}
    </p>
    ${buildInfoTable([
      { label: 'Request ID', value: `<span style="font-family:monospace;">${shortId(data.requestId)}</span>` },
      { label: 'Status',     value: '<span style="color:#C62828;font-weight:600;">Not approved</span>' },
    ])}
    <p style="margin:12px 0 0;font-size:13px;color:#757575;line-height:1.6;">
      Your Stripe connection remains in place. If you have questions, contact
      <a href="mailto:merchant@crunchyplum.com" style="color:#E53935;">merchant@crunchyplum.com</a>.
    </p>
  `
  return { subject, html: wrapInLayout({ subject, body, cta: { label: 'Open dashboard', url: settingsUrl } }) }
}
