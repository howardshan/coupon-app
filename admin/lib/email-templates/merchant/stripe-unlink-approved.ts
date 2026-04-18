// M20 — Stripe 解绑审批通过（仅平台库已解绑，英文）
// 触发：approveStripeUnlinkRequest

import { wrapInLayout, escapeHtml, buildInfoTable } from '../base-layout'

export interface M20StripeUnlinkApprovedData {
  addresseeName: string
  requestId: string
  scopeLabel: string
  unboundAt: string
  settingsUrl?: string
}

function shortId(id: string) {
  return id.replace(/-/g, '').slice(0, 8).toUpperCase()
}

export function buildM20Email(data: M20StripeUnlinkApprovedData): { subject: string; html: string } {
  const subject = `Your Stripe connection has been removed — ${data.scopeLabel}`
  const settingsUrl = data.settingsUrl ?? 'https://merchant.crunchyplum.com/earnings'
  const body = `
    <p style="margin:0 0 16px;font-size:22px;font-weight:700;color:#212121;">
      Disconnection approved
    </p>
    <p style="margin:0 0 16px;color:#424242;line-height:1.7;">
      Hi ${escapeHtml(data.addresseeName)}, we have removed the platform-side link between your
      business and Stripe for <strong>${escapeHtml(data.scopeLabel)}</strong>. Payouts through this
      account will not be available until you connect a new account.
    </p>
    ${buildInfoTable([
      { label: 'Request ID', value: `<span style="font-family:monospace;">${shortId(data.requestId)}</span>` },
      { label: 'Status',     value: '<span style="color:#2E7D32;font-weight:600;">Disconnected (platform data)</span>' },
      { label: 'Updated',   value: escapeHtml(data.unboundAt) },
    ])}
    <p style="margin:16px 0 0;font-size:13px;color:#757575;line-height:1.6;">
      This change applies to our app only; Stripe may still retain the connected account and records per their policies.
      When you are ready, you can connect Stripe again from your dashboard.
    </p>
  `
  return { subject, html: wrapInLayout({ subject, body, cta: { label: 'Earnings & payments', url: settingsUrl } }) }
}
