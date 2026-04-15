-- order_items 新增 stripe_reserve_hold_id 字段
-- 存储 Stripe ReserveHold ID (rsvh_xxx)
-- 冻结该 order_item 对应的 merchant_net，核销/退款时释放
ALTER TABLE public.order_items
  ADD COLUMN IF NOT EXISTS stripe_reserve_hold_id TEXT;

COMMENT ON COLUMN public.order_items.stripe_reserve_hold_id IS
  'Stripe ReserveHold ID (rsvh_xxx)，冻结该 order_item 的 merchant_net，核销/退款/过期时通过 Reserves API 释放';
