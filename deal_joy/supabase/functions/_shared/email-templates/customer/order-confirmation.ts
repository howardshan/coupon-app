// =============================================================
// C2 — 订单确认邮件
// 触发：create-order-v3 订单创建成功后
// =============================================================

import { wrapInLayout, escapeHtml, formatCurrency, buildInfoTable } from "../base-layout.ts";

export interface C2OrderItem {
  dealTitle:  string;
  unitPrice:  number;
  quantity:   number;
}

export interface C2OrderConfirmationData {
  customerEmail:  string;
  orderNumber:    string;
  items:          C2OrderItem[];
  subtotal:       number;
  serviceFee:     number;
  totalAmount:    number;
}

export function buildC2Email(data: C2OrderConfirmationData): { subject: string; html: string } {
  const subject = `Order confirmed — ${data.orderNumber}`;

  // 逐行渲染 deal 列表
  const itemRows = data.items.map(item => `
    <tr>
      <td style="padding:10px 0;font-size:14px;color:#212121;border-bottom:1px solid #F0F0F0;">
        ${escapeHtml(item.dealTitle)}
        ${item.quantity > 1 ? `<span style="color:#757575;font-size:12px;"> × ${item.quantity}</span>` : ''}
      </td>
      <td style="padding:10px 0 10px 16px;font-size:14px;color:#212121;border-bottom:1px solid #F0F0F0;
                 text-align:right;font-weight:500;white-space:nowrap;">
        ${formatCurrency(item.unitPrice * item.quantity)}
      </td>
    </tr>`).join('');

  const body = `
    <p style="margin:0 0 4px;font-size:22px;font-weight:700;color:#212121;">
      Your order is confirmed! 🎉
    </p>
    <p style="margin:0 0 20px;font-size:14px;color:#757575;">
      Order <strong>${escapeHtml(data.orderNumber)}</strong>
    </p>

    <p style="margin:0 0 12px;color:#424242;line-height:1.7;">
      Thanks for your purchase on CrunchyPlum. Your vouchers are ready to use —
      show them to the merchant at any time.
    </p>

    <!-- 订单明细 -->
    <table width="100%" cellpadding="0" cellspacing="0" border="0"
           style="margin:16px 0;border-top:1px solid #F0F0F0;">
      ${itemRows}
      <tr>
        <td style="padding:8px 0;font-size:13px;color:#757575;">Subtotal</td>
        <td style="padding:8px 0;font-size:13px;color:#757575;text-align:right;">
          ${formatCurrency(data.subtotal)}
        </td>
      </tr>
      <tr>
        <td style="padding:4px 0 12px;font-size:13px;color:#757575;">Service fee</td>
        <td style="padding:4px 0 12px;font-size:13px;color:#757575;text-align:right;">
          ${formatCurrency(data.serviceFee)}
        </td>
      </tr>
      <tr style="border-top:2px solid #E0E0E0;">
        <td style="padding:12px 0 4px;font-size:15px;font-weight:700;color:#212121;">Total</td>
        <td style="padding:12px 0 4px;font-size:15px;font-weight:700;color:#212121;text-align:right;">
          ${formatCurrency(data.totalAmount)}
        </td>
      </tr>
    </table>

    <p style="margin:16px 0 0;font-size:13px;color:#757575;line-height:1.6;">
      ✅ Your vouchers never expire until you use them — and you can get a full refund anytime
      before redemption. Questions? Contact us at
      <a href="mailto:support@crunchyplum.com" style="color:#E53935;">support@crunchyplum.com</a>.
    </p>
  `;

  return {
    subject,
    html: wrapInLayout({ subject, body, cta: { label: "View My Orders", url: "crunchyplum://orders" } }),
  };
}
