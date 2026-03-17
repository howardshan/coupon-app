-- ============================================================
-- 有效期三种模式迁移
-- 1. deals.validity_type 扩展为三个值
-- 2. orders 表新增 capture_method 列
-- ============================================================

-- 第一步：删除旧约束（旧约束名来自 20260303000004_merchant_deals.sql）
ALTER TABLE public.deals DROP CONSTRAINT IF EXISTS deals_validity_type_check;

-- 第二步：迁移现有 days_after_purchase 数据
-- validity_days <= 7 → short_after_purchase（预授权模式）
-- validity_days > 7 或 NULL → long_after_purchase（立即扣款模式）
UPDATE public.deals
  SET validity_type = CASE
    WHEN validity_days IS NOT NULL AND validity_days <= 7 THEN 'short_after_purchase'
    WHEN validity_days IS NOT NULL AND validity_days > 7  THEN 'long_after_purchase'
    ELSE 'long_after_purchase'
  END
WHERE validity_type = 'days_after_purchase';

-- 第三步：添加新约束，支持三种类型
ALTER TABLE public.deals
  ADD CONSTRAINT deals_validity_type_check
    CHECK (validity_type IN ('fixed_date', 'short_after_purchase', 'long_after_purchase'));

-- ============================================================
-- orders 表：新增 capture_method 列
-- 'automatic' = 立即扣款（fixed_date / long_after_purchase）
-- 'manual'    = Stripe 预授权（short_after_purchase，核销时才实收）
-- ============================================================
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS capture_method text NOT NULL DEFAULT 'automatic';

ALTER TABLE public.orders
  DROP CONSTRAINT IF EXISTS orders_capture_method_check;

ALTER TABLE public.orders
  ADD CONSTRAINT orders_capture_method_check
    CHECK (capture_method IN ('automatic', 'manual'));
