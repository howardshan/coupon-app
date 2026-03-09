-- V2.5 品牌级营销工具
-- 品牌活动、品牌优惠券、品牌忠诚度

-- 品牌级营销活动
CREATE TABLE IF NOT EXISTS brand_campaigns (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  brand_id UUID NOT NULL REFERENCES brands(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT DEFAULT '',
  campaign_type TEXT NOT NULL DEFAULT 'discount',
    -- discount: 全品牌折扣
    -- bogo: 买一赠一
    -- bundle: 组合优惠
    -- loyalty: 忠诚度奖励
  discount_type TEXT DEFAULT 'percentage',
    -- percentage: 百分比折扣
    -- fixed: 固定金额减免
  discount_value NUMERIC(10,2) DEFAULT 0,
  min_spend NUMERIC(10,2) DEFAULT 0,
  applicable_store_ids UUID[] DEFAULT NULL, -- NULL=全部门店
  start_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  end_date TIMESTAMPTZ,
  max_uses INT DEFAULT NULL, -- NULL=无限制
  current_uses INT DEFAULT 0,
  is_active BOOLEAN DEFAULT true,
  created_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 品牌优惠码
CREATE TABLE IF NOT EXISTS brand_promo_codes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  brand_id UUID NOT NULL REFERENCES brands(id) ON DELETE CASCADE,
  campaign_id UUID REFERENCES brand_campaigns(id) ON DELETE SET NULL,
  code TEXT NOT NULL,
  discount_type TEXT NOT NULL DEFAULT 'percentage',
  discount_value NUMERIC(10,2) NOT NULL DEFAULT 0,
  min_spend NUMERIC(10,2) DEFAULT 0,
  max_uses INT DEFAULT NULL,
  current_uses INT DEFAULT 0,
  applicable_store_ids UUID[] DEFAULT NULL,
  start_date TIMESTAMPTZ DEFAULT NOW(),
  end_date TIMESTAMPTZ,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(brand_id, code)
);

-- 品牌忠诚度积分
CREATE TABLE IF NOT EXISTS brand_loyalty_points (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  brand_id UUID NOT NULL REFERENCES brands(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id),
  points INT NOT NULL DEFAULT 0,
  lifetime_points INT NOT NULL DEFAULT 0,
  tier TEXT DEFAULT 'bronze', -- bronze / silver / gold / platinum
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(brand_id, user_id)
);

-- 忠诚度积分交易记录
CREATE TABLE IF NOT EXISTS loyalty_transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  brand_id UUID NOT NULL REFERENCES brands(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id),
  points INT NOT NULL, -- 正=获得，负=消耗
  transaction_type TEXT NOT NULL, -- earn / redeem / expire / bonus
  reference_id UUID, -- 关联的 order/coupon ID
  description TEXT DEFAULT '',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 索引
CREATE INDEX IF NOT EXISTS idx_brand_campaigns_brand ON brand_campaigns(brand_id);
CREATE INDEX IF NOT EXISTS idx_brand_campaigns_active ON brand_campaigns(is_active, start_date, end_date);
CREATE INDEX IF NOT EXISTS idx_brand_promo_codes_brand ON brand_promo_codes(brand_id);
CREATE INDEX IF NOT EXISTS idx_brand_promo_codes_code ON brand_promo_codes(code);
CREATE INDEX IF NOT EXISTS idx_brand_loyalty_brand_user ON brand_loyalty_points(brand_id, user_id);
CREATE INDEX IF NOT EXISTS idx_loyalty_tx_user ON loyalty_transactions(user_id, brand_id);

-- RLS
ALTER TABLE brand_campaigns ENABLE ROW LEVEL SECURITY;
ALTER TABLE brand_promo_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE brand_loyalty_points ENABLE ROW LEVEL SECURITY;
ALTER TABLE loyalty_transactions ENABLE ROW LEVEL SECURITY;

-- 品牌管理员可管理活动和优惠码
CREATE POLICY "brand_admins_manage_campaigns" ON brand_campaigns
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM brand_admins
      WHERE brand_admins.brand_id = brand_campaigns.brand_id
        AND brand_admins.user_id = auth.uid()
    )
  );

CREATE POLICY "brand_admins_manage_promo_codes" ON brand_promo_codes
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM brand_admins
      WHERE brand_admins.brand_id = brand_promo_codes.brand_id
        AND brand_admins.user_id = auth.uid()
    )
  );

-- 用户可查看自己的忠诚度积分
CREATE POLICY "users_view_own_loyalty" ON brand_loyalty_points
  FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "brand_admins_manage_loyalty" ON brand_loyalty_points
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM brand_admins
      WHERE brand_admins.brand_id = brand_loyalty_points.brand_id
        AND brand_admins.user_id = auth.uid()
    )
  );

CREATE POLICY "users_view_own_loyalty_tx" ON loyalty_transactions
  FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "brand_admins_manage_loyalty_tx" ON loyalty_transactions
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM brand_admins
      WHERE brand_admins.brand_id = loyalty_transactions.brand_id
        AND brand_admins.user_id = auth.uid()
    )
  );
