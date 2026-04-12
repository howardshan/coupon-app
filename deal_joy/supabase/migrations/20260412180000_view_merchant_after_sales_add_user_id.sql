-- Admin 审批列表：SELECT 列顺序须与既有视图一致（total_amount → order_number → user_id），
-- 否则 CREATE OR REPLACE VIEW 会报 42P16（不能把同一位置的列名从 total_amount 改成 user_id）。
-- user_id 使用 r.user_id（与 o.user_id 一致，来自售后单归属）。
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
  d.title AS deal_title
FROM public.after_sales_requests r
JOIN public.orders o ON o.id = r.order_id
JOIN public.users u ON u.id = o.user_id
JOIN public.merchants s ON s.id = r.store_id
LEFT JOIN public.deals d ON d.id = o.deal_id;

commit;
