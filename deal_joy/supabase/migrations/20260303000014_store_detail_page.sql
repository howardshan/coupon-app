-- =============================================================
-- DealJoy 商家详情页（用户端）Migration
-- 新增字段、新表、数据库函数、种子数据
-- =============================================================

-- -------------------------------------------------------------
-- 1. merchants 表新增字段
-- -------------------------------------------------------------
ALTER TABLE public.merchants
  ADD COLUMN IF NOT EXISTS price_per_person  numeric(6,2),
  ADD COLUMN IF NOT EXISTS established_year  int,
  ADD COLUMN IF NOT EXISTS parking_info      text,
  ADD COLUMN IF NOT EXISTS wifi              boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS reservation_url   text;

-- -------------------------------------------------------------
-- 2. merchant_photos 表新增 category 字段（细分环境照片类型）
-- -------------------------------------------------------------
ALTER TABLE public.merchant_photos
  ADD COLUMN IF NOT EXISTS category text;

CREATE INDEX IF NOT EXISTS idx_merchant_photos_category
  ON public.merchant_photos(merchant_id, category);

-- -------------------------------------------------------------
-- 3. 新建 menu_items 表（菜品/菜单）
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.menu_items (
  id                   uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id          uuid        NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  name                 text        NOT NULL,
  image_url            text,
  price                numeric(8,2),
  -- category 取值: 'signature' | 'popular' | 'regular'
  category             text        NOT NULL DEFAULT 'regular',
  recommendation_count int         NOT NULL DEFAULT 0,
  is_signature         boolean     NOT NULL DEFAULT false,
  sort_order           int         NOT NULL DEFAULT 0,
  created_at           timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_menu_items_merchant
  ON public.menu_items(merchant_id);
CREATE INDEX IF NOT EXISTS idx_menu_items_category
  ON public.menu_items(merchant_id, category);

ALTER TABLE public.menu_items ENABLE ROW LEVEL SECURITY;

-- 用户端：已审批商家的菜品公开可读
CREATE POLICY "menu_items_read_approved" ON public.menu_items
  FOR SELECT USING (
    merchant_id IN (SELECT id FROM public.merchants WHERE status = 'approved')
  );

-- 商家端：管理自己的菜品
CREATE POLICY "menu_items_manage_own" ON public.menu_items
  FOR ALL USING (
    merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid())
  );

-- -------------------------------------------------------------
-- 4. 新建 store_facilities 表（设施信息）
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.store_facilities (
  id             uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id    uuid        NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  -- facility_type 取值: 'private_room' | 'parking' | 'wifi' | 'baby_chair' | 'reservation' | 'large_table' | 'no_smoking' | 'other'
  facility_type  text        NOT NULL,
  name           text        NOT NULL,
  description    text,
  image_url      text,
  capacity       int,
  is_free        boolean     NOT NULL DEFAULT true,
  sort_order     int         NOT NULL DEFAULT 0,
  created_at     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_store_facilities_merchant
  ON public.store_facilities(merchant_id);

ALTER TABLE public.store_facilities ENABLE ROW LEVEL SECURITY;

-- 用户端：已审批商家的设施公开可读
CREATE POLICY "store_facilities_read_approved" ON public.store_facilities
  FOR SELECT USING (
    merchant_id IN (SELECT id FROM public.merchants WHERE status = 'approved')
  );

-- 商家端：管理自己的设施
CREATE POLICY "store_facilities_manage_own" ON public.store_facilities
  FOR ALL USING (
    merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid())
  );

