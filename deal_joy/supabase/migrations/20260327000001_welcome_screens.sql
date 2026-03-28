-- ============================================================
-- 欢迎页面系统：Splash + Onboarding + Homepage Banner
-- ============================================================

-- Step 1: splash_configs 表（开屏广告轮播）
CREATE TABLE IF NOT EXISTS splash_configs (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  is_active        boolean NOT NULL DEFAULT false,
  duration_seconds int NOT NULL DEFAULT 5
                     CHECK (duration_seconds BETWEEN 3 AND 10),
  slides           jsonb NOT NULL DEFAULT '[]',
  created_by       uuid REFERENCES users(id),
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);

-- 每次只有一条 is_active = true
CREATE UNIQUE INDEX IF NOT EXISTS idx_splash_configs_active
  ON splash_configs(is_active) WHERE is_active = true;

CREATE TRIGGER set_splash_configs_updated_at
  BEFORE UPDATE ON splash_configs
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

ALTER TABLE splash_configs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "public_read_splash" ON splash_configs
  FOR SELECT USING (is_active = true);

-- 插入默认空配置（无图片时 Splash 自动跳过）
INSERT INTO splash_configs (is_active, duration_seconds, slides)
VALUES (true, 5, '[]');

-- Step 2: onboarding_configs 表（首次安装引导页）
CREATE TABLE IF NOT EXISTS onboarding_configs (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  is_active  boolean NOT NULL DEFAULT false,
  slides     jsonb NOT NULL DEFAULT '[]',
  created_by uuid REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_onboarding_configs_active
  ON onboarding_configs(is_active) WHERE is_active = true;

CREATE TRIGGER set_onboarding_configs_updated_at
  BEFORE UPDATE ON onboarding_configs
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

ALTER TABLE onboarding_configs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "public_read_onboarding" ON onboarding_configs
  FOR SELECT USING (is_active = true);

-- 插入默认 Onboarding（三页）
INSERT INTO onboarding_configs (is_active, slides) VALUES (
  true,
  '[
    {
      "id": "ob1",
      "image_url": "",
      "title": "Discover Local Deals",
      "subtitle": "Save up to 60% at restaurants and shops near you",
      "sort_order": 0
    },
    {
      "id": "ob2",
      "image_url": "",
      "title": "Buy Anytime, Refund Anytime",
      "subtitle": "No risk. Get a full refund before your coupon expires",
      "sort_order": 1
    },
    {
      "id": "ob3",
      "image_url": "",
      "title": "Share with Friends",
      "subtitle": "Gift coupons or share great deals with your friends",
      "sort_order": 2
    }
  ]'
);

-- Step 3: banner_configs 表（首页 Banner 轮播）
CREATE TABLE IF NOT EXISTS banner_configs (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  is_active         boolean NOT NULL DEFAULT false,
  auto_play_seconds int NOT NULL DEFAULT 3
                      CHECK (auto_play_seconds BETWEEN 2 AND 10),
  slides            jsonb NOT NULL DEFAULT '[]',
  created_by        uuid REFERENCES users(id),
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_banner_configs_active
  ON banner_configs(is_active) WHERE is_active = true;

CREATE TRIGGER set_banner_configs_updated_at
  BEFORE UPDATE ON banner_configs
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

ALTER TABLE banner_configs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "public_read_banner" ON banner_configs
  FOR SELECT USING (is_active = true);

-- 插入默认空 Banner 配置
INSERT INTO banner_configs (is_active, auto_play_seconds, slides)
VALUES (true, 3, '[]');
