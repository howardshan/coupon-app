-- Admin 售后「历史」列表：补充结案相关列（追加在视图末尾，避免 REPLACE 列位冲突）
begin;

CREATE OR REPLACE VIEW public.view_merchant_after_sales_requests AS
SELECT
  r.id,
  r.order_id,
  r.coupon_id,
  r.status,
  r.reason_code,
  r.reason_detail,
  r.refund_amount,
  r.user_attachments,
  r.merchant_feedback,
  r.merchant_attachments,
  r.platform_feedback,
  r.platform_attachments,
  r.expires_at,
  r.created_at,
  r.updated_at,
  r.merchant_id,
  r.store_id,
  o.total_amount,
  o.order_number,
  r.user_id,
  u.full_name AS user_name,
  s.name AS store_name,
  d.title AS deal_title,
  r.refunded_at,
  r.platform_decided_at,
  r.closed_at,
  COALESCE(r.refunded_at, r.platform_decided_at, r.closed_at, r.updated_at) AS resolved_at
FROM public.after_sales_requests r
JOIN public.orders o ON o.id = r.order_id
JOIN public.users u ON u.id = o.user_id
JOIN public.merchants s ON s.id = r.store_id
LEFT JOIN public.deals d ON d.id = o.deal_id;

commit;
