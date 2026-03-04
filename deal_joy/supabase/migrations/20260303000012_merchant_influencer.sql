-- ============================================================
-- Module 12: Influencer 合作
-- 商家达人推广任务、申请、效果追踪表
-- 优先级: P2/V2 — 表结构先建，业务逻辑 V2 实现
-- ============================================================

-- ============================================================
-- 1. influencer_campaigns — 商家创建的推广任务表
-- ============================================================
CREATE TABLE IF NOT EXISTS influencer_campaigns (
  id                  uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id         uuid          NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
  deal_id             uuid          REFERENCES deals(id) ON DELETE SET NULL,
  title               text          NOT NULL,
  requirements        text,                                         -- 推广要求描述
  compensation_type   text          NOT NULL                        -- 报酬模式
    CHECK (compensation_type IN ('fixed', 'per_redemption', 'revenue_share')),
  compensation_amount numeric(10,2) NOT NULL CHECK (compensation_amount > 0), -- 报酬金额/比例
  budget              numeric(10,2) NOT NULL CHECK (budget >= compensation_amount), -- 总预算上限
  status              text          NOT NULL DEFAULT 'draft'        -- Campaign 状态
    CHECK (status IN ('draft', 'active', 'completed')),
  created_at          timestamptz   NOT NULL DEFAULT now(),
  updated_at          timestamptz   NOT NULL DEFAULT now()
);

-- 索引
CREATE INDEX IF NOT EXISTS idx_influencer_campaigns_merchant_id ON influencer_campaigns(merchant_id);
CREATE INDEX IF NOT EXISTS idx_influencer_campaigns_status      ON influencer_campaigns(status);
CREATE INDEX IF NOT EXISTS idx_influencer_campaigns_deal_id     ON influencer_campaigns(deal_id) WHERE deal_id IS NOT NULL;

-- updated_at 自动触发器（复用已有模式）
CREATE OR REPLACE FUNCTION update_influencer_campaigns_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_influencer_campaigns_updated_at
  BEFORE UPDATE ON influencer_campaigns
  FOR EACH ROW EXECUTE FUNCTION update_influencer_campaigns_updated_at();

-- ============================================================
-- 2. influencer_applications — 达人申请参与 Campaign 的记录表
-- ============================================================
CREATE TABLE IF NOT EXISTS influencer_applications (
  id                  uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id         uuid          NOT NULL REFERENCES influencer_campaigns(id) ON DELETE CASCADE,
  influencer_user_id  uuid          NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE, -- 达人的 auth user id
  status              text          NOT NULL DEFAULT 'pending'      -- 审批状态
    CHECK (status IN ('pending', 'approved', 'rejected')),
  promo_link          text,                                         -- 审批通过后自动生成的推广链接
  rejection_reason    text,                                         -- 拒绝原因（可选）
  applied_at          timestamptz   NOT NULL DEFAULT now(),
  reviewed_at         timestamptz                                   -- 审批时间
);

-- 唯一约束：同一 Campaign 每个 Influencer 只能申请一次
CREATE UNIQUE INDEX IF NOT EXISTS uq_influencer_application
  ON influencer_applications(campaign_id, influencer_user_id);

-- 其他索引
CREATE INDEX IF NOT EXISTS idx_influencer_applications_campaign_id
  ON influencer_applications(campaign_id);
CREATE INDEX IF NOT EXISTS idx_influencer_applications_influencer_user_id
  ON influencer_applications(influencer_user_id);
CREATE INDEX IF NOT EXISTS idx_influencer_applications_status
  ON influencer_applications(status);

-- ============================================================
-- 3. influencer_performance — 达人效果追踪与佣金结算表
-- ============================================================
CREATE TABLE IF NOT EXISTS influencer_performance (
  id                  uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id         uuid          NOT NULL REFERENCES influencer_campaigns(id) ON DELETE CASCADE,
  influencer_user_id  uuid          NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  clicks              integer       NOT NULL DEFAULT 0 CHECK (clicks >= 0),       -- 推广链接点击次数
  purchases           integer       NOT NULL DEFAULT 0 CHECK (purchases >= 0),    -- 带来的购买次数
  redemptions         integer       NOT NULL DEFAULT 0 CHECK (redemptions >= 0),  -- 带来的核销次数
  commission_amount   numeric(10,2) NOT NULL DEFAULT 0.00 CHECK (commission_amount >= 0), -- 应付佣金 USD
  settlement_status   text          NOT NULL DEFAULT 'pending'
    CHECK (settlement_status IN ('pending', 'paid')),               -- 结算状态
  paid_at             timestamptz,                                  -- 打款时间
  created_at          timestamptz   NOT NULL DEFAULT now(),
  updated_at          timestamptz   NOT NULL DEFAULT now()
);

