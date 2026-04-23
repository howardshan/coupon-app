-- ============================================================
-- search_ranking_config — Near Me 商家排序多因子权重配置
-- 管理员在 Admin > Settings > Search Ranking 修改
--
-- 存储原始权重（不要求归一化），RPC 内部自动归一化。
-- 5 个因子：
--   distance — 距离（越近越好）
--   rating   — 用户评分（越高越好）
--   clicks   — 点击量（越多越好）
--   orders   — 下单量（越多越好）
--   refund   — 退款率（越低越好，负向信号）
-- ============================================================

CREATE TABLE IF NOT EXISTS search_ranking_config (
  id              INT PRIMARY KEY DEFAULT 1,
  -- 原始权重（0~100，不要求归一化，RPC 内部做归一化）
  distance_weight DECIMAL(6, 2) NOT NULL DEFAULT 60,
  rating_weight   DECIMAL(6, 2) NOT NULL DEFAULT 40,
  click_weight    DECIMAL(6, 2) NOT NULL DEFAULT 20,
  order_weight    DECIMAL(6, 2) NOT NULL DEFAULT 10,
  refund_weight   DECIMAL(6, 2) NOT NULL DEFAULT 20,
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT single_row CHECK (id = 1),
  CONSTRAINT weights_non_negative CHECK (
    distance_weight >= 0 AND rating_weight >= 0 AND
    click_weight >= 0 AND order_weight >= 0 AND refund_weight >= 0
  )
);

INSERT INTO search_ranking_config (id, distance_weight, rating_weight, click_weight, order_weight, refund_weight)
VALUES (1, 60, 40, 20, 10, 20)
ON CONFLICT (id) DO NOTHING;

ALTER TABLE search_ranking_config ENABLE ROW LEVEL SECURITY;

CREATE POLICY "anyone can read ranking config"
  ON search_ranking_config FOR SELECT USING (true);

CREATE POLICY "service role can update ranking config"
  ON search_ranking_config FOR UPDATE USING (auth.role() = 'service_role');

-- ============================================================
-- 重建 search_merchants_nearby — 5 因子加权排序
--
-- 各因子归一化方式（结果均为 0~1）：
--   distance_score = 1 - (distance_meters / p_radius_m)
--                    → 0 = 在边界，1 = 在中心
--   rating_score   = avg_rating / 5.0
--   click_score    = views / (views + 200)       软上限，平滑归一化
--   order_score    = total_sold / (total_sold + 50)   软上限
--   refund_score   = 1 - refund_rate             退款率越低分越高
--
-- 最终得分 = Σ(归一化权重_i × score_i)，降序排列
-- ============================================================

DROP FUNCTION IF EXISTS search_merchants_nearby(DECIMAL, DECIMAL, DECIMAL, TEXT, INT, INT);

CREATE OR REPLACE FUNCTION search_merchants_nearby(
  p_lat      DECIMAL,
  p_lng      DECIMAL,
  p_radius_m DECIMAL DEFAULT 32187,
  p_category TEXT    DEFAULT NULL,
  p_limit    INT     DEFAULT 30,
  p_offset   INT     DEFAULT 0
)
RETURNS TABLE(
  id                  UUID,
  name                TEXT,
  description         TEXT,
  logo_url            TEXT,
  homepage_cover_url  TEXT,
  address             TEXT,
  phone               TEXT,
  lat                 DECIMAL,
  lng                 DECIMAL,
  avg_rating          DECIMAL,
  total_review_count  INT,
  active_deal_count   INT,
  best_discount       DECIMAL,
  distance_meters     DECIMAL
) AS $$
DECLARE
  v_distance_weight DECIMAL;
  v_rating_weight   DECIMAL;
  v_click_weight    DECIMAL;
  v_order_weight    DECIMAL;
  v_refund_weight   DECIMAL;
  v_total_weight    DECIMAL;
