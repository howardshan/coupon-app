/**
 * 后台订单券展示：券码格式化、QR 摘要（注释中文）
 */

/** 展示用：16 位十六进制分段，其余原样 trim */
export function displayCouponCode(code: string | null | undefined): string {
  if (code == null || String(code).trim() === '') return '—'
  const c = String(code).trim()
  if (c.length === 16 && /^[0-9a-fA-F]+$/.test(c)) {
    return `${c.slice(0, 4)}-${c.slice(4, 8)}-${c.slice(8, 12)}-${c.slice(12)}`
  }
  return c
}

/** 复制到剪贴板用：原始 coupon_code */
export function couponCodeForClipboard(code: string | null | undefined): string {
  if (code == null) return ''
  return String(code).trim()
}

/** QR 载荷：完整值、缩略展示、是否 http(s) 链接 */
export function qrPayloadPreview(qr: string | null | undefined): {
  preview: string
  full: string
  isHttpUrl: boolean
} {
  const full = qr == null ? '' : String(qr).trim()
  if (!full) return { preview: '', full: '', isHttpUrl: false }
  const isHttpUrl = /^https?:\/\//i.test(full)
  const max = 52
  const preview = full.length <= max ? full : `${full.slice(0, 22)}…${full.slice(-18)}`
  return { preview, full, isHttpUrl }
}
