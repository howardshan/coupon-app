-- order_items 新增 promo_discount 字段
-- 快照下单时的促销折扣金额，用于退款时精确计算 merchant_net
-- merchant_net = unit_price - promo_discount - commission_amount
ALTER TABLE public.order_items
  ADD COLUMN IF NOT EXISTS promo_discount numeric(10, 2) NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.order_items.promo_discount IS
  '下单时快照的促销折扣金额，用于退款时精确计算 merchant_net = unit_price - promo_discount - commission_amount';
