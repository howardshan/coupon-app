// =============================================================
// M5 — 新订单通知（发给商家）
// 触发：create-order-v3 订单创建成功后，每个涉及的商家各收一封
// =============================================================

import { wrapInLayout, escapeHtml, formatCurrency, buildInfoTable } from "../base-layout.ts";

export interface M5NewOrderData {
  merchantName:   string;
  orderNumber:    string;
  items:          Array<{ dealTitle: string; quantity: number; unitPrice: number }>;
  totalAmount:    number;     // 此商家相关的金额合计
  dashboardUrl?:  string;
}

export function buildM5Email(data: M5NewOrderData): { subject: string; html: string } {
  const subject = `New order received — ${data.orderNumber}`;
  const dashboardUrl = data.dashboardUrl ?? "https://merchant.crunchyplum.com/orders";

  const itemRows = data.items.map(item => `
    <tr>
      <td style="padding:10px 0;font-size:14px;color:#212121;border-bottom:1px solid #F0F0F0;">
        ${escapeHtml(item.dealTitle)}
      </td>
      <td style="padding:10px 0 10px 16px;font-size:14px;color:#757575;
                 border-bottom:1px solid #F0F0F0;text-align:center;">
        × ${item.quantity}
      </td>
      <td style="padding:10px 0 10px 16px;font-size:14px;color:#212121;
                 border-bottom:1px solid #F0F0F0;text-align:right;font-weight:500;">
        ${formatCurrency(item.unitPrice * item.quantity)}
      </td>
    </tr>`).join('');

  const body = `
    <p style="margin:0 0 16px;font-size:22px;font-weight:700;color:#212121;">
      You have a new order! 🛒
    </p>

    <p style="margin:0 0 16px;color:#424242;line-height:1.7;">
      Hi ${escapeHtml(data.merchantName)}, a customer has just purchased vouchers for your deals
      on CrunchyPlum.
    </p>

    ${buildInfoTable([
      { label: "Order Number", value: `<strong>${escapeHtml(data.orderNumber)}</strong>` },
    ])}

    <!-- 订单明细 -->
    <table width="100%" cellpadding="0" cellspacing="0" border="0"
           style="margin:16px 0;border-top:1px solid #F0F0F0;">
      <tr>
        <th style="padding:8px 0;font-size:12px;color:#9E9E9E;text-align:left;font-weight:500;
                   text-transform:uppercase;letter-spacing:0.5px;">Deal</th>
        <th style="padding:8px 0;font-size:12px;color:#9E9E9E;text-align:center;font-weight:500;
                   text-transform:uppercase;letter-spacing:0.5px;">Qty</th>
        <th style="padding:8px 0;font-size:12px;color:#9E9E9E;text-align:right;font-weight:500;
                   text-transform:uppercase;letter-spacing:0.5px;">Amount</th>
      </tr>
      ${itemRows}
    </table>

    <p style="margin:0;font-size:13px;color:#757575;line-height:1.6;">
      The customer can present the voucher QR code for redemption at any time.
      Use the Scan page in your dashboard to verify and redeem it.
    </p>
  `;

  return {
    subject,
    html: wrapInLayout({ subject, body, cta: { label: "View in Dashboard", url: dashboardUrl } }),
  };
}
