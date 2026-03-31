-- ============================================================
-- merchant_categories: 商家与全局分类的多对多关联表
-- 一个商家可以属于多个分类（如 BBQ + Korean）
-- ============================================================

-- 1. 创建关联表
CREATE TABLE IF NOT EXISTS public.merchant_categories (
  merchant_id uuid NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  category_id int  NOT NULL REFERENCES public.categories(id) ON DELETE CASCADE,
  created_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (merchant_id, category_id)
);

-- 索引：按分类查商家（用户端首页筛选）
CREATE INDEX IF NOT EXISTS idx_merchant_categories_category
  ON public.merchant_categories(category_id);

-- 索引：按商家查分类（商家端编辑页）
CREATE INDEX IF NOT EXISTS idx_merchant_categories_merchant
  ON public.merchant_categories(merchant_id);

-- 2. RLS 策略
ALTER TABLE public.merchant_categories ENABLE ROW LEVEL SECURITY;

-- 所有人可读（公开数据）
CREATE POLICY "merchant_categories_select"
  ON public.merchant_categories FOR SELECT
  USING (true);

-- 商家 owner 可管理自己的分类
CREATE POLICY "merchant_categories_insert"
  ON public.merchant_categories FOR INSERT
  WITH CHECK (
    merchant_id IN (
      SELECT id FROM public.merchants WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "merchant_categories_delete"
  ON public.merchant_categories FOR DELETE
  USING (
    merchant_id IN (
      SELECT id FROM public.merchants WHERE user_id = auth.uid()
    )
  );

-- service_role 全权限（Edge Function 使用）
CREATE POLICY "merchant_categories_service"
  ON public.merchant_categories FOR ALL
  USING (auth.role() = 'service_role');

-- 3. 更新 search_deals_nearby RPC：通过 merchant_categories 筛选
-- 先删除旧函数再重建
DROP FUNCTION IF EXISTS public.search_deals_nearby(double precision, double precision, double precision, text, int, int);

CREATE OR REPLACE FUNCTION public.search_deals_nearby(
  p_lat double precision,
  p_lng double precision,
  p_radius_m double precision DEFAULT 24140,
  p_category text DEFAULT NULL,
  p_limit int DEFAULT 20,
  p_offset int DEFAULT 0
)
RETURNS TABLE (
  id uuid,
  merchant_id uuid,
  title text,
  description text,
  category text,
  original_price numeric,
  discount_price numeric,
  stock_limit int,
  total_sold int,
  rating numeric,
  review_count int,
  is_active boolean,
  is_featured boolean,
  expires_at timestamptz,
  created_at timestamptz,
  address text,
  image_url text,
  sort_order int,
  deal_type text,
  badge_text text,
  deal_category_id uuid,
  short_name text,
  validity_type text,
  validity_days int,
  applicable_merchant_ids uuid[],
  merchant_name text,
  merchant_logo_url text,
  merchant_phone text,
  merchant_homepage_cover_url text,
  merchant_brand_id uuid,
  brand_name text,
  brand_logo_url text,
  distance_m double precision
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    d.id,
    d.merchant_id,
    d.title,
    d.description,
    d.category,
    d.original_price,
    d.discount_price,
    d.stock_limit,
    d.total_sold,
    d.rating,
    d.review_count,
    d.is_active,
    d.is_featured,
    d.expires_at,
    d.created_at,
    d.address,
    d.image_url,
    d.sort_order,
    d.deal_type,
    d.badge_text,
    d.deal_category_id,
    d.short_name,
    d.validity_type,
    d.validity_days,
    d.applicable_merchant_ids,
    m.name AS merchant_name,
    m.logo_url AS merchant_logo_url,
    m.phone AS merchant_phone,
    m.homepage_cover_url AS merchant_homepage_cover_url,
    m.brand_id AS merchant_brand_id,
    b.name AS brand_name,
    b.logo_url AS brand_logo_url,
    ST_Distance(
      ST_SetSRID(ST_MakePoint(m.lng, m.lat), 4326)::geography,
      ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography
    ) AS distance_m
  FROM public.deals d
  JOIN public.merchants m ON m.id = d.merchant_id
  LEFT JOIN public.brands b ON b.id = m.brand_id
  WHERE d.is_active = true
    AND d.expires_at > now()
    AND m.lat IS NOT NULL
    AND m.lng IS NOT NULL
    AND ST_DWithin(
          ST_SetSRID(ST_MakePoint(m.lng, m.lat), 4326)::geography,
          ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
          p_radius_m
        )
    -- 分类筛选：通过 merchant_categories 关联表
    AND (
      p_category IS NULL
      OR EXISTS (
        SELECT 1 FROM public.merchant_categories mc
        JOIN public.categories c ON c.id = mc.category_id
        WHERE mc.merchant_id = d.merchant_id
          AND c.name = p_category
      )
    )
  ORDER BY d.is_featured DESC, distance_m ASC
  LIMIT p_limit
  OFFSET p_offset;
END;
$$ LANGUAGE plpgsql STABLE;

-- 4. 更新 search_deals_by_city RPC：通过 merchant_categories 筛选
DROP FUNCTION IF EXISTS public.search_deals_by_city(text, double precision, double precision, text, int, int);

CREATE OR REPLACE FUNCTION public.search_deals_by_city(
  p_city text,
  p_user_lat double precision DEFAULT NULL,
  p_user_lng double precision DEFAULT NULL,
  p_category text DEFAULT NULL,
  p_limit int DEFAULT 20,
  p_offset int DEFAULT 0
)
RETURNS TABLE (
  id uuid,
  merchant_id uuid,
  title text,
  description text,
  category text,
  original_price numeric,
  discount_price numeric,
  stock_limit int,
  total_sold int,
  rating numeric,
  review_count int,
  is_active boolean,
  is_featured boolean,
  expires_at timestamptz,
  created_at timestamptz,
  address text,
  image_url text,
  sort_order int,
  deal_type text,
  badge_text text,
  deal_category_id uuid,
  short_name text,
  validity_type text,
  validity_days int,
  applicable_merchant_ids uuid[],
  merchant_name text,
  merchant_logo_url text,
  merchant_phone text,
  merchant_homepage_cover_url text,
  merchant_brand_id uuid,
  brand_name text,
  brand_logo_url text,
  distance_m double precision
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    d.id,
    d.merchant_id,
    d.title,
    d.description,
    d.category,
    d.original_price,
    d.discount_price,
    d.stock_limit,
    d.total_sold,
    d.rating,
    d.review_count,
    d.is_active,
    d.is_featured,
    d.expires_at,
    d.created_at,
    d.address,
    d.image_url,
    d.sort_order,
    d.deal_type,
    d.badge_text,
    d.deal_category_id,
    d.short_name,
    d.validity_type,
    d.validity_days,
    d.applicable_merchant_ids,
    m.name AS merchant_name,
    m.logo_url AS merchant_logo_url,
    m.phone AS merchant_phone,
    m.homepage_cover_url AS merchant_homepage_cover_url,
    m.brand_id AS merchant_brand_id,
    b.name AS brand_name,
    b.logo_url AS brand_logo_url,
    CASE
      WHEN p_user_lat IS NOT NULL AND p_user_lng IS NOT NULL
           AND m.lat IS NOT NULL AND m.lng IS NOT NULL
      THEN ST_Distance(
             ST_SetSRID(ST_MakePoint(m.lng, m.lat), 4326)::geography,
             ST_SetSRID(ST_MakePoint(p_user_lng, p_user_lat), 4326)::geography
           )
      ELSE NULL
    END AS distance_m
  FROM public.deals d
  JOIN public.merchants m ON m.id = d.merchant_id
  LEFT JOIN public.brands b ON b.id = m.brand_id
  WHERE d.is_active = true
    AND d.expires_at > now()
    AND m.city = p_city
    -- 分类筛选：通过 merchant_categories 关联表
    AND (
      p_category IS NULL
      OR EXISTS (
        SELECT 1 FROM public.merchant_categories mc
        JOIN public.categories c ON c.id = mc.category_id
        WHERE mc.merchant_id = d.merchant_id
          AND c.name = p_category
      )
    )
  ORDER BY d.is_featured DESC, d.created_at DESC
  LIMIT p_limit
  OFFSET p_offset;
END;
$$ LANGUAGE plpgsql STABLE;
