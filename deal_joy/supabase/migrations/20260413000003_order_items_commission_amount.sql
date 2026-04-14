-- order_items 新增 commission_amount 快照字段
-- 下单时按 (unit_price - promo_discount) × commission_rate 冻结佣金金额
-- 用于退款时精确回退平台佣金，防止 commission_rate 后续变更导致历史订单漂移

ALTER TABLE public.order_items
  ADD COLUMN IF NOT EXISTS commission_amount numeric(10, 2) NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.order_items.commission_amount IS
  '下单时快照的平台佣金金额，用于退款时精确计算佣金回退';