BEGIN
  -- 读取原始权重并归一化
  SELECT
    COALESCE(src.distance_weight, 60),
    COALESCE(src.rating_weight,   40),
    COALESCE(src.click_weight,    20),
    COALESCE(src.order_weight,    10),
    COALESCE(src.refund_weight,   20)
  INTO v_distance_weight, v_rating_weight, v_click_weight, v_order_weight, v_refund_weight
  FROM search_ranking_config src
  LIMIT 1;

  v_total_weight := GREATEST(
    v_distance_weight + v_rating_weight + v_click_weight + v_order_weight + v_refund_weight,
    0.001  -- 防止除零
  );

  -- 归一化
  v_distance_weight := v_distance_weight / v_total_weight;
  v_rating_weight   := v_rating_weight   / v_total_weight;
  v_click_weight    := v_click_weight    / v_total_weight;
  v_order_weight    := v_order_weight    / v_total_weight;
  v_refund_weight   := v_refund_weight   / v_total_weight;

  RETURN QUERY
  WITH radius_filter AS (
    -- 第一步：筛选半径内有 active deal 的商家，avg_rating 从 reviews 聚合（不随 deal 过期消失）
    SELECT
      m.id,
      m.name::TEXT,
      m.description::TEXT,
      m.logo_url::TEXT,
      m.homepage_cover_url::TEXT,
      m.address::TEXT,
      m.phone::TEXT,
      m.lat::DECIMAL,
      m.lng::DECIMAL,
      COUNT(d.id) FILTER (WHERE d.is_active = true AND d.expires_at > NOW())::INT           AS active_deal_count,
      MIN(d.discount_price) FILTER (WHERE d.is_active = true AND d.expires_at > NOW())::DECIMAL AS best_discount,
      COALESCE(SUM(d.total_sold) FILTER (WHERE d.is_active = true), 0)::INT                 AS total_sold_sum,
      (3958.8 * 2 * ASIN(SQRT(
        POWER(SIN(RADIANS((m.lat - p_lat) / 2)), 2) +
        COS(RADIANS(p_lat)) * COS(RADIANS(m.lat)) *
        POWER(SIN(RADIANS((m.lng - p_lng) / 2)), 2)
      )) * 1609.34)::DECIMAL AS distance_meters
    FROM merchants m
    LEFT JOIN deals d ON d.merchant_id = m.id
    WHERE m.status = 'approved'
      AND m.lat IS NOT NULL
      AND m.lng IS NOT NULL
      AND (p_category IS NULL OR d.category = p_category)
      AND (3958.8 * 2 * ASIN(SQRT(
        POWER(SIN(RADIANS((m.lat - p_lat) / 2)), 2) +
        COS(RADIANS(p_lat)) * COS(RADIANS(m.lat)) *
        POWER(SIN(RADIANS((m.lng - p_lng) / 2)), 2)
      )) * 1609.34) <= p_radius_m
    GROUP BY m.id, m.name, m.description, m.logo_url, m.homepage_cover_url,
             m.address, m.phone, m.lat, m.lng
    HAVING (p_category IS NULL OR
            COUNT(d.id) FILTER (WHERE d.is_active = true AND d.expires_at > NOW() AND d.category = p_category) > 0)
  ),
  review_agg AS (
    -- 从 reviews 表直接聚合评分（覆盖所有 deal，含已过期）
    SELECT
      r.merchant_id,
      COALESCE(AVG(r.rating), 0)::DECIMAL AS avg_rating,
      COUNT(*)::INT                        AS total_review_count
    FROM reviews r
    WHERE r.merchant_id IN (SELECT rf.id FROM radius_filter rf)
    GROUP BY r.merchant_id
  ),
  view_agg AS (
    -- 各商家总点击量
    SELECT dv.merchant_id, COUNT(*)::INT AS total_views
    FROM deal_views dv
    WHERE dv.merchant_id IN (SELECT rf.id FROM radius_filter rf)
    GROUP BY dv.merchant_id
  ),
  refund_agg AS (
    -- 各商家退款率 = 已退款 order_item / 总 order_item
    SELECT
      oi.purchased_merchant_id                                                   AS merchant_id,
      COUNT(*)                                                                   AS total_items,
      COUNT(*) FILTER (WHERE oi.customer_status = 'refund_success')             AS refunded_items
    FROM order_items oi
    WHERE oi.purchased_merchant_id IN (SELECT rf.id FROM radius_filter rf)
    GROUP BY oi.purchased_merchant_id
  ),
  scored AS (
    SELECT
      rf.*,
      COALESCE(rev.avg_rating, 0)::DECIMAL                                       AS avg_rating,
      COALESCE(rev.total_review_count, 0)::INT                                   AS total_review_count,
      COALESCE(va.total_views, 0)                                                AS click_count,
      -- 各因子归一化得分（0~1）
      (1.0 - rf.distance_meters / NULLIF(p_radius_m, 0))                        AS distance_score,
      (COALESCE(rev.avg_rating, 0) / 5.0)                                        AS rating_score,
      (COALESCE(va.total_views, 0)::DECIMAL / (COALESCE(va.total_views, 0) + 200.0)) AS click_score,
      (rf.total_sold_sum::DECIMAL / (rf.total_sold_sum + 50.0))                  AS order_score,
      (1.0 - COALESCE(ref.refunded_items::DECIMAL / NULLIF(ref.total_items, 0), 0)) AS refund_score
    FROM radius_filter rf
    LEFT JOIN review_agg  rev ON rev.merchant_id = rf.id
    LEFT JOIN view_agg    va  ON va.merchant_id  = rf.id
    LEFT JOIN refund_agg  ref ON ref.merchant_id = rf.id
  )
  SELECT
    s.id, s.name, s.description, s.logo_url, s.homepage_cover_url,
    s.address, s.phone, s.lat, s.lng,
    s.avg_rating, s.total_review_count, s.active_deal_count,
    s.best_discount, s.distance_meters
  FROM scored s
  ORDER BY (
    v_distance_weight * s.distance_score +
    v_rating_weight   * s.rating_score   +
    v_click_weight    * s.click_score    +
    v_order_weight    * s.order_score    +
    v_refund_weight   * s.refund_score
  ) DESC
  OFFSET p_offset LIMIT p_limit;
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION search_merchants_nearby TO authenticated, anon;
