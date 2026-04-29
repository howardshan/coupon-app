// =============================================================
// Crunchy Plum 邮件公共 HTML 布局
// 所有邮件模板通过 wrapInLayout() 包裹，保持品牌视觉一致性
// =============================================================

// 品牌颜色
const BRAND_RED    = "#E53935";
const BRAND_DARK   = "#1A1A2E";
const BODY_BG      = "#F5F5F5";
const CARD_BG      = "#FFFFFF";
const TEXT_PRIMARY = "#212121";
const TEXT_MUTED   = "#757575";
const DIVIDER      = "#E0E0E0";

// ─────────────────────────────────────────────────────────────
// 主函数：wrapInLayout
// 将邮件正文包裹进品牌 HTML 框架
// ─────────────────────────────────────────────────────────────

export function wrapInLayout(options: {
  /** 邮件主题（也作为预览文本） */
  subject: string;
  /** 正文内容（纯 HTML 片段，不含 <html>/<body> 标签） */
  body: string;
  /** 可选：正文底部附加的操作按钮区块 */
  cta?: {
    label: string;
    url: string;
  };
}): string {
  const { subject, body, cta } = options;

  const ctaBlock = cta
    ? `
      <tr>
        <td align="center" style="padding: 24px 0 8px;">
          <a href="${cta.url}"
             style="display:inline-block;background:${BRAND_RED};color:#FFFFFF;
                    font-size:15px;font-weight:600;text-decoration:none;
                    padding:14px 32px;border-radius:6px;letter-spacing:0.3px;">
            ${cta.label}
          </a>
        </td>
      </tr>`
    : "";

  return `<!DOCTYPE html>
<html lang="en" xmlns="http://www.w3.org/1999/xhtml">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <meta name="x-apple-disable-message-reformatting" />
  <title>${escapeHtml(subject)}</title>
  <!--[if mso]>
  <noscript>
    <xml><o:OfficeDocumentSettings>
      <o:PixelsPerInch>96</o:PixelsPerInch>
    </o:OfficeDocumentSettings></xml>
  </noscript>
  <![endif]-->
  <style>
    body { margin: 0; padding: 0; background-color: ${BODY_BG}; }
    table { border-collapse: collapse; }
    img { border: 0; outline: none; text-decoration: none; }
    a { color: ${BRAND_RED}; }
    @media only screen and (max-width: 600px) {
      .email-wrapper { width: 100% !important; }
      .email-card    { padding: 24px 16px !important; }
    }
  </style>
</head>
<body style="margin:0;padding:0;background-color:${BODY_BG};font-family:'Helvetica Neue',Helvetica,Arial,sans-serif;">

  <!-- 预览文本（邮件列表中显示） -->
  <div style="display:none;max-height:0;overflow:hidden;mso-hide:all;">
    ${escapeHtml(subject)}&nbsp;&#8203;&zwnj;&#8203;&zwnj;
  </div>

  <!-- 外层容器 -->
  <table width="100%" cellpadding="0" cellspacing="0" border="0"
         style="background-color:${BODY_BG};padding:32px 16px;">
    <tr>
      <td align="center">

        <!-- 邮件卡片（最大宽度 600px） -->
        <table class="email-wrapper" width="600" cellpadding="0" cellspacing="0" border="0"
               style="max-width:600px;width:100%;">

          <!-- 顶部品牌 Logo 区 -->
          <tr>
            <td align="center" style="padding-bottom:24px;">
              <table cellpadding="0" cellspacing="0" border="0">
                <tr>
                  <td align="center" valign="middle"
                      style="background-color:#1A1A2E;padding:14px 24px;border-radius:10px;">
                    <img src="https://www.crunchyplum.com/logo-email.png"
                         alt="Crunchy Plum"
                         width="36" height="36"
                         style="display:inline-block;vertical-align:middle;border-radius:6px;margin-right:10px;" />
                    <span style="display:inline-block;vertical-align:middle;
                                 font-size:20px;font-weight:800;color:#FFFFFF;letter-spacing:0.4px;">
                      Crunchy Plum
                    </span>
                  </td>
                </tr>
              </table>
            </td>
          </tr>

          <!-- 邮件正文卡片 -->
          <tr>
            <td class="email-card"
                style="background-color:${CARD_BG};border-radius:12px;
                       padding:36px 40px;box-shadow:0 2px 8px rgba(0,0,0,0.06);">
              <table width="100%" cellpadding="0" cellspacing="0" border="0">

                <!-- 正文内容（由各模板注入） -->
                <tr>
                  <td style="color:${TEXT_PRIMARY};font-size:15px;line-height:1.7;">
                    ${body}
                  </td>
                </tr>

                ${ctaBlock}

              </table>
            </td>
          </tr>

          <!-- 分隔线 -->
          <tr>
            <td style="padding:24px 0 0;">
              <hr style="border:none;border-top:1px solid ${DIVIDER};margin:0;" />
            </td>
          </tr>

          <!-- 页脚 -->
          <tr>
            <td align="center" style="padding:20px 0 8px;">
              <p style="margin:0;font-size:12px;color:${TEXT_MUTED};line-height:1.6;">
                You received this email because you have an account with CrunchyPlum.<br />
                CrunchyPlum · Dallas, TX · <a href="https://crunchyplum.com" style="color:${TEXT_MUTED};">crunchyplum.com</a>
              </p>
              <p style="margin:8px 0 0;font-size:11px;color:${TEXT_MUTED};">
                <a href="https://www.crunchyplum.com/legal/terms" style="color:${TEXT_MUTED};">Terms of Service</a> ·
                <a href="https://www.crunchyplum.com/legal/privacy" style="color:${TEXT_MUTED};">Privacy Policy</a> ·
                <a href="https://www.crunchyplum.com/legal/refund" style="color:${TEXT_MUTED};">Refund Policy</a>
              </p>
              <p style="margin:8px 0 0;font-size:11px;color:${TEXT_MUTED};">
                © ${new Date().getFullYear()} CrunchyPlum. All rights reserved.
              </p>
            </td>
          </tr>

        </table>
        <!-- /邮件卡片 -->

      </td>
    </tr>
  </table>

</body>
</html>`;
}

