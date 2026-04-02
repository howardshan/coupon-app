-- ============================================================
-- 竞价推广系统 Migration
-- 6 表 + 7 函数 + 1 trigger + 3 pg_cron
-- 注意：DROP COLUMN is_sponsored 在单独的 migration 文件中
-- ============================================================

-- ============================================================
-- Step 1: ad_accounts 广告账户余额表
-- ============================================================
CREATE TABLE IF NOT EXISTS ad_accounts (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id     uuid NOT NULL UNIQUE REFERENCES merchants(id) ON DELETE CASCADE,
  balance         numeric(10,2) NOT NULL DEFAULT 0 CHECK (balance >= 0),
  total_recharged numeric(10,2) NOT NULL DEFAULT 0,
  total_spent     numeric(10,2) NOT NULL DEFAULT 0,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ad_accounts_merchant_id ON ad_accounts(merchant_id);

ALTER TABLE ad_accounts ENABLE ROW LEVEL SECURITY;

-- 商家 owner 和员工可查看自己的广告账户
CREATE POLICY "merchant_view_own_ad_account" ON ad_accounts
  FOR SELECT USING (
    merchant_id IN (
      SELECT id FROM merchants WHERE user_id = auth.uid()
      UNION
      SELECT merchant_id FROM merchant_staff WHERE user_id = auth.uid()
    )
  );

-- updated_at 自动更新
CREATE TRIGGER set_ad_accounts_updated_at
  BEFORE UPDATE ON ad_accounts
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================
-- Step 2: ad_recharges 充值记录表
-- ============================================================
CREATE TABLE IF NOT EXISTS ad_recharges (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id              uuid NOT NULL REFERENCES merchants(id),
  ad_account_id            uuid NOT NULL REFERENCES ad_accounts(id),
  amount                   numeric(10,2) NOT NULL CHECK (amount >= 20),
  stripe_payment_intent_id text NOT NULL UNIQUE,
  status                   text NOT NULL DEFAULT 'pending'
                             CHECK (status IN ('pending', 'succeeded', 'failed')),
  created_at               timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ad_recharges_merchant
  ON ad_recharges(merchant_id, created_at DESC);

ALTER TABLE ad_recharges ENABLE ROW LEVEL SECURITY;

CREATE POLICY "merchant_view_own_recharges" ON ad_recharges
  FOR SELECT USING (
    merchant_id IN (
      SELECT id FROM merchants WHERE user_id = auth.uid()
      UNION
      SELECT merchant_id FROM merchant_staff WHERE user_id = auth.uid()
    )
  );

-- ============================================================
-- Step 3: ad_placement_config 广告位配置表
-- ============================================================
CREATE TABLE IF NOT EXISTS ad_placement_config (
  placement    text PRIMARY KEY,
  min_bid      numeric(6,4) NOT NULL DEFAULT 0.10,
  max_slots    int NOT NULL DEFAULT 3,
  billing_type text NOT NULL CHECK (billing_type IN ('cpm', 'cpc')),
  updated_at   timestamptz NOT NULL DEFAULT now()
);

-- RLS：公开可读，仅 serviceRole 可写
ALTER TABLE ad_placement_config ENABLE ROW LEVEL SECURITY;
CREATE POLICY "public_read_placement_config" ON ad_placement_config
  FOR SELECT USING (true);

-- 初始化 5 个广告位
INSERT INTO ad_placement_config (placement, min_bid, max_slots, billing_type) VALUES
  ('home_banner',         0.50, 5, 'cpm'),
  ('home_deal_top',       0.20, 3, 'cpc'),
  ('home_store_top',      0.15, 3, 'cpc'),
  ('category_store_top',  0.10, 3, 'cpc'),
  ('category_deal_top',   0.08, 3, 'cpc')
ON CONFLICT (placement) DO NOTHING;

-- ============================================================
-- Step 4: ad_campaigns 广告投放计划表
-- ============================================================
CREATE TABLE IF NOT EXISTS ad_campaigns (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id     uuid NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
  ad_account_id   uuid NOT NULL REFERENCES ad_accounts(id),

  -- 投放对象
  target_type     text NOT NULL CHECK (target_type IN ('deal', 'store')),
  target_id       uuid NOT NULL,   -- deal_id 或 merchant_id

  -- 广告位
  placement       text NOT NULL CHECK (placement IN (
                    'home_banner',
                    'home_deal_top',
                    'home_store_top',
                    'category_store_top',
                    'category_deal_top'
                  )),
  category_id     int REFERENCES categories(id),  -- 分类页投放时填写

  -- 出价
  bid_price       numeric(6,4) NOT NULL CHECK (bid_price > 0),
  daily_budget    numeric(8,2) NOT NULL CHECK (daily_budget >= 10),

  -- 投放时段（NULL = 全天）
  schedule_hours  int[],  -- [11,12,13,17,18,19,20] = 午饭 + 晚饭时段

  -- 时间范围
  start_at        timestamptz NOT NULL DEFAULT now(),
  end_at          timestamptz,  -- NULL = 永不过期

  -- 状态：admin_paused 仅 Admin 可设/恢复
  status          text NOT NULL DEFAULT 'active'
                    CHECK (status IN ('active', 'paused', 'exhausted', 'ended', 'admin_paused')),
  admin_note      text,  -- Admin 暂停原因

  -- 今日统计（每日重置）
  today_spend       numeric(8,2) NOT NULL DEFAULT 0,
  today_impressions int NOT NULL DEFAULT 0,
  today_clicks      int NOT NULL DEFAULT 0,

  -- 累计统计
  total_spend       numeric(10,2) NOT NULL DEFAULT 0,
  total_impressions int NOT NULL DEFAULT 0,
  total_clicks      int NOT NULL DEFAULT 0,

  -- 质量分（每小时更新）
  quality_score   numeric(4,3) NOT NULL DEFAULT 0.700,
  ad_score        numeric(10,4) NOT NULL DEFAULT 0,  -- bid × quality，排名用

  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

-- 同商家同广告位只允许1个活跃或管理员暂停的 campaign
CREATE UNIQUE INDEX IF NOT EXISTS idx_ad_campaigns_one_active_per_placement
  ON ad_campaigns(merchant_id, placement) WHERE status IN ('active', 'admin_paused');

-- 按广告位和分数排序的索引（排名查询用）
CREATE INDEX IF NOT EXISTS idx_ad_campaigns_placement_score
  ON ad_campaigns(placement, ad_score DESC)
  WHERE status = 'active';

CREATE INDEX IF NOT EXISTS idx_ad_campaigns_merchant_id
  ON ad_campaigns(merchant_id);

ALTER TABLE ad_campaigns ENABLE ROW LEVEL SECURITY;

CREATE POLICY "merchant_manage_own_campaigns" ON ad_campaigns
  FOR ALL USING (
    merchant_id IN (
      SELECT id FROM merchants WHERE user_id = auth.uid()
      UNION
      SELECT merchant_id FROM merchant_staff WHERE user_id = auth.uid()
    )
  );

CREATE TRIGGER set_ad_campaigns_updated_at
  BEFORE UPDATE ON ad_campaigns
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================
-- Step 5: ad_events 广告事件日志表
-- ============================================================
CREATE TABLE IF NOT EXISTS ad_events (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id uuid NOT NULL REFERENCES ad_campaigns(id),
  merchant_id uuid NOT NULL REFERENCES merchants(id),
  event_type  text NOT NULL CHECK (event_type IN ('impression', 'click', 'conversion')),
  cost        numeric(8,4) NOT NULL DEFAULT 0,
  user_id     uuid REFERENCES users(id),
  occurred_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ad_events_campaign
  ON ad_events(campaign_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_ad_events_merchant
  ON ad_events(merchant_id, occurred_at DESC);

-- 点击去重查询索引（同用户同campaign近30秒）
CREATE INDEX IF NOT EXISTS idx_ad_events_dedup
  ON ad_events(campaign_id, user_id, occurred_at DESC)
  WHERE event_type = 'click';

-- ad_events 不启用 RLS（仅 serviceRole 写入）
ALTER TABLE ad_events ENABLE ROW LEVEL SECURITY;
-- 无用户直接访问策略，仅通过 Edge Function + serviceRole 操作

-- ============================================================
-- Step 6: ad_daily_stats 每日统计汇总表
-- ============================================================
CREATE TABLE IF NOT EXISTS ad_daily_stats (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id  uuid NOT NULL REFERENCES ad_campaigns(id),
  merchant_id  uuid NOT NULL REFERENCES merchants(id),
  date         date NOT NULL,
  impressions  int NOT NULL DEFAULT 0,
  clicks       int NOT NULL DEFAULT 0,
  conversions  int NOT NULL DEFAULT 0,
  spend        numeric(8,2) NOT NULL DEFAULT 0,
  avg_position numeric(4,2),
  UNIQUE(campaign_id, date)
);

CREATE INDEX IF NOT EXISTS idx_ad_daily_stats_merchant
  ON ad_daily_stats(merchant_id, date DESC);

ALTER TABLE ad_daily_stats ENABLE ROW LEVEL SECURITY;

CREATE POLICY "merchant_view_own_stats" ON ad_daily_stats
  FOR SELECT USING (
    merchant_id IN (
      SELECT id FROM merchants WHERE user_id = auth.uid()
      UNION
      SELECT merchant_id FROM merchant_staff WHERE user_id = auth.uid()
    )
  );

-- ============================================================
-- Step 7: charge_ad_account 扣费事务函数
-- 返回 text：'ok' / 'ok_low_balance' / 'insufficient_balance' / 'daily_budget_exceeded'
-- 锁顺序：先 ad_accounts 再 ad_campaigns（固定，防死锁）
-- ============================================================
CREATE OR REPLACE FUNCTION charge_ad_account(
  p_campaign_id  uuid,
  p_merchant_id  uuid,
  p_cost         numeric,
  p_event_type   text,
  p_user_id      uuid DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  v_balance      numeric;
  v_today_spend  numeric;
  v_daily_budget numeric;
  v_result       text := 'ok';
BEGIN
  -- 锁顺序 1/2：先锁 ad_accounts
  SELECT balance INTO v_balance
  FROM ad_accounts
  WHERE merchant_id = p_merchant_id
  FOR UPDATE;

  IF v_balance IS NULL THEN
    RETURN 'insufficient_balance';
  END IF;

  IF v_balance < p_cost THEN
    RETURN 'insufficient_balance';
  END IF;

  -- 锁顺序 2/2：再锁 ad_campaigns
  SELECT today_spend, daily_budget INTO v_today_spend, v_daily_budget
  FROM ad_campaigns
  WHERE id = p_campaign_id
  FOR UPDATE;

  IF v_today_spend + p_cost > v_daily_budget THEN
    UPDATE ad_campaigns SET status = 'exhausted', updated_at = now()
    WHERE id = p_campaign_id;
    RETURN 'daily_budget_exceeded';
  END IF;

  -- 扣余额
  UPDATE ad_accounts SET
    balance      = balance - p_cost,
    total_spent  = total_spent + p_cost,
    updated_at   = now()
  WHERE merchant_id = p_merchant_id;

  -- 更新 campaign 统计
  UPDATE ad_campaigns SET
    today_spend       = today_spend + p_cost,
    total_spend       = total_spend + p_cost,
    today_impressions = today_impressions + CASE WHEN p_event_type = 'impression' THEN 1 ELSE 0 END,
    today_clicks      = today_clicks      + CASE WHEN p_event_type = 'click'      THEN 1 ELSE 0 END,
    total_impressions = total_impressions + CASE WHEN p_event_type = 'impression' THEN 1 ELSE 0 END,
    total_clicks      = total_clicks      + CASE WHEN p_event_type = 'click'      THEN 1 ELSE 0 END,
    updated_at        = now()
  WHERE id = p_campaign_id;

  -- 写事件日志
  INSERT INTO ad_events (campaign_id, merchant_id, event_type, cost, user_id)
  VALUES (p_campaign_id, p_merchant_id, p_event_type, p_cost, p_user_id);

  -- 低余额预警：扣费后余额 < 该 campaign 的日预算
  IF (v_balance - p_cost) < v_daily_budget THEN
    v_result := 'ok_low_balance';
  END IF;

  RETURN v_result;
END;
$$;

-- ============================================================
-- Step 8: add_ad_balance 充值到账函数（幂等）
-- 内部完成 recharge 状态更新 + 余额增加，同一事务
-- 返回 text：'ok' / 'already_processed' / 'not_found'
-- ============================================================
CREATE OR REPLACE FUNCTION add_ad_balance(
  p_merchant_id       uuid,
  p_amount            numeric,
  p_payment_intent_id text
)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  v_recharge_status text;
BEGIN
  -- 查找充值记录并锁定
  SELECT status INTO v_recharge_status
  FROM ad_recharges
  WHERE stripe_payment_intent_id = p_payment_intent_id
  FOR UPDATE;

  IF v_recharge_status IS NULL THEN
    RETURN 'not_found';
  END IF;

  -- 幂等：已处理过直接返回
  IF v_recharge_status = 'succeeded' THEN
    RETURN 'already_processed';
  END IF;

  -- 更新充值记录状态
  UPDATE ad_recharges
  SET status = 'succeeded'
  WHERE stripe_payment_intent_id = p_payment_intent_id;

  -- 增加广告账户余额
  UPDATE ad_accounts SET
    balance         = balance + p_amount,
    total_recharged = total_recharged + p_amount,
    updated_at      = now()
  WHERE merchant_id = p_merchant_id;

  RETURN 'ok';
END;
$$;

-- ============================================================
-- Step 9: get_active_ads 获取活跃广告（排名查询）
-- 函数内自行计算 Dallas 时区的当前小时
-- ============================================================
CREATE OR REPLACE FUNCTION get_active_ads(
  p_placement   text,
  p_category_id int DEFAULT NULL,
  p_limit       int DEFAULT 3
)
RETURNS TABLE (
  campaign_id   uuid,
  merchant_id   uuid,
  target_type   text,
  target_id     uuid,
  placement     text,
  bid_price     numeric,
  ad_score      numeric,
  quality_score numeric
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_current_hour int;
  v_min_bid      numeric;
BEGIN
  -- 使用 Dallas 时区计算当前小时
  v_current_hour := EXTRACT(HOUR FROM now() AT TIME ZONE 'America/Chicago')::int;

  -- 获取该广告位的最低出价
  SELECT apc.min_bid INTO v_min_bid
  FROM ad_placement_config apc
  WHERE apc.placement = p_placement;

  IF v_min_bid IS NULL THEN
    v_min_bid := 0;
  END IF;

  RETURN QUERY
  SELECT
    ac.id AS campaign_id,
    ac.merchant_id,
    ac.target_type,
    ac.target_id,
    ac.placement,
    ac.bid_price,
    ac.ad_score,
    ac.quality_score
  FROM ad_campaigns ac
  JOIN ad_accounts aa ON aa.merchant_id = ac.merchant_id
  WHERE ac.placement = p_placement
    AND ac.status = 'active'
    AND ac.today_spend < ac.daily_budget
    AND aa.balance > 0
    AND (ac.start_at IS NULL OR ac.start_at <= now())
    AND (ac.end_at IS NULL OR ac.end_at > now())
    AND (ac.schedule_hours IS NULL OR v_current_hour = ANY(ac.schedule_hours))
    AND (p_category_id IS NULL OR ac.category_id = p_category_id)
    AND ac.bid_price >= v_min_bid
  ORDER BY ac.ad_score DESC
  LIMIT p_limit;
END;
$$;

-- ============================================================
-- Step 10: reset_daily_ad_stats 每日重置函数
-- 时区：America/Chicago
-- ============================================================
CREATE OR REPLACE FUNCTION reset_daily_ad_stats()
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_yesterday date;
BEGIN
  -- 使用 Dallas 时区计算"昨天"
  v_yesterday := (now() AT TIME ZONE 'America/Chicago')::date - 1;

  -- 汇总昨天数据到 ad_daily_stats
  INSERT INTO ad_daily_stats (campaign_id, merchant_id, date,
    impressions, clicks, spend)
  SELECT id, merchant_id, v_yesterday,
    today_impressions, today_clicks, today_spend
  FROM ad_campaigns
  WHERE today_spend > 0
  ON CONFLICT (campaign_id, date) DO UPDATE
    SET impressions = EXCLUDED.impressions,
        clicks      = EXCLUDED.clicks,
        spend       = EXCLUDED.spend;

  -- 过期 Campaign 标记为 ended
  UPDATE ad_campaigns SET status = 'ended', updated_at = now()
  WHERE end_at IS NOT NULL
    AND end_at <= now()
    AND status IN ('active', 'paused', 'exhausted');

  -- 重置今日统计（不重置 ended 和 admin_paused）
  UPDATE ad_campaigns SET
    today_spend       = 0,
    today_impressions = 0,
    today_clicks      = 0,
    status = CASE
      WHEN status = 'exhausted' THEN 'active'
      ELSE status
    END
  WHERE status NOT IN ('ended', 'admin_paused');
END;
$$;

-- ============================================================
-- Step 11: update_ad_quality_scores 质量分更新（V1：CTR + rating）
-- avg_ctr 按同广告位内有效数据（impressions > 100）计算
-- ============================================================
CREATE OR REPLACE FUNCTION update_ad_quality_scores()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE ad_campaigns ac SET
    quality_score = GREATEST(0.1, LEAST(2.0,
      -- V1：0.6 × ctr_score + 0.4 × rating_score
      0.6 * COALESCE(
        -- ctr_score = campaign_ctr / avg_ctr_for_placement
        (ac.total_clicks::numeric / NULLIF(ac.total_impressions, 0))
        / NULLIF(
          (SELECT AVG(c2.total_clicks::numeric / NULLIF(c2.total_impressions, 0))
           FROM ad_campaigns c2
           WHERE c2.placement = ac.placement
             AND c2.total_impressions > 100),
          0
        ),
        0.7  -- 新广告默认
      )
      + 0.4 * COALESCE(
        (SELECT m.avg_rating FROM merchants m WHERE m.id = ac.merchant_id),
        0
      ) / 5.0
    )),
    ad_score = ac.bid_price * GREATEST(0.1, LEAST(2.0,
      0.6 * COALESCE(
        (ac.total_clicks::numeric / NULLIF(ac.total_impressions, 0))
        / NULLIF(
          (SELECT AVG(c2.total_clicks::numeric / NULLIF(c2.total_impressions, 0))
           FROM ad_campaigns c2
           WHERE c2.placement = ac.placement
             AND c2.total_impressions > 100),
          0
        ),
        0.7
      )
      + 0.4 * COALESCE(
        (SELECT m.avg_rating FROM merchants m WHERE m.id = ac.merchant_id),
        0
      ) / 5.0
    )),
    updated_at = now()
  WHERE ac.status IN ('active', 'exhausted', 'paused');
END;
$$;

-- ============================================================
-- Step 12: auto_create_ad_account 新商家自动创建广告账户
-- 含 ON CONFLICT 保护（防御性编程）
-- ============================================================
CREATE OR REPLACE FUNCTION auto_create_ad_account()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO ad_accounts (merchant_id)
  VALUES (NEW.id)
  ON CONFLICT (merchant_id) DO NOTHING;
  RETURN NEW;
END;
$$;

-- ============================================================
-- Step 13: 为已有商家批量创建广告账户（在 trigger 之前执行）
-- ============================================================
INSERT INTO ad_accounts (merchant_id)
SELECT id FROM merchants
WHERE id NOT IN (SELECT merchant_id FROM ad_accounts)
ON CONFLICT (merchant_id) DO NOTHING;

-- 创建 trigger（在批量 INSERT 之后）
CREATE TRIGGER on_merchant_insert_create_ad_account
  AFTER INSERT ON merchants
  FOR EACH ROW EXECUTE FUNCTION auto_create_ad_account();

-- ============================================================
-- Step 14: recommendation_config 字段更新
-- sponsor_boost → max_sponsor_boost，默认 200
-- ============================================================
UPDATE recommendation_config
SET weights = (weights - 'sponsor_boost') || '{"max_sponsor_boost": 200}'::jsonb
WHERE weights ? 'sponsor_boost';

-- 如果没有 sponsor_boost 字段，直接添加 max_sponsor_boost
UPDATE recommendation_config
SET weights = weights || '{"max_sponsor_boost": 200}'::jsonb
WHERE NOT (weights ? 'max_sponsor_boost');

-- ============================================================
-- Step 15: pg_cron 定时任务
-- ============================================================

-- 每日重置（UTC 6:00 = CST 0:00 冬令时 / CDT 1:00 夏令时）
SELECT cron.schedule(
  'reset-daily-ad-stats',
  '0 6 * * *',
  $$ SELECT reset_daily_ad_stats(); $$
);

-- 每小时更新质量分
SELECT cron.schedule(
  'update-ad-quality-scores',
  '0 * * * *',
  $$ SELECT update_ad_quality_scores(); $$
);

-- 每天凌晨 3:00 UTC 清理 90 天前 ad_events + 730 天前 ad_daily_stats
SELECT cron.schedule(
  'cleanup-ad-data',
  '0 3 * * *',
  $$
    DELETE FROM ad_events WHERE occurred_at < now() - interval '90 days';
    DELETE FROM ad_daily_stats WHERE date < (CURRENT_DATE - 730);
  $$
);
