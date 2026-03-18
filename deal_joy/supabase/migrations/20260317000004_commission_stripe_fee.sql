-- ============================================================
-- 新增 Stripe 手续费字段 + 生效日期范围到全局抽成配置表
-- ============================================================

ALTER TABLE platform_commission_config
  ADD COLUMN IF NOT EXISTS stripe_processing_rate DECIMAL(5,4) NOT NULL DEFAULT 0.03,
  ADD COLUMN IF NOT EXISTS stripe_flat_fee         DECIMAL(10,2) NOT NULL DEFAULT 0.30,
  ADD COLUMN IF NOT EXISTS effective_from          DATE,
  ADD COLUMN IF NOT EXISTS effective_to            DATE;

-- 更新初始数据（如果已存在）
UPDATE platform_commission_config
SET
  stripe_processing_rate = 0.03,
  stripe_flat_fee        = 0.30
WHERE stripe_processing_rate IS NULL OR stripe_flat_fee IS NULL;
