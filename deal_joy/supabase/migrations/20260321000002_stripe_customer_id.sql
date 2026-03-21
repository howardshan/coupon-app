-- 为 users 表添加 stripe_customer_id 字段
-- 用于关联 Stripe Customer，实现保存卡片功能

ALTER TABLE public.users ADD COLUMN IF NOT EXISTS stripe_customer_id text;

-- 添加索引，加速根据 stripe_customer_id 查找用户（webhook 场景）
CREATE INDEX IF NOT EXISTS idx_users_stripe_customer_id
  ON public.users (stripe_customer_id)
  WHERE stripe_customer_id IS NOT NULL;

COMMENT ON COLUMN public.users.stripe_customer_id IS 'Stripe Customer ID，首次支付时自动创建并保存';
