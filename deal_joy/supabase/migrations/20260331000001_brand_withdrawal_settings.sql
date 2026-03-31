-- =============================================================
-- 品牌自动提现设置表
-- 参考 merchant_withdrawal_settings，为品牌端提供自动/手动提现配置
-- =============================================================

CREATE TABLE IF NOT EXISTS brand_withdrawal_settings (
  brand_id                  UUID PRIMARY KEY REFERENCES brands(id) ON DELETE CASCADE,
  auto_withdrawal_enabled   BOOLEAN NOT NULL DEFAULT false,
  auto_withdrawal_frequency TEXT NOT NULL DEFAULT 'weekly'
    CHECK (auto_withdrawal_frequency IN ('daily','weekly','biweekly','monthly')),
  auto_withdrawal_day       INT NOT NULL DEFAULT 1,
  min_withdrawal_amount     NUMERIC(10,2) NOT NULL DEFAULT 50.00,
  updated_at                TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- RLS: 品牌管理员可读写自己品牌的设置
ALTER TABLE brand_withdrawal_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "brand_admins_manage_own_settings" ON brand_withdrawal_settings
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM brand_admins
      WHERE brand_admins.brand_id = brand_withdrawal_settings.brand_id
        AND brand_admins.user_id = auth.uid()
    )
  );