-- 唯一约束：每个 Campaign 每个 Influencer 只有一条汇总性能记录
CREATE UNIQUE INDEX IF NOT EXISTS uq_influencer_performance
  ON influencer_performance(campaign_id, influencer_user_id);

-- 索引
CREATE INDEX IF NOT EXISTS idx_influencer_performance_campaign_id
  ON influencer_performance(campaign_id);
CREATE INDEX IF NOT EXISTS idx_influencer_performance_influencer_user_id
  ON influencer_performance(influencer_user_id);
CREATE INDEX IF NOT EXISTS idx_influencer_performance_settlement
  ON influencer_performance(settlement_status);

-- updated_at 自动触发器
CREATE OR REPLACE FUNCTION update_influencer_performance_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_influencer_performance_updated_at
  BEFORE UPDATE ON influencer_performance
  FOR EACH ROW EXECUTE FUNCTION update_influencer_performance_updated_at();

-- ============================================================
-- 4. RLS 策略
-- ============================================================

-- influencer_campaigns RLS
ALTER TABLE influencer_campaigns ENABLE ROW LEVEL SECURITY;

-- 商家管理自己的 Campaign（全权限）
CREATE POLICY merchants_manage_own_campaigns ON influencer_campaigns
  FOR ALL
  USING (
    merchant_id IN (
      SELECT id FROM merchants WHERE user_id = auth.uid()
    )
  );

-- influencer_applications RLS
ALTER TABLE influencer_applications ENABLE ROW LEVEL SECURITY;

-- 商家读取自己 Campaign 下的申请
CREATE POLICY merchants_read_own_campaign_applications ON influencer_applications
  FOR SELECT
  USING (
    campaign_id IN (
      SELECT id FROM influencer_campaigns
      WHERE merchant_id IN (SELECT id FROM merchants WHERE user_id = auth.uid())
    )
  );

-- 商家更新自己 Campaign 下的申请（审批操作）
CREATE POLICY merchants_update_own_campaign_applications ON influencer_applications
  FOR UPDATE
  USING (
    campaign_id IN (
      SELECT id FROM influencer_campaigns
      WHERE merchant_id IN (SELECT id FROM merchants WHERE user_id = auth.uid())
    )
  );

-- 达人提交自己的申请（V2 用户端使用）
CREATE POLICY influencers_insert_own_applications ON influencer_applications
  FOR INSERT
  WITH CHECK (influencer_user_id = auth.uid());

-- 达人读取自己的申请状态
CREATE POLICY influencers_read_own_applications ON influencer_applications
  FOR SELECT
  USING (influencer_user_id = auth.uid());

-- influencer_performance RLS
ALTER TABLE influencer_performance ENABLE ROW LEVEL SECURITY;

-- 商家读取自己 Campaign 的所有达人数据
CREATE POLICY merchants_read_own_campaign_performance ON influencer_performance
  FOR SELECT
  USING (
    campaign_id IN (
      SELECT id FROM influencer_campaigns
      WHERE merchant_id IN (SELECT id FROM merchants WHERE user_id = auth.uid())
    )
  );

-- 达人读取自己的效果数据
CREATE POLICY influencers_read_own_performance ON influencer_performance
  FOR SELECT
  USING (influencer_user_id = auth.uid());

-- ============================================================
-- 注释说明
-- ============================================================
COMMENT ON TABLE influencer_campaigns   IS 'Influencer 合作 - 商家创建的推广 Campaign，V2 实现完整业务';
COMMENT ON TABLE influencer_applications IS 'Influencer 合作 - 达人申请参与 Campaign 的记录，V2 实现审批流程';
COMMENT ON TABLE influencer_performance IS 'Influencer 合作 - 效果追踪与佣金结算，V2 接入 Stripe Connect Payout';
