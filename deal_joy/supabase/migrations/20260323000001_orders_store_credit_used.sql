-- 为 orders 表添加 store_credit_used 字段
-- 记录订单中使用了多少 Store Credit，退款时需要按比例拆分

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS store_credit_used NUMERIC DEFAULT 0;

COMMENT ON COLUMN public.orders.store_credit_used IS '本单使用的 Store Credit 金额，用于退款时按比例拆分 card/credit 退款';
