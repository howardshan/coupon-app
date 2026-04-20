-- order_items 新增 stripe_fee_amount 快照字段
-- 下单时按 per-item 比例分摊 Stripe 手续费（2.9% + $0.30/笔）
-- 退款时平台承担这部分，不从商家 reverse
-- 配合 stripe_transfer_amount（商家实收）实现精确退款分配

ALTER TABLE public.order_items
  ADD COLUMN IF NOT EXISTS stripe_fee_amount numeric(10, 2) NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.order_items.stripe_fee_amount IS
  '下单时快照的 Stripe 手续费（per-item 分摊），退款时由平台承担';

-- create-order-v3 同步更新：写入 stripe_fee_amount + stripe_transfer_amount
-- stripe_transfer_amount = unit_price - commission_amount - stripe_fee_amount（商家实收）
-- 退款时 createReversal 只从商家 reverse stripe_transfer_amount 对应的金额
