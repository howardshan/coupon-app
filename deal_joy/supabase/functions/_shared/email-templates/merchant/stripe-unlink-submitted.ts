// =============================================================
// M19 — Stripe 解绑申请已提交（发给操作者本人，商家/品牌）
// 触发：merchant-withdrawal POST /stripe-unlink/request
// =============================================================

import { wrapInLayout, escapeHtml, buildInfoTable } from "../base-layout.ts";

export interface M19StripeUnlinkSubmittedData {
  addresseeName: string; // 操作者名字（名或 “there”）
  requestId: string; // 申请行 id（UUID，展示短码）
  scopeLabel: string; // 作用域说明，如门店名或 “Brand: Acme”
  requestNote?: string;
  settingsUrl?: string; // 收款设置页
}

function shortId(id: string): string {
  return id.replace(/-/g, "").slice(0, 8).toUpperCase();
}

export function buildM19Email(data: M19StripeUnlinkSubmittedData): { subject: string; html: string } {
  const subject = `We received your Stripe disconnect request — ${data.scopeLabel}`;
  const settingsUrl = data.settingsUrl ?? "https://merchant.crunchyplum.com/earnings";

  const noteBlock = data.requestNote?.trim()
    ? `<p style="margin:0 0 12px;color:#424242;line-height:1.7;">Your note: <em>${escapeHtml(
        data.requestNote.trim().slice(0, 2000)
      )}</em></p>`
    : "";

  const body = `
    <p style="margin:0 0 16px;font-size:22px;font-weight:700;color:#212121;">
      Request received
    </p>

    <p style="margin:0 0 16px;color:#424242;line-height:1.7;">
      Hi ${escapeHtml(data.addresseeName)}, we have received your request to remove the
      payment account connection (Stripe) for <strong>${escapeHtml(data.scopeLabel)}</strong>.
    </p>

    ${buildInfoTable([
      { label: "Request ID", value: `<span style="font-family:monospace;">${shortId(data.requestId)}</span>` },
      { label: "Status", value: '<span style="color:#F57C00;font-weight:600;">Pending review</span>' },
    ])}

    ${noteBlock}

    <p style="margin:16px 0 0;font-size:13px;color:#757575;line-height:1.6;">
      Our team will review your request. You will be notified by email when a decision
      is made. If you have questions, contact
      <a href="mailto:merchant@crunchyplum.com" style="color:#E53935;">merchant@crunchyplum.com</a>.
    </p>
  `;

  return {
    subject,
    html: wrapInLayout({ subject, body, cta: { label: "Open earnings & payments", url: settingsUrl } }),
  };
}