-- -------------------------------------------------------------
-- 5. 新建 review_photos 表（评价照片）
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.review_photos (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  review_id   uuid        NOT NULL REFERENCES public.reviews(id) ON DELETE CASCADE,
  image_url   text        NOT NULL,
  sort_order  int         NOT NULL DEFAULT 0,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_review_photos_review
  ON public.review_photos(review_id);

ALTER TABLE public.review_photos ENABLE ROW LEVEL SECURITY;

-- 评价照片公开可读
CREATE POLICY "review_photos_read_all" ON public.review_photos
  FOR SELECT USING (true);

-- 评价所有者可上传照片
CREATE POLICY "review_photos_insert_own" ON public.review_photos
  FOR INSERT WITH CHECK (
    review_id IN (SELECT id FROM public.reviews WHERE user_id = auth.uid())
  );

-- -------------------------------------------------------------
-- 6. get_merchant_review_summary 函数（用户端公开版）
--    复用 000008 get_review_stats 的统计逻辑和停用词列表
--    区别：无 auth.uid() 权限检查（面向所有用户），返回 jsonb
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_merchant_review_summary(
  p_merchant_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_result jsonb;
BEGIN
  -- 统计逻辑与 get_review_stats（000008）保持一致
  -- 不做 auth.uid() 权限检查，因为用户端需要公开访问
  WITH review_base AS (
    SELECT r.rating, r.comment
    FROM public.reviews r
    JOIN public.deals d ON d.id = r.deal_id
    WHERE d.merchant_id = p_merchant_id
  ),
  stats AS (
    SELECT
      -- 精度与 get_review_stats 保持一致：2 位小数
      COALESCE(ROUND(AVG(rating::numeric), 2), 0::numeric) AS avg_rating,
      COUNT(*) AS total_count,
      jsonb_build_object(
        '1', COUNT(*) FILTER (WHERE rating = 1),
        '2', COUNT(*) FILTER (WHERE rating = 2),
        '3', COUNT(*) FILTER (WHERE rating = 3),
        '4', COUNT(*) FILTER (WHERE rating = 4),
        '5', COUNT(*) FILTER (WHERE rating = 5)
      ) AS distribution
    FROM review_base
  ),
  -- 分词 + 停用词列表与 get_review_stats（000008）完全一致
  words_raw AS (
    SELECT
      lower(regexp_replace(word, '[^a-zA-Z]', '', 'g')) AS word
    FROM review_base,
    LATERAL regexp_split_to_table(COALESCE(comment, ''), '\s+') AS word
    WHERE length(word) > 0
  ),
  clean_words AS (
    SELECT word
    FROM words_raw
    WHERE length(word) >= 4
      AND word NOT IN (
        'the','a','an','is','it','in','on','at','to','for','of','and','or',
        'was','were','be','been','being','have','has','had','do','does','did',
        'will','would','could','should','may','might','this','that','these',
        'those','my','our','your','his','her','its','their','with','very',
        'just','like','great','good','nice','also','from','they','were',
        'really','very','more','some','than','when','then','here','food',
        'place','time','back','came','came','went','said'
      )
  ),
  word_freq AS (
    SELECT word, COUNT(*) AS cnt
    FROM clean_words
    WHERE word != ''
    GROUP BY word
    ORDER BY cnt DESC
    LIMIT 10
  )
  SELECT jsonb_build_object(
    'avg_rating', s.avg_rating,
    'total_count', s.total_count,
    'distribution', s.distribution,
    'top_tags', COALESCE(
      (SELECT jsonb_agg(jsonb_build_object('tag', word, 'count', cnt)) FROM word_freq),
      '[]'::jsonb
    )
  ) INTO v_result
  FROM stats s;

  RETURN COALESCE(v_result, '{"avg_rating":0,"total_count":0,"distribution":{"1":0,"2":0,"3":0,"4":0,"5":0},"top_tags":[]}'::jsonb);
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_merchant_review_summary(uuid) TO authenticated, anon;

-- -------------------------------------------------------------
-- 7. get_nearby_merchants 函数（附近推荐商家）
--    Haversine 距离计算，返回英里
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_nearby_merchants(
  p_lat        double precision,
  p_lng        double precision,
  p_exclude_id uuid    DEFAULT NULL,
  p_limit      int     DEFAULT 5
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_result jsonb;
BEGIN
  SELECT COALESCE(jsonb_agg(row_data ORDER BY distance_miles), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT jsonb_build_object(
      'id', m.id,
      'name', m.name,
      'logo_url', m.logo_url,
      'address', m.address,
      'price_per_person', m.price_per_person,
      'avg_rating', COALESCE(ROUND(AVG(d.rating)::numeric, 1), 0),
      'review_count', COALESCE(SUM(d.review_count)::int, 0),
      'distance_miles', ROUND((
        3958.8 * 2 * ASIN(SQRT(
          POWER(SIN(RADIANS(m.lat - p_lat) / 2), 2) +
          COS(RADIANS(p_lat)) * COS(RADIANS(m.lat)) *
          POWER(SIN(RADIANS(m.lng - p_lng) / 2), 2)
        ))
      )::numeric, 1)
    ) AS row_data,
    ROUND((
      3958.8 * 2 * ASIN(SQRT(
        POWER(SIN(RADIANS(m.lat - p_lat) / 2), 2) +
        COS(RADIANS(p_lat)) * COS(RADIANS(m.lat)) *
        POWER(SIN(RADIANS(m.lng - p_lng) / 2), 2)
      ))
    )::numeric, 1) AS distance_miles
    FROM public.merchants m
    LEFT JOIN public.deals d ON d.merchant_id = m.id AND d.is_active = true
    WHERE m.status = 'approved'
      AND m.is_online = true
      AND m.lat IS NOT NULL
      AND m.lng IS NOT NULL
      AND (p_exclude_id IS NULL OR m.id != p_exclude_id)
    GROUP BY m.id, m.name, m.logo_url, m.address, m.price_per_person, m.lat, m.lng
    ORDER BY distance_miles ASC
    LIMIT p_limit
  ) sub;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_nearby_merchants(double precision, double precision, uuid, int)
  TO authenticated, anon;

-- -------------------------------------------------------------
-- 8. 种子数据
-- -------------------------------------------------------------
DO $$
DECLARE
  v_m1 uuid; -- Texas BBQ House
  v_m2 uuid; -- Hot Pot Paradise
  v_m3 uuid; -- Sakura Sushi Bar
  v_r1 uuid; -- 第一条 review
  v_r2 uuid; -- 第二条 review
BEGIN
  -- 获取已有商家 ID
  SELECT id INTO v_m1 FROM public.merchants WHERE name = 'Texas BBQ House' LIMIT 1;
  SELECT id INTO v_m2 FROM public.merchants WHERE name = 'Hot Pot Paradise' LIMIT 1;
  SELECT id INTO v_m3 FROM public.merchants WHERE name = 'Sakura Sushi Bar' LIMIT 1;

  IF v_m1 IS NULL THEN RETURN; END IF;

  -- ── 更新商家基本信息 ──────────────────────────────
  UPDATE public.merchants SET
    price_per_person = 25.00,
    parking_info = 'Free parking lot with 30 spaces',
    wifi = true,
    established_year = 2018,
    tags = ARRAY['Parking', 'Private Rooms', 'Large Tables', 'Reservations', 'Baby Chairs', 'WiFi']
  WHERE id = v_m1;

  UPDATE public.merchants SET
    price_per_person = 35.00,
    parking_info = 'Free parking in plaza lot',
    wifi = true,
    established_year = 2020,
    tags = ARRAY['Parking', 'Large Tables', 'Reservations', 'WiFi', 'No Smoking']
  WHERE id = v_m2;

  UPDATE public.merchants SET
    price_per_person = 45.00,
    parking_info = 'Street parking available',
    wifi = true,
    established_year = 2019,
    tags = ARRAY['Parking', 'Private Rooms', 'Reservations', 'WiFi', 'Bar']
  WHERE id = v_m3;

  -- ── 门店照片（带 category）──────────────────────────
  INSERT INTO public.merchant_photos (merchant_id, photo_type, category, photo_url, sort_order) VALUES
    -- Texas BBQ House
    (v_m1, 'storefront', 'entrance', 'https://images.unsplash.com/photo-1555396273-367ea4eb4db5?w=800', 0),
    (v_m1, 'environment', 'main_hall', 'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?w=800', 1),
    (v_m1, 'environment', 'interior', 'https://images.unsplash.com/photo-1552566626-52f8b828add9?w=800', 2),
    (v_m1, 'environment', 'private_room', 'https://images.unsplash.com/photo-1414235077428-338989a2e8c0?w=800', 3),
    -- Hot Pot Paradise
    (v_m2, 'storefront', 'entrance', 'https://images.unsplash.com/photo-1526234362653-3b75a0c07438?w=800', 0),
    (v_m2, 'environment', 'main_hall', 'https://images.unsplash.com/photo-1559329007-40df8a9345d8?w=800', 1),
    (v_m2, 'environment', 'interior', 'https://images.unsplash.com/photo-1466978913421-dad2ebd01d17?w=800', 2),
    -- Sakura Sushi Bar
    (v_m3, 'storefront', 'entrance', 'https://images.unsplash.com/photo-1579027989536-b7b1f875659b?w=800', 0),
    (v_m3, 'environment', 'main_hall', 'https://images.unsplash.com/photo-1553621042-f6e147245754?w=800', 1),
    (v_m3, 'environment', 'interior', 'https://images.unsplash.com/photo-1540914124281-342587941389?w=800', 2),
    (v_m3, 'environment', 'private_room', 'https://images.unsplash.com/photo-1590846406792-0adc7f938f1d?w=800', 3)
  ON CONFLICT DO NOTHING;

  -- ── 菜品数据 ──────────────────────────────────────
  INSERT INTO public.menu_items (merchant_id, name, image_url, price, category, recommendation_count, is_signature, sort_order) VALUES
    -- Texas BBQ House 招牌菜
    (v_m1, 'Smoked Beef Brisket', 'https://images.unsplash.com/photo-1544025162-d76694265947?w=400', 28.00, 'signature', 342, true, 0),
    (v_m1, 'Baby Back Ribs', 'https://images.unsplash.com/photo-1529193591184-b1d58069ecdd?w=400', 24.00, 'signature', 289, true, 1),
    (v_m1, 'Jalapeño Sausage', 'https://images.unsplash.com/photo-1432139555190-58524dae6a55?w=400', 16.00, 'signature', 198, true, 2),
    -- Texas BBQ House 热门
    (v_m1, 'Pulled Pork Sandwich', 'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?w=400', 14.00, 'popular', 156, false, 3),
    (v_m1, 'Texas Combo Platter', 'https://images.unsplash.com/photo-1558030006-450675393462?w=400', 42.00, 'popular', 203, false, 4),
    (v_m1, 'Mac & Cheese', 'https://images.unsplash.com/photo-1543339494-b4cd4f7ba686?w=400', 8.00, 'popular', 178, false, 5),
    (v_m1, 'Coleslaw', 'https://images.unsplash.com/photo-1625938144755-652e08e359b7?w=400', 5.00, 'regular', 67, false, 6),
    -- Hot Pot Paradise 招牌菜
    (v_m2, 'Wagyu Beef Platter', 'https://images.unsplash.com/photo-1602030028438-4cf153cbae9e?w=400', 38.00, 'signature', 456, true, 0),
    (v_m2, 'Spicy Mala Broth', 'https://images.unsplash.com/photo-1569050467447-ce54b3bbc37d?w=400', 12.00, 'signature', 389, true, 1),
    (v_m2, 'Seafood Combo', 'https://images.unsplash.com/photo-1559847844-5315695dadae?w=400', 32.00, 'signature', 267, true, 2),
    -- Hot Pot Paradise 热门
    (v_m2, 'Lamb Shoulder Rolls', 'https://images.unsplash.com/photo-1585032226651-759b368d7246?w=400', 22.00, 'popular', 234, false, 3),
    (v_m2, 'Mushroom Platter', 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=400', 16.00, 'popular', 189, false, 4),
    (v_m2, 'Handmade Noodles', 'https://images.unsplash.com/photo-1552611052-33e04de1b100?w=400', 8.00, 'popular', 156, false, 5),
    -- Sakura Sushi Bar 招牌菜
    (v_m3, 'Chef\'s Omakase', 'https://images.unsplash.com/photo-1579871494447-9811cf80d66c?w=400', 68.00, 'signature', 312, true, 0),
    (v_m3, 'Dragon Roll', 'https://images.unsplash.com/photo-1553621042-f6e147245754?w=400', 18.00, 'signature', 278, true, 1),
    (v_m3, 'Sashimi Deluxe', 'https://images.unsplash.com/photo-1534256958597-7fe685cbd745?w=400', 32.00, 'signature', 245, true, 2),
    -- Sakura Sushi Bar 热门
    (v_m3, 'Spicy Tuna Roll', 'https://images.unsplash.com/photo-1617196034796-73dfa7b1fd56?w=400', 14.00, 'popular', 198, false, 3),
    (v_m3, 'Miso Soup', 'https://images.unsplash.com/photo-1547592166-23ac45744acd?w=400', 5.00, 'popular', 167, false, 4),
    (v_m3, 'Tempura Platter', 'https://images.unsplash.com/photo-1615361200098-9e630ec29b4e?w=400', 22.00, 'popular', 145, false, 5)
  ON CONFLICT DO NOTHING;

  -- ── 设施数据 ──────────────────────────────────────
  INSERT INTO public.store_facilities (merchant_id, facility_type, name, description, image_url, capacity, is_free, sort_order) VALUES
    -- Texas BBQ House
    (v_m1, 'private_room', 'Private Dining Room A', 'Ideal for business dinners and celebrations, with dedicated service', 'https://images.unsplash.com/photo-1414235077428-338989a2e8c0?w=400', 12, false, 0),
    (v_m1, 'private_room', 'Private Dining Room B', 'Cozy room perfect for family gatherings', 'https://images.unsplash.com/photo-1590846406792-0adc7f938f1d?w=400', 8, false, 1),
    (v_m1, 'parking', 'Free Parking Lot', '30 spaces available, free for all diners', NULL, NULL, true, 2),
    (v_m1, 'baby_chair', 'Baby Chairs', 'High chairs available upon request at no charge', NULL, NULL, true, 3),
    (v_m1, 'large_table', 'Large Tables', 'Tables seating 8-12 guests available', NULL, 12, true, 4),
    (v_m1, 'wifi', 'Free WiFi', 'Complimentary high-speed WiFi for all guests', NULL, NULL, true, 5),
    -- Hot Pot Paradise
    (v_m2, 'parking', 'Plaza Parking', 'Free parking in the shared plaza lot', NULL, NULL, true, 0),
    (v_m2, 'large_table', 'Large Round Tables', 'Round tables seating up to 10 guests', NULL, 10, true, 1),
    (v_m2, 'wifi', 'Free WiFi', 'High-speed WiFi available', NULL, NULL, true, 2),
    (v_m2, 'no_smoking', 'No Smoking', 'Smoke-free dining environment', NULL, NULL, true, 3),
    -- Sakura Sushi Bar
    (v_m3, 'private_room', 'Tatami Room', 'Traditional Japanese-style private dining with tatami seating', 'https://images.unsplash.com/photo-1590846406792-0adc7f938f1d?w=400', 6, false, 0),
    (v_m3, 'parking', 'Street Parking', 'Metered street parking available nearby', NULL, NULL, false, 1),
    (v_m3, 'wifi', 'Free WiFi', 'Complimentary WiFi', NULL, NULL, true, 2),
    (v_m3, 'reservation', 'Online Reservation', 'Reserve your table in advance through our website', NULL, NULL, true, 3)
  ON CONFLICT DO NOTHING;

  -- ── 评价照片种子数据 ──────────────────────────────
  -- 获取前两条 review 的 ID
  SELECT id INTO v_r1 FROM public.reviews ORDER BY created_at ASC LIMIT 1;
  SELECT id INTO v_r2 FROM public.reviews ORDER BY created_at ASC OFFSET 1 LIMIT 1;

  IF v_r1 IS NOT NULL THEN
    INSERT INTO public.review_photos (review_id, image_url, sort_order) VALUES
      (v_r1, 'https://images.unsplash.com/photo-1544025162-d76694265947?w=400', 0),
      (v_r1, 'https://images.unsplash.com/photo-1529193591184-b1d58069ecdd?w=400', 1)
    ON CONFLICT DO NOTHING;
  END IF;

  IF v_r2 IS NOT NULL THEN
    INSERT INTO public.review_photos (review_id, image_url, sort_order) VALUES
      (v_r2, 'https://images.unsplash.com/photo-1569050467447-ce54b3bbc37d?w=400', 0)
    ON CONFLICT DO NOTHING;
  END IF;

END $$;