// ─────────────────────────────────────────────────────────────
// 辅助函数：escapeHtml
// 防止 XSS：将用户提供的字符串安全嵌入 HTML 属性/文本
// ─────────────────────────────────────────────────────────────

export function escapeHtml(str: string): string {
  return str
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#x27;");
}

// ─────────────────────────────────────────────────────────────
// 辅助函数：formatDate
// 将 ISO 8601 日期字符串转为美式格式（如 "March 25, 2026"）
// ─────────────────────────────────────────────────────────────

export function formatDate(isoString: string): string {
  const d = new Date(isoString);
  return d.toLocaleDateString("en-US", {
    year:  "numeric",
    month: "long",
    day:   "numeric",
    timeZone: "America/Chicago",
  });
}

// ─────────────────────────────────────────────────────────────
// 辅助函数：formatCurrency
// 将数字格式化为带 $ 符号的金额（如 "$12.50"）
// ─────────────────────────────────────────────────────────────

export function formatCurrency(amount: number): string {
  return `$${amount.toFixed(2)}`;
}

// ─────────────────────────────────────────────────────────────
// 辅助函数：buildInfoTable
// 构建一个两列（字段名 + 值）的信息汇总表格
// ─────────────────────────────────────────────────────────────

export function buildInfoTable(rows: Array<{ label: string; value: string }>): string {
  const rowsHtml = rows
    .map(
      ({ label, value }) => `
        <tr>
          <td style="padding:8px 0;font-size:14px;color:#757575;width:40%;
                     border-bottom:1px solid #F0F0F0;vertical-align:top;">
            ${escapeHtml(label)}
          </td>
          <td style="padding:8px 0 8px 16px;font-size:14px;color:#212121;
                     border-bottom:1px solid #F0F0F0;vertical-align:top;
                     font-weight:500;">
            ${value}
          </td>
        </tr>`
    )
    .join("");

  return `
    <table width="100%" cellpadding="0" cellspacing="0" border="0"
           style="margin:16px 0;border-top:1px solid #F0F0F0;">
      ${rowsHtml}
    </table>`;
}
