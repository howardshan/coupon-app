-- ============================================================
-- 推荐算法系统 Migration
-- 创建日期：2026-03-26
-- ============================================================

-- ============================================================
-- Step 1: deals 表新增推荐相关字段
-- 侦察结果：category 已存在(text)，跳过
-- ============================================================
ALTER TABLE deals
  ADD COLUMN IF NOT EXISTS meal_type text
    CHECK (meal_type IN ('breakfast','lunch','dinner','all_day','n/a')),
  ADD COLUMN IF NOT EXISTS price_tier text
    CHECK (price_tier IN ('budget','mid','premium')),
  ADD COLUMN IF NOT EXISTS tags text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS is_sponsored boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS sponsor_priority int DEFAULT 0;

-- ============================================================
-- Step 2: merchants 表新增推荐相关字段
-- 侦察结果：category/tags/lat/lng/avg_rating/review_count 已存在，跳过
-- ============================================================
ALTER TABLE merchants
  ADD COLUMN IF NOT EXISTS cuisine_type text,
  ADD COLUMN IF NOT EXISTS avg_redemption_rate numeric(4,3) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS refund_rate numeric(4,3) DEFAULT 0;

-- ============================================================
-- Step 3: user_events 用户行为事件日志表
-- ============================================================
CREATE TABLE IF NOT EXISTS user_events (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  event_type  text NOT NULL CHECK (event_type IN (
                'view_deal','view_merchant','search',
                'purchase','redeem','review','refund'
              )),
  deal_id     uuid REFERENCES deals(id),
  merchant_id uuid REFERENCES merchants(id),
  metadata    jsonb,
  occurred_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_user_events_user_id
  ON user_events(user_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_user_events_type_time
  ON user_events(event_type, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_user_events_deal_id
  ON user_events(deal_id) WHERE deal_id IS NOT NULL;

-- RLS：用户只能插入和查看自己的事件
ALTER TABLE user_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users_insert_own_events" ON user_events
  FOR INSERT WITH CHECK (user_id = auth.uid());
CREATE POLICY "users_view_own_events" ON user_events
  FOR SELECT USING (user_id = auth.uid());
-- service_role 可以读写所有事件（Edge Function 用）
CREATE POLICY "service_role_full_access_events" ON user_events
  FOR ALL USING (auth.role() = 'service_role');

-- ============================================================
-- Step 4: user_tags 用户标签表（定时任务计算）
-- ============================================================
CREATE TABLE IF NOT EXISTS user_tags (
  user_id            uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  top_categories     text[] NOT NULL DEFAULT '{}',
  avg_spend          numeric(10,2) DEFAULT 0,
  price_tier         text DEFAULT 'mid',
  active_time_slots  text[] NOT NULL DEFAULT '{}',
  favorite_hashtags  text[] NOT NULL DEFAULT '{}',
  purchase_frequency text DEFAULT 'low',
  location_lat       numeric(10,7),
  location_lng       numeric(10,7),
  search_keywords    text[] NOT NULL DEFAULT '{}',
  last_updated_at    timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE user_tags ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users_view_own_tags" ON user_tags
  FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "service_role_full_access_tags" ON user_tags
  FOR ALL USING (auth.role() = 'service_role');

-- ============================================================
-- Step 5: recommendation_config 算法配置表
-- ============================================================
CREATE TABLE IF NOT EXISTS recommendation_config (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  version      text NOT NULL,
  weights      jsonb NOT NULL,
  description  text,
  is_active    boolean NOT NULL DEFAULT false,
  created_by   uuid REFERENCES users(id),
  created_at   timestamptz NOT NULL DEFAULT now(),
  activated_at timestamptz
);

-- 每次只有一条 is_active = true
CREATE UNIQUE INDEX IF NOT EXISTS idx_rec_config_active
  ON recommendation_config(is_active) WHERE is_active = true;

ALTER TABLE recommendation_config ENABLE ROW LEVEL SECURITY;

-- 仅 admin 可管理
CREATE POLICY "admin_manage_rec_config" ON recommendation_config
  FOR ALL USING (
    EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin')
  );
CREATE POLICY "service_role_full_access_rec_config" ON recommendation_config
  FOR ALL USING (auth.role() = 'service_role');

-- 插入默认配置
INSERT INTO recommendation_config (version, weights, description, is_active, activated_at)
VALUES (
  '1.0.0',
  '{
    "weights": {
      "w_relevance": 0.30,
      "w_distance": 0.20,
      "w_popularity": 0.20,
      "w_quality": 0.15,
      "w_freshness": 0.10,
      "w_time_slot": 0.05
    },
    "sponsor_boost": 100.0,
    "diversity_penalty": -0.30,
    "max_same_merchant": 2,
    "cache_ttl_minutes": 15
  }',
  '默认权重：相关性优先，兼顾距离和热度',
  true,
  now()
);

-- ============================================================
-- Step 6: recommendation_cache 个人推荐缓存表
-- ============================================================
CREATE TABLE IF NOT EXISTS recommendation_cache (
  user_id        uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  deal_ids       uuid[] NOT NULL,
  scores         jsonb,
  computed_at    timestamptz NOT NULL DEFAULT now(),
  config_version text NOT NULL
);

ALTER TABLE recommendation_cache ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users_view_own_cache" ON recommendation_cache
  FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "service_role_full_access_cache" ON recommendation_cache
  FOR ALL USING (auth.role() = 'service_role');

-- ============================================================
-- Step 7: recommendation_global_cache 全局热门缓存表（冷启动用）
-- ============================================================
CREATE TABLE IF NOT EXISTS recommendation_global_cache (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  deal_ids    uuid[] NOT NULL,
  computed_at timestamptz NOT NULL DEFAULT now(),
  time_slot   text NOT NULL DEFAULT 'all'
);

ALTER TABLE recommendation_global_cache ENABLE ROW LEVEL SECURITY;

-- 所有认证用户可读
CREATE POLICY "authenticated_view_global_cache" ON recommendation_global_cache
  FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "service_role_full_access_global_cache" ON recommendation_global_cache
  FOR ALL USING (auth.role() = 'service_role');

-- ============================================================
-- Step 8: 90天事件清理函数
-- ============================================================
CREATE OR REPLACE FUNCTION cleanup_old_events() RETURNS void AS $$
BEGIN
  DELETE FROM user_events WHERE occurred_at < now() - interval '90 days';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- Step 9: pg_cron 定时任务
-- ============================================================

-- 每15分钟计算推荐
SELECT cron.schedule(
  'compute-recommendations',
  '*/15 * * * *',
  $$
  SELECT net.http_post(
    url := 'https://kqyolvmgrdekybjrwizx.supabase.co/functions/v1/compute-recommendations',
    headers := '{"Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtxeW9sdm1ncmRla3lianJ3aXp4Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3MjMxOTY1OSwiZXhwIjoyMDg3ODk1NjU5fQ.tkYSikgL9UenIw_MUhxbh73MSKA0tcTMQNJX08eaGNA"}'::jsonb
  );
  $$
);

-- 每小时更新用户标签
SELECT cron.schedule(
  'update-user-tags',
  '0 * * * *',
  $$
  SELECT net.http_post(
    url := 'https://kqyolvmgrdekybjrwizx.supabase.co/functions/v1/update-user-tags',
    headers := '{"Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtxeW9sdm1ncmRla3lianJ3aXp4Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3MjMxOTY1OSwiZXhwIjoyMDg3ODk1NjU5fQ.tkYSikgL9UenIw_MUhxbh73MSKA0tcTMQNJX08eaGNA"}'::jsonb
  );
  $$
);

-- 每天凌晨3点清理90天前的事件
SELECT cron.schedule(
  'cleanup-old-events',
  '0 3 * * *',
  $$SELECT cleanup_old_events()$$
);
