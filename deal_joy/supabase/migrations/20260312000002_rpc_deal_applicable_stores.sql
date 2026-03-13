-- ============================================================
-- 更新 RPC 搜索函数：从查 applicable_merchant_ids 数组改为查 deal_applicable_stores 表
-- 返回类型有变更（applicable_merchant_ids → active_store_count），必须 DROP 重建
-- ============================================================

-- 先 DROP 旧版本（需完整参数签名）
DROP FUNCTION IF EXISTS search_deals_by_city(TEXT, DECIMAL, DECIMAL, TEXT, INT, INT);
DROP FUNCTION IF EXISTS search_deals_nearby(DECIMAL, DECIMAL, DECIMAL, TEXT, INT, INT);

-- ============================================================
-- search_deals_by_city：城市搜索
-- 改动：WHERE 条件查 deal_applicable_stores active 门店，新增 active_store_count
-- ============================================================
CREATE FUNCTION search_deals_by_city(
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
  active_store_count INT,
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
    -- 用户距离（基于 Deal 创建门店坐标）
    CASE
      WHEN p_user_lat IS NOT NULL AND m.lat IS NOT NULL THEN
        (3958.8 * 2 * ASIN(SQRT(
          POWER(SIN(RADIANS((m.lat - p_user_lat) / 2)), 2) +
          COS(RADIANS(p_user_lat)) * COS(RADIANS(m.lat)) *
          POWER(SIN(RADIANS((m.lng - p_user_lng) / 2)), 2)
        )) * 1609.34)::DECIMAL
      ELSE NULL
    END AS distance_meters,
    -- active 门店数量（用户端 "Available at X locations"）
    (
      SELECT COUNT(*)::INT
      FROM public.deal_applicable_stores das
      WHERE das.deal_id = d.id
        AND das.status = 'active'
    ) AS active_store_count,
    b.name AS merchant_brand_name,
    COALESCE(d.deal_type, 'regular'),
    d.deal_category_id,
    d.badge_text,
    d.sort_order
  FROM public.deals d
  JOIN public.merchants m ON d.merchant_id = m.id
  LEFT JOIN public.brands b ON m.brand_id = b.id
  WHERE d.is_active = true
    AND d.expires_at > NOW()
    AND (p_category IS NULL OR d.category = p_category)
    -- 只返回在目标城市有 active 门店的 Deal
    AND EXISTS (
      SELECT 1
      FROM public.deal_applicable_stores das
      JOIN public.merchants sm ON sm.id = das.store_id
      WHERE das.deal_id = d.id
        AND das.status = 'active'
        AND sm.city = p_city
    )
  ORDER BY d.is_featured DESC, COALESCE(d.rating, 0) DESC, d.created_at DESC
  OFFSET p_offset LIMIT p_limit;
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION search_deals_by_city(TEXT, DECIMAL, DECIMAL, TEXT, INT, INT)
  TO authenticated, anon;


-- ============================================================
-- search_deals_nearby：GPS 附近搜索
-- 改动：WHERE 条件查 deal_applicable_stores active 门店，新增 active_store_count
-- ============================================================
CREATE FUNCTION search_deals_nearby(
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
  active_store_count INT,
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
    -- 到 Deal 创建门店的距离
    (3958.8 * 2 * ASIN(SQRT(
      POWER(SIN(RADIANS((m.lat - p_lat) / 2)), 2) +
      COS(RADIANS(p_lat)) * COS(RADIANS(m.lat)) *
      POWER(SIN(RADIANS((m.lng - p_lng) / 2)), 2)
    )) * 1609.34)::DECIMAL AS distance_meters,
    -- active 门店数量
    (
      SELECT COUNT(*)::INT
      FROM public.deal_applicable_stores das
      WHERE das.deal_id = d.id
        AND das.status = 'active'
    ) AS active_store_count,
    b.name AS merchant_brand_name,
    COALESCE(d.deal_type, 'regular'),
    d.deal_category_id,
    d.badge_text,
    d.sort_order
  FROM public.deals d
  JOIN public.merchants m ON d.merchant_id = m.id
  LEFT JOIN public.brands b ON m.brand_id = b.id
  WHERE d.is_active = true
    AND d.expires_at > NOW()
    AND m.lat IS NOT NULL
    AND m.lng IS NOT NULL
    AND (p_category IS NULL OR d.category = p_category)
    -- 只返回在搜索半径内有 active 门店的 Deal
    AND EXISTS (
      SELECT 1
      FROM public.deal_applicable_stores das
      JOIN public.merchants sm ON sm.id = das.store_id
      WHERE das.deal_id = d.id
        AND das.status = 'active'
        AND sm.lat IS NOT NULL
        AND sm.lng IS NOT NULL
        AND (3958.8 * 2 * ASIN(SQRT(
          POWER(SIN(RADIANS((sm.lat - p_lat) / 2)), 2) +
          COS(RADIANS(p_lat)) * COS(RADIANS(sm.lat)) *
          POWER(SIN(RADIANS((sm.lng - p_lng) / 2)), 2)
        )) * 1609.34) <= p_radius_m
    )
  ORDER BY distance_meters ASC
  OFFSET p_offset LIMIT p_limit;
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION search_deals_nearby(DECIMAL, DECIMAL, DECIMAL, TEXT, INT, INT)
  TO authenticated, anon;
