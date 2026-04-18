-- 记录每张 order_item 实际转给商家的 Stripe transfer 金额
-- 用于退款时精确逆向，避免超额或不足额 reversal
ALTER TABLE public.order_items
  ADD COLUMN IF NOT EXISTS stripe_transfer_amount NUMERIC(10, 2);

COMMENT ON COLUMN public.order_items.stripe_transfer_amount IS
  '该 item 对应的实际 Stripe Transfer 金额（美元），含 stripe_fee 摊薄后的净值。退款时用此值做 createReversal，比 merchant_net 更精确。';
