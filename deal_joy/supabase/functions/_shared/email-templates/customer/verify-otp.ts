// =============================================================
// C15 — 注册邮箱 OTP 验证码邮件
// 触发：用户注册后发送 6 位验证码
// =============================================================

import { wrapInLayout, escapeHtml } from "../base-layout.ts";

export interface C15VerifyOtpData {
  email: string;
  otpCode: string;
  fullName?: string;
}

export function buildC15Email(data: C15VerifyOtpData): { subject: string; html: string } {
  const subject = `${data.otpCode} is your DealJoy verification code`;
  const name = data.fullName ? escapeHtml(data.fullName) : 'there';

  const body = `
    <tr>
      <td style="padding:0 0 16px;font-size:16px;color:#212121;line-height:1.5;">
        Hi ${name},
      </td>
    </tr>
    <tr>
      <td style="padding:0 0 16px;font-size:14px;color:#424242;line-height:1.6;">
        Thanks for signing up for DealJoy! Please use the verification code below to complete your registration:
      </td>
    </tr>
    <tr>
      <td align="center" style="padding:16px 0 24px;">
        <div style="display:inline-block;background:#F5F5F5;border:2px dashed #E53935;
                    border-radius:12px;padding:20px 40px;letter-spacing:8px;
                    font-size:32px;font-weight:700;color:#E53935;font-family:monospace;">
          ${data.otpCode}
        </div>
      </td>
    </tr>
    <tr>
      <td style="padding:0 0 16px;font-size:14px;color:#424242;line-height:1.6;">
        This code will expire in <strong>60 minutes</strong>. If you didn't create an account, you can safely ignore this email.
      </td>
    </tr>
    <tr>
      <td style="padding:0 0 8px;font-size:13px;color:#757575;line-height:1.5;">
        For security reasons, please do not share this code with anyone.
      </td>
    </tr>
  `;

  const html = wrapInLayout({ subject, body });

  return { subject, html };
}
