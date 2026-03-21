// =============================================================
// DealJoy 邮件公共 HTML 布局（Admin Next.js 专用）
// 与 Edge Function 版本保持视觉一致，去除 Deno 依赖
// =============================================================

const BRAND_RED    = '#E53935'
const BRAND_DARK   = '#1A1A2E'
const BODY_BG      = '#F5F5F5'
const CARD_BG      = '#FFFFFF'
const TEXT_PRIMARY = '#212121'
const TEXT_MUTED   = '#757575'
const DIVIDER      = '#E0E0E0'

export function wrapInLayout(options: {
  subject: string
  body: string
  cta?: { label: string; url: string }
}): string {
  const { subject, body, cta } = options

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
    : ''

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>${escapeHtml(subject)}</title>
  <style>
    body { margin: 0; padding: 0; background-color: ${BODY_BG}; }
    table { border-collapse: collapse; }
    a { color: ${BRAND_RED}; }
    @media only screen and (max-width: 600px) {
      .email-wrapper { width: 100% !important; }
      .email-card    { padding: 24px 16px !important; }
    }
  </style>
</head>
<body style="margin:0;padding:0;background-color:${BODY_BG};font-family:'Helvetica Neue',Helvetica,Arial,sans-serif;">

  <div style="display:none;max-height:0;overflow:hidden;">
    ${escapeHtml(subject)}&nbsp;&#8203;
  </div>

  <table width="100%" cellpadding="0" cellspacing="0" border="0"
         style="background-color:${BODY_BG};padding:32px 16px;">
    <tr>
      <td align="center">
        <table class="email-wrapper" width="600" cellpadding="0" cellspacing="0" border="0"
               style="max-width:600px;width:100%;">

          <!-- Logo -->
          <tr>
            <td align="center" style="padding-bottom:24px;">
              <table cellpadding="0" cellspacing="0" border="0">
                <tr>
                  <td style="background-color:${BRAND_DARK};padding:16px 28px;border-radius:8px;">
                    <span style="font-size:22px;font-weight:800;color:#FFFFFF;letter-spacing:0.5px;">
                      🍒 DealJoy
                    </span>
                  </td>
                </tr>
              </table>
            </td>
          </tr>

          <!-- 正文卡片 -->
          <tr>
            <td class="email-card"
                style="background-color:${CARD_BG};border-radius:12px;
                       padding:36px 40px;box-shadow:0 2px 8px rgba(0,0,0,0.06);">
              <table width="100%" cellpadding="0" cellspacing="0" border="0">
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
                You received this email because you have an account with DealJoy.<br />
                DealJoy · Dallas, TX · <a href="https://crunchyplum.com" style="color:${TEXT_MUTED};">crunchyplum.com</a>
              </p>
              <p style="margin:8px 0 0;font-size:11px;color:${TEXT_MUTED};">
                © ${new Date().getFullYear()} DealJoy. All rights reserved.
              </p>
            </td>
          </tr>

        </table>
      </td>
    </tr>
  </table>
</body>
</html>`
}

export function escapeHtml(str: string): string {
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#x27;')
}

export function formatDate(isoString: string): string {
  const d = new Date(isoString)
  return d.toLocaleDateString('en-US', {
    year: 'numeric', month: 'long', day: 'numeric',
    timeZone: 'America/Chicago',
  })
}

export function formatCurrency(amount: number): string {
  return `$${amount.toFixed(2)}`
}

export function buildInfoTable(rows: Array<{ label: string; value: string }>): string {
  const rowsHtml = rows
    .map(({ label, value }) => `
      <tr>
        <td style="padding:8px 0;font-size:14px;color:#757575;width:40%;
                   border-bottom:1px solid #F0F0F0;vertical-align:top;">
          ${escapeHtml(label)}
        </td>
        <td style="padding:8px 0 8px 16px;font-size:14px;color:#212121;
                   border-bottom:1px solid #F0F0F0;vertical-align:top;font-weight:500;">
          ${value}
        </td>
      </tr>`)
    .join('')

  return `
    <table width="100%" cellpadding="0" cellspacing="0" border="0"
           style="margin:16px 0;border-top:1px solid #F0F0F0;">
      ${rowsHtml}
    </table>`
}
