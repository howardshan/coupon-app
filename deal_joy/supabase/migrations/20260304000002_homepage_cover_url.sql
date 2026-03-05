-- ============================================================
-- 商家首页封面图字段
-- 用于客户端首页 deal 卡片 fallback 显示
-- ============================================================

ALTER TABLE public.merchants ADD COLUMN IF NOT EXISTS homepage_cover_url TEXT;

-- 必须先 DROP 旧函数，因为返回类型变了（新增 merchant_homepage_cover_url 列）
DROP FUNCTION IF EXISTS search_deals_nearby(DECIMAL, DECIMAL, DECIMAL, TEXT, INT, INT);
DROP FUNCTION IF EXISTS search_deals_by_city(TEXT, DECIMAL, DECIMAL, TEXT, INT, INT);

-- ============================================================
-- 更新 search_deals_nearby 返回 homepage_cover_url
-- ============================================================
CREATE OR REPLACE FUNCTION search_deals_nearby(
  p_lat      DECIMAL,
  p_lng      DECIMAL,
  p_radius_m DECIMAL DEFAULT 24140,
  p_category TEXT    DEFAULT NULL,
  p_limit    INT     DEFAULT 20,
  p_offset   INT     DEFAULT 0
)
RETURNS TABLE(
  id               UUID,
  merchant_id      UUID,
  title            TEXT,
  description      TEXT,
  category         TEXT,
  original_price   DECIMAL,
  discount_price   DECIMAL,
  discount_percent INT,
  discount_label   TEXT,
  image_urls       TEXT[],
  is_featured      BOOL,
  rating           DECIMAL,
  review_count     INT,
  total_sold       INT,
  expires_at       TIMESTAMPTZ,
  merchant_name    TEXT,
  merchant_logo_url TEXT,
  merchant_city    TEXT,
  merchant_homepage_cover_url TEXT,
  distance_meters  DECIMAL
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    d.id,
    d.merchant_id,
    d.title,
    d.description,
    d.category,
    d.original_price::DECIMAL,
    d.discount_price::DECIMAL,
    d.discount_percent,
    COALESCE(d.discount_label, ''),
    d.image_urls,
    d.is_featured,
    COALESCE(d.rating, 0)::DECIMAL,
    COALESCE(d.review_count, 0),
    COALESCE(d.total_sold, 0),
    d.expires_at,
    m.name,
    m.logo_url,
    m.city,
    m.homepage_cover_url,
    (3958.8 * 2 * ASIN(SQRT(
      POWER(SIN(RADIANS((m.lat - p_lat) / 2)), 2) +
      COS(RADIANS(p_lat)) * COS(RADIANS(m.lat)) *
      POWER(SIN(RADIANS((m.lng - p_lng) / 2)), 2)
    )) * 1609.34)::DECIMAL AS distance_meters
  FROM deals d
  JOIN merchants m ON d.merchant_id = m.id
  WHERE d.is_active = true
    AND d.expires_at > NOW()
    AND m.lat IS NOT NULL
    AND m.lng IS NOT NULL
    AND (p_category IS NULL OR d.category = p_category)
    AND (3958.8 * 2 * ASIN(SQRT(
      POWER(SIN(RADIANS((m.lat - p_lat) / 2)), 2) +
      COS(RADIANS(p_lat)) * COS(RADIANS(m.lat)) *
      POWER(SIN(RADIANS((m.lng - p_lng) / 2)), 2)
    )) * 1609.34) <= p_radius_m
  ORDER BY distance_meters ASC
  OFFSET p_offset LIMIT p_limit;
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION search_deals_nearby TO authenticated, anon;

-- ============================================================
-- 更新 search_deals_by_city 返回 homepage_cover_url
-- ============================================================
CREATE OR REPLACE FUNCTION search_deals_by_city(
  p_city     TEXT,
  p_user_lat DECIMAL DEFAULT NULL,
  p_user_lng DECIMAL DEFAULT NULL,
  p_category TEXT    DEFAULT NULL,
  p_limit    INT     DEFAULT 20,
  p_offset   INT     DEFAULT 0
)
RETURNS TABLE(
  id               UUID,
  merchant_id      UUID,
  title            TEXT,
  description      TEXT,
  category         TEXT,
  original_price   DECIMAL,
  discount_price   DECIMAL,
  discount_percent INT,
  discount_label   TEXT,
  image_urls       TEXT[],
  is_featured      BOOL,
  rating           DECIMAL,
  review_count     INT,
  total_sold       INT,
  expires_at       TIMESTAMPTZ,
  merchant_name    TEXT,
  merchant_logo_url TEXT,
  merchant_city    TEXT,
  merchant_homepage_cover_url TEXT,
  distance_meters  DECIMAL
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    d.id,
    d.merchant_id,
    d.title,
    d.description,
    d.category,
    d.original_price::DECIMAL,
    d.discount_price::DECIMAL,
    d.discount_percent,
    COALESCE(d.discount_label, ''),
    d.image_urls,
    d.is_featured,
    COALESCE(d.rating, 0)::DECIMAL,
    COALESCE(d.review_count, 0),
    COALESCE(d.total_sold, 0),
    d.expires_at,
    m.name,
    m.logo_url,
    m.city,
    m.homepage_cover_url,
    CASE
      WHEN p_user_lat IS NOT NULL AND m.lat IS NOT NULL THEN
        (3958.8 * 2 * ASIN(SQRT(
          POWER(SIN(RADIANS((m.lat - p_user_lat) / 2)), 2) +
          COS(RADIANS(p_user_lat)) * COS(RADIANS(m.lat)) *
          POWER(SIN(RADIANS((m.lng - p_user_lng) / 2)), 2)
        )) * 1609.34)::DECIMAL
      ELSE NULL
    END AS distance_meters
  FROM deals d
  JOIN merchants m ON d.merchant_id = m.id
  WHERE d.is_active = true
    AND d.expires_at > NOW()
    AND m.city = p_city
    AND (p_category IS NULL OR d.category = p_category)
  ORDER BY d.is_featured DESC, COALESCE(d.rating, 0) DESC, d.created_at DESC
  OFFSET p_offset LIMIT p_limit;
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION search_deals_by_city TO authenticated, anon;
