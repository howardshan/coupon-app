// =============================================================
// M22 — 员工邀请邮件
// 触发：商家端 merchant-staff-mgmt/invite 成功创建邀请后
// =============================================================

import { wrapInLayout, escapeHtml, buildInfoTable } from "../base-layout.ts";

export interface M22StaffInvitationData {
  invitedEmail: string;
  storeName: string;
  role: string;
  inviterName: string;
  invitationId: string;
  expiresAt: string; // ISO 8601
  acceptUrl: string;
}

const ROLE_LABELS: Record<string, string> = {
  regional_manager: "Regional Manager",
  manager: "Manager",
  finance: "Finance",
  cashier: "Cashier",
  service: "Service",
  trainee: "Trainee",
};

export function buildM22Email(data: M22StaffInvitationData): { subject: string; html: string } {
  const subject = `You've been invited to join ${escapeHtml(data.storeName)} on CrunchyPlum`;
  const roleLabel = ROLE_LABELS[data.role] ?? data.role;

  const expiresDate = new Date(data.expiresAt).toLocaleDateString("en-US", {
    year: "numeric",
    month: "long",
    day: "numeric",
  });

  const body = `
    <p style="margin:0 0 16px;font-size:22px;font-weight:700;color:#212121;">
      You've been invited! 🎉
    </p>

    <p style="margin:0 0 16px;color:#424242;line-height:1.7;">
      <strong>${escapeHtml(data.inviterName)}</strong> has invited you to join
      <strong>${escapeHtml(data.storeName)}</strong> as a staff member on CrunchyPlum.
    </p>

    ${buildInfoTable([
      { label: "Store",       value: escapeHtml(data.storeName) },
      { label: "Your Role",   value: `<strong>${escapeHtml(roleLabel)}</strong>` },
      { label: "Invited By",  value: escapeHtml(data.inviterName) },
      { label: "Expires",     value: escapeHtml(expiresDate) },
    ])}

    <p style="margin:16px 0;color:#424242;line-height:1.7;">
      Click the button below to accept the invitation. You'll need to sign in or create a
      CrunchyPlum account with this email address (<strong>${escapeHtml(data.invitedEmail)}</strong>).
    </p>

    <p style="margin:0;font-size:13px;color:#757575;line-height:1.6;">
      This invitation expires on <strong>${escapeHtml(expiresDate)}</strong>.
      If you didn't expect this invitation, you can safely ignore this email.
    </p>
  `;

  return {
    subject,
    html: wrapInLayout({
      subject,
      body,
      cta: { label: "Accept Invitation", url: data.acceptUrl },
    }),
  };
}
