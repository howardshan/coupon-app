-- 给 order_items 添加 refund_credit_amount 字段
-- 记录每个 item 退款中 store credit 退了多少，用于多券退款时追踪剩余可退额度

ALTER TABLE public.order_items
  ADD COLUMN IF NOT EXISTS refund_credit_amount NUMERIC DEFAULT 0;

COMMENT ON COLUMN public.order_items.refund_credit_amount IS '本 item 退款中退回 store credit 的金额';
