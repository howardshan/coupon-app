-- =============================================================
-- 提现系统：银行账户、提现记录、自动提现设置
-- =============================================================

-- 1. 商家银行账户（Stripe Connect）
CREATE TABLE IF NOT EXISTS merchant_bank_accounts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
  stripe_account_id TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'verified', 'disabled')),
  bank_name TEXT,
  last4 TEXT,
  currency TEXT DEFAULT 'usd',
  is_default BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(merchant_id, stripe_account_id)
);

-- 2. 提现记录
CREATE TABLE IF NOT EXISTS withdrawals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
  amount NUMERIC(10,2) NOT NULL CHECK (amount > 0),
  currency TEXT DEFAULT 'usd',
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'cancelled')),
  stripe_payout_id TEXT,
  stripe_transfer_id TEXT,
  bank_account_id UUID REFERENCES merchant_bank_accounts(id),
  failure_reason TEXT,
  requested_by UUID REFERENCES auth.users(id),
  requested_at TIMESTAMPTZ DEFAULT now(),
  processed_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- 3. 商家提现设置
CREATE TABLE IF NOT EXISTS merchant_withdrawal_settings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE UNIQUE,
  auto_withdrawal_enabled BOOLEAN DEFAULT false,
  auto_withdrawal_frequency TEXT DEFAULT 'weekly' CHECK (auto_withdrawal_frequency IN ('daily', 'weekly', 'biweekly', 'monthly')),
  auto_withdrawal_day INTEGER DEFAULT 1, -- 周几(1-7) 或 月几号(1-28)
  min_withdrawal_amount NUMERIC(10,2) DEFAULT 50.00, -- 最低提现金额
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- 索引
CREATE INDEX IF NOT EXISTS idx_withdrawals_merchant_id ON withdrawals(merchant_id);
CREATE INDEX IF NOT EXISTS idx_withdrawals_status ON withdrawals(status);
CREATE INDEX IF NOT EXISTS idx_withdrawals_requested_at ON withdrawals(requested_at DESC);
CREATE INDEX IF NOT EXISTS idx_merchant_bank_accounts_merchant ON merchant_bank_accounts(merchant_id);

-- RLS 策略
ALTER TABLE merchant_bank_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE withdrawals ENABLE ROW LEVEL SECURITY;
ALTER TABLE merchant_withdrawal_settings ENABLE ROW LEVEL SECURITY;

-- 银行账户：商家只能看自己的
CREATE POLICY "merchant_bank_accounts_select" ON merchant_bank_accounts
  FOR SELECT USING (
    merchant_id IN (SELECT id FROM merchants WHERE user_id = auth.uid())
  );

-- 提现记录：商家只能看自己的
CREATE POLICY "withdrawals_select" ON withdrawals
  FOR SELECT USING (
    merchant_id IN (SELECT id FROM merchants WHERE user_id = auth.uid())
  );

-- 提现设置：商家只能看自己的
CREATE POLICY "merchant_withdrawal_settings_select" ON merchant_withdrawal_settings
  FOR SELECT USING (
    merchant_id IN (SELECT id FROM merchants WHERE user_id = auth.uid())
  );

-- Service Role 全权限（Edge Function 使用）
CREATE POLICY "service_role_bank_accounts" ON merchant_bank_accounts
  FOR ALL USING (auth.role() = 'service_role');

CREATE POLICY "service_role_withdrawals" ON withdrawals
  FOR ALL USING (auth.role() = 'service_role');

CREATE POLICY "service_role_withdrawal_settings" ON merchant_withdrawal_settings
  FOR ALL USING (auth.role() = 'service_role');

COMMENT ON TABLE merchant_bank_accounts IS '商家银行账户（Stripe Connect）';
COMMENT ON TABLE withdrawals IS '提现记录';
COMMENT ON TABLE merchant_withdrawal_settings IS '商家提现设置（自动提现等）';
