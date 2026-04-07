-- ============================================================
-- 开屏广告竞价投放系统
-- 基于 GPS 定位，投放半径内出价最高的商家广告优先展示
-- ============================================================

-- ============================================================
-- Step 1: ad_campaigns 增加 splash 专属字段
-- ============================================================
ALTER TABLE ad_campaigns
  ADD COLUMN IF NOT EXISTS creative_url         text,
  ADD COLUMN IF NOT EXISTS splash_link_type     text
    CHECK (splash_link_type IS NULL OR
           splash_link_type IN ('deal','merchant','external','none')),
  ADD COLUMN IF NOT EXISTS splash_link_value    text,
  ADD COLUMN IF NOT EXISTS splash_radius_meters int NOT NULL DEFAULT 16093;
  -- 默认 10 英里 ≈ 16093 米
  -- 商家可选 8047(5mi) / 16093(10mi) / 24140(15mi) / 40234(25mi)

-- ============================================================
-- Step 2: 扩展 placement CHECK 约束，加入 'splash'
-- ============================================================
ALTER TABLE ad_campaigns DROP CONSTRAINT IF EXISTS ad_campaigns_placement_check;
ALTER TABLE ad_campaigns ADD CONSTRAINT ad_campaigns_placement_check
  CHECK (placement IN (
    'home_banner','home_deal_top','home_store_top',
    'category_store_top','category_deal_top','splash'
  ));

-- ============================================================
-- Step 3: ad_placement_config 新增 is_enabled 字段 + splash 广告位
-- ============================================================
ALTER TABLE ad_placement_config
  ADD COLUMN IF NOT EXISTS is_enabled boolean NOT NULL DEFAULT true;

INSERT INTO ad_placement_config (placement, min_bid, max_slots, billing_type, is_enabled)
VALUES ('splash', 1.00, 3, 'cpc', true)
ON CONFLICT (placement) DO NOTHING;

-- ============================================================
-- Step 4: ad_events 扩展 event_type（新增 skip）
-- ============================================================
ALTER TABLE ad_events DROP CONSTRAINT IF EXISTS ad_events_event_type_check;
ALTER TABLE ad_events ADD CONSTRAINT ad_events_event_type_check
  CHECK (event_type IN ('impression','click','conversion','skip'));

-- ============================================================
-- Step 5: user_events 扩展 event_type（新增 app_open）
-- ============================================================
ALTER TABLE user_events DROP CONSTRAINT IF EXISTS user_events_event_type_check;
ALTER TABLE user_events ADD CONSTRAINT user_events_event_type_check
  CHECK (event_type IN (
    'view_deal','view_merchant','search',
    'purchase','redeem','review','refund','app_open'
  ));

-- ============================================================
-- Step 6: 创建独立 Haversine 距离函数（返回米）
-- 供 get_splash_ads / get_splash_ad_estimate 等复用
-- ============================================================
CREATE OR REPLACE FUNCTION haversine(
  lat1 float8, lng1 float8,
  lat2 float8, lng2 float8
) RETURNS float8
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT 6371000.0 * acos(
    LEAST(1.0, GREATEST(-1.0,
      cos(radians(lat1)) * cos(radians(lat2))
      * cos(radians(lng2) - radians(lng1))
      + sin(radians(lat1)) * sin(radians(lat2))
    ))
  );
$$;

