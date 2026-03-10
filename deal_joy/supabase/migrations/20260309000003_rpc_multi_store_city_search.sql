-- ============================================================
-- 修复多店 deal 搜索：applicable_merchant_ids 里的门店也应该被搜到
-- search_deals_by_city: 如果 deal 适用门店中有该城市的门店，也返回
-- search_deals_nearby: 如果 deal 适用门店中有在搜索半径内的门店，也返回
-- 返回类型不变，可以 CREATE OR REPLACE
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
  distance_meters  DECIMAL,
  applicable_merchant_ids UUID[],
  merchant_brand_name TEXT,
  deal_type        TEXT,
  deal_category_id UUID,
  badge_text       TEXT,
  sort_order       INT
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
    END AS distance_meters,
    d.applicable_merchant_ids,
    b.name AS merchant_brand_name,
    COALESCE(d.deal_type, 'regular'),
    d.deal_category_id,
    d.badge_text,
    d.sort_order
  FROM deals d
  JOIN merchants m ON d.merchant_id = m.id
  LEFT JOIN brands b ON m.brand_id = b.id
  WHERE d.is_active = true
    AND d.expires_at > NOW()
    AND (p_category IS NULL OR d.category = p_category)
    AND (
      -- 原逻辑：创建门店在目标城市
      m.city = p_city
      OR
      -- 新增：applicable_merchant_ids 中有门店在目标城市
      (
        d.applicable_merchant_ids IS NOT NULL
        AND EXISTS (
          SELECT 1 FROM merchants am
          WHERE am.id = ANY(d.applicable_merchant_ids)
            AND am.city = p_city
        )
      )
    )
  ORDER BY d.is_featured DESC, COALESCE(d.rating, 0) DESC, d.created_at DESC
  OFFSET p_offset LIMIT p_limit;
END;
$$ LANGUAGE plpgsql;


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
  distance_meters  DECIMAL,
  applicable_merchant_ids UUID[],
  merchant_brand_name TEXT,
  deal_type        TEXT,
  deal_category_id UUID,
  badge_text       TEXT,
  sort_order       INT
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
    )) * 1609.34)::DECIMAL AS distance_meters,
    d.applicable_merchant_ids,
    b.name AS merchant_brand_name,
    COALESCE(d.deal_type, 'regular'),
    d.deal_category_id,
    d.badge_text,
    d.sort_order
  FROM deals d
  JOIN merchants m ON d.merchant_id = m.id
  LEFT JOIN brands b ON m.brand_id = b.id
  WHERE d.is_active = true
    AND d.expires_at > NOW()
    AND m.lat IS NOT NULL
    AND m.lng IS NOT NULL
    AND (p_category IS NULL OR d.category = p_category)
    AND (
      -- 原逻辑：创建门店在搜索半径内
      (3958.8 * 2 * ASIN(SQRT(
        POWER(SIN(RADIANS((m.lat - p_lat) / 2)), 2) +
        COS(RADIANS(p_lat)) * COS(RADIANS(m.lat)) *
        POWER(SIN(RADIANS((m.lng - p_lng) / 2)), 2)
      )) * 1609.34) <= p_radius_m
      OR
      -- 新增：applicable_merchant_ids 中有门店在搜索半径内
      (
        d.applicable_merchant_ids IS NOT NULL
        AND EXISTS (
          SELECT 1 FROM merchants am
          WHERE am.id = ANY(d.applicable_merchant_ids)
            AND am.lat IS NOT NULL
            AND am.lng IS NOT NULL
            AND (3958.8 * 2 * ASIN(SQRT(
              POWER(SIN(RADIANS((am.lat - p_lat) / 2)), 2) +
              COS(RADIANS(p_lat)) * COS(RADIANS(am.lat)) *
              POWER(SIN(RADIANS((am.lng - p_lng) / 2)), 2)
            )) * 1609.34) <= p_radius_m
        )
      )
    )
  ORDER BY distance_meters ASC
  OFFSET p_offset LIMIT p_limit;
END;
$$ LANGUAGE plpgsql;
