-- =============================================================
-- Deal 多店通用支持
-- deals 表新增 applicable_merchant_ids 字段
-- coupons 表新增 redeemed_at_merchant_id 字段（记录实际核销门店）
-- =============================================================

-- 1. deals 表新增适用门店 ID 数组
-- NULL = 仅限创建门店（默认行为，兼容现有数据）
-- 非空数组 = 指定适用门店列表
ALTER TABLE deals
  ADD COLUMN IF NOT EXISTS applicable_merchant_ids UUID[] DEFAULT NULL;

-- 2. coupons 表新增实际核销门店 ID
-- 用于结算时按实际核销门店归属收入
-- 注意: 已有 redeemed_by_merchant_id 字段，确认是否已存在
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'coupons' AND column_name = 'redeemed_at_merchant_id'
  ) THEN
    ALTER TABLE coupons
      ADD COLUMN redeemed_at_merchant_id UUID REFERENCES merchants(id);
  END IF;
END $$;

-- 3. 创建索引加速查询"某门店可用的 Deal"
CREATE INDEX IF NOT EXISTS idx_deals_applicable_merchant_ids
  ON deals USING GIN (applicable_merchant_ids);

-- 4. 创建辅助函数：检查某门店是否在 Deal 的适用范围内
CREATE OR REPLACE FUNCTION is_deal_applicable_at(
  p_deal_merchant_id UUID,
  p_applicable_ids UUID[],
  p_target_merchant_id UUID
) RETURNS BOOLEAN AS $$
BEGIN
  -- 如果 applicable_merchant_ids 为 NULL，仅限创建门店
  IF p_applicable_ids IS NULL THEN
    RETURN p_deal_merchant_id = p_target_merchant_id;
  END IF;
  -- 否则检查目标门店是否在适用列表中
  RETURN p_target_merchant_id = ANY(p_applicable_ids);
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON COLUMN deals.applicable_merchant_ids IS '适用门店ID列表，NULL表示仅限创建门店';
COMMENT ON COLUMN coupons.redeemed_at_merchant_id IS '实际核销门店ID，用于按店结算';
