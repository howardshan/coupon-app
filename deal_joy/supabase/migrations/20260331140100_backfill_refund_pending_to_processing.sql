-- ADD VALUE 后须新事务才能写入新枚举；将「等 Stripe webhook」行从 refund_pending 迁出
UPDATE public.order_items
SET customer_status = 'refund_processing'
WHERE customer_status = 'refund_pending'
  AND refunded_at IS NULL;
