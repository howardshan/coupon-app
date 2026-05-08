-- 商家合同表
-- 流程：创建(draft) → 发送(sent) → 签署(signed) → 绑定商家(assigned) | 作废(voided)
CREATE TABLE merchant_contracts (
  id                        UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- 合同基本信息
  name                      TEXT NOT NULL,
  recipient_name            TEXT NOT NULL,
  recipient_email           TEXT NOT NULL,

  -- 商业条款
  promo_months              INT NOT NULL DEFAULT 3,
  promo_commission_rate     NUMERIC(5,4) NOT NULL,    -- e.g. 0.05 = 5%
  standard_commission_rate  NUMERIC(5,4) NOT NULL,    -- e.g. 0.15 = 15%
  booster_credit_amount     NUMERIC(10,2) NOT NULL DEFAULT 0,

  -- 状态机
  status                    TEXT NOT NULL DEFAULT 'draft'
                            CHECK (status IN ('draft','sent','signed','assigned','voided')),

  -- Assign 后填入
  merchant_id               UUID REFERENCES merchants(id) ON DELETE SET NULL,
  effective_from            DATE,
  promo_ends_at             DATE,
  standard_rate_applied     BOOLEAN NOT NULL DEFAULT FALSE,
  booster_credit_granted    BOOLEAN NOT NULL DEFAULT FALSE,
  assigned_at               TIMESTAMPTZ,

  -- 合同文档
  content_html              TEXT,              -- 可编辑的合同 HTML 内容，null 时用模板生成
  docusign_envelope_id      TEXT,              -- DocuSign Envelope ID（发送后填入）

  -- 元数据
  notes                     TEXT,
  created_at                TIMESTAMPTZ DEFAULT NOW(),
  created_by                UUID REFERENCES auth.users(id),

  -- 每个商家最多只能被 assign 一份有效合同
  CONSTRAINT one_active_contract_per_merchant UNIQUE (merchant_id)
);

-- RLS：只有 service_role 可写（管理后台用 service client）
ALTER TABLE merchant_contracts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "admin read merchant_contracts"
  ON merchant_contracts FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- 管理员直接赠送 booster credit（不走 Stripe 支付，管理后台专用）
CREATE OR REPLACE FUNCTION admin_grant_booster_credit(
  p_merchant_id uuid,
  p_amount      numeric
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO ad_accounts (merchant_id, balance, total_recharged)
  VALUES (p_merchant_id, p_amount, p_amount)
  ON CONFLICT (merchant_id) DO UPDATE
    SET balance         = ad_accounts.balance + p_amount,
        total_recharged = ad_accounts.total_recharged + p_amount,
        updated_at      = now();
END;
$$;

-- pg_cron: 每日凌晨 2 点自动将已过优惠期的合同切换为标准费率
SELECT cron.schedule(
  'apply-standard-commission-rate',
  '0 2 * * *',
  $$
    -- 更新 merchants.commission_rate 为标准费率
    UPDATE merchants m
    SET commission_rate = mc.standard_commission_rate
    FROM merchant_contracts mc
    WHERE mc.merchant_id = m.id
      AND mc.status = 'assigned'
      AND mc.promo_ends_at < CURRENT_DATE
      AND mc.standard_rate_applied = FALSE;

    -- 标记切换完成
    UPDATE merchant_contracts
    SET standard_rate_applied = TRUE
    WHERE status = 'assigned'
      AND promo_ends_at < CURRENT_DATE
      AND standard_rate_applied = FALSE;
  $$
);
