-- ============================================================
-- search_merchants_nearby — Near Me 模式按 GPS 搜索商家
-- 返回半径内有 active deal 的商家，含聚合数据
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
BEGIN
  RETURN QUERY
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
    COALESCE(AVG(d.rating) FILTER (WHERE d.is_active = true AND d.expires_at > NOW()), 0)::DECIMAL AS avg_rating,
    COALESCE(SUM(d.review_count) FILTER (WHERE d.is_active = true AND d.expires_at > NOW()), 0)::INT AS total_review_count,
    COUNT(d.id) FILTER (WHERE d.is_active = true AND d.expires_at > NOW())::INT AS active_deal_count,
    MIN(d.discount_price) FILTER (WHERE d.is_active = true AND d.expires_at > NOW())::DECIMAL AS best_discount,
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
  HAVING (p_category IS NULL OR COUNT(d.id) FILTER (WHERE d.is_active = true AND d.expires_at > NOW() AND d.category = p_category) > 0)
  ORDER BY distance_meters ASC
  OFFSET p_offset LIMIT p_limit;
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION search_merchants_nearby TO authenticated, anon;