-- ============================================================
-- Step 7: RPC get_splash_ads(p_lat, p_lng)
-- 根据用户 GPS 位置，返回投放半径内出价最高的竞价广告
-- V1 纯出价排名（不用质量分），同价时半径小的优先
-- ============================================================
CREATE OR REPLACE FUNCTION get_splash_ads(
  p_lat float8,
  p_lng float8
)
RETURNS TABLE (
  campaign_id       uuid,
  merchant_id       uuid,
  creative_url      text,
  splash_link_type  text,
  splash_link_value text,
  merchant_name     text,
  merchant_logo_url text,
  bid_price         numeric
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_max_slots    int;
  v_is_enabled   boolean;
  v_current_hour int;
  v_min_bid      numeric;
BEGIN
  -- 读取广告位配置
  SELECT apc.max_slots, apc.is_enabled, apc.min_bid
  INTO v_max_slots, v_is_enabled, v_min_bid
  FROM ad_placement_config apc
  WHERE apc.placement = 'splash';

  -- Admin 关闭时返回空
  IF v_is_enabled IS NOT TRUE THEN
    RETURN;
  END IF;

  IF v_max_slots IS NULL THEN
    v_max_slots := 3;
  END IF;

  -- Dallas 时区当前小时
  v_current_hour := EXTRACT(HOUR FROM now() AT TIME ZONE 'America/Chicago')::int;

  RETURN QUERY
  SELECT
    ac.id            AS campaign_id,
    ac.merchant_id   AS merchant_id,
    ac.creative_url  AS creative_url,
    ac.splash_link_type  AS splash_link_type,
    ac.splash_link_value AS splash_link_value,
    m.name           AS merchant_name,
    m.logo_url       AS merchant_logo_url,
    ac.bid_price     AS bid_price
  FROM ad_campaigns ac
  JOIN ad_accounts aa   ON aa.merchant_id = ac.merchant_id
  JOIN merchants m      ON m.id = ac.merchant_id
  WHERE
    ac.placement = 'splash'
    AND ac.status = 'active'
    AND ac.creative_url IS NOT NULL
    AND ac.creative_url != ''
    AND aa.balance > 0
    AND ac.today_spend < ac.daily_budget
    AND ac.start_at <= now()
    AND (ac.end_at IS NULL OR ac.end_at > now())
    AND (ac.schedule_hours IS NULL
         OR v_current_hour = ANY(ac.schedule_hours))
    AND ac.bid_price >= COALESCE(v_min_bid, 0)
    -- NULL 坐标商家过滤
    AND m.lat IS NOT NULL
    AND m.lng IS NOT NULL
    -- 各 campaign 自身的投放半径
    AND haversine(p_lat, p_lng,
                  m.lat::float8, m.lng::float8) <= ac.splash_radius_meters
  ORDER BY
    ac.bid_price DESC,
    ac.splash_radius_meters ASC
  LIMIT v_max_slots;
END;
$$;

-- 用户端可能未登录（匿名），需要 anon + authenticated 都可调用
GRANT EXECUTE ON FUNCTION get_splash_ads(float8, float8) TO anon, authenticated;

-- ============================================================
-- Step 8: RPC get_splash_ad_estimate(p_lat, p_lng, p_radius_meters)
-- 预估日均触达人数（商家端展示，仅 authenticated 可调）
-- ============================================================
CREATE OR REPLACE FUNCTION get_splash_ad_estimate(
  p_lat           float8,
  p_lng           float8,
  p_radius_meters int
)
RETURNS int
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count int;
BEGIN
  -- 近 30 天该半径内有 app_open 事件的去重用户数 / 30
  -- P3: 用 ::numeric / 30.0 避免整数除法
  SELECT (COUNT(DISTINCT ue.user_id)::numeric / 30.0)::int
  INTO v_count
  FROM user_events ue
  WHERE
    ue.event_type = 'app_open'
    AND ue.occurred_at >= now() - interval '30 days'
    AND (ue.metadata->>'lat') IS NOT NULL
    AND haversine(
          p_lat, p_lng,
          (ue.metadata->>'lat')::float8,
          (ue.metadata->>'lng')::float8
        ) <= p_radius_meters;

  -- 数据不足时返回保守估算下限
  RETURN GREATEST(v_count, CASE
    WHEN p_radius_meters <= 8047  THEN 30   -- 5mi
    WHEN p_radius_meters <= 16093 THEN 80   -- 10mi
    WHEN p_radius_meters <= 24140 THEN 150  -- 15mi
    ELSE 300                                -- 25mi
  END);
END;
$$;

-- P4: 仅 authenticated 可调用，避免匿名用户滥用探测
GRANT EXECUTE ON FUNCTION get_splash_ad_estimate(float8, float8, int) TO authenticated;

-- ============================================================
-- Step 9: splash campaign 专用索引（可选，早期量小可跳过）
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_ad_campaigns_splash_active
  ON ad_campaigns(placement, bid_price DESC)
  WHERE placement = 'splash' AND status = 'active';
