-- ============================================================
-- Migration: 20260307000001_chain_store_and_staff.sql
-- 功能: 连锁店（品牌多门店）+ 员工权限体系
-- 新增: brands, brand_admins, brand_invitations, staff_invitations
-- 修改: merchants (加 brand_id), merchant_staff (重构角色), deals (加 deal_template_id)
-- 更新: RLS 策略, RPC 搜索函数
-- ============================================================

-- ============================================================
-- 第一部分: 新建表
-- ============================================================

-- ------------------------------------------------------------
-- 1. brands 表 — 品牌实体
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.brands (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  name         TEXT        NOT NULL,
  logo_url     TEXT,
  description  TEXT,
  category     TEXT,
  website      TEXT,
  company_name TEXT,
  ein          TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_brands_name ON public.brands(name);
COMMENT ON TABLE public.brands IS '品牌表：连锁店品牌实体，多个 merchants 可关联同一 brand';

-- ------------------------------------------------------------
-- 2. brand_admins 表 — 品牌管理员
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.brand_admins (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  brand_id   UUID        NOT NULL REFERENCES public.brands(id) ON DELETE CASCADE,
  user_id    UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role       TEXT        NOT NULL CHECK (role IN ('owner', 'admin')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (brand_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_brand_admins_brand ON public.brand_admins(brand_id);
CREATE INDEX IF NOT EXISTS idx_brand_admins_user  ON public.brand_admins(user_id);
COMMENT ON TABLE public.brand_admins IS '品牌管理员表：owner 和 admin 可管理品牌下所有门店';

-- ------------------------------------------------------------
-- 3. brand_invitations 表 — 品牌邀请
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.brand_invitations (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  brand_id      UUID        NOT NULL REFERENCES public.brands(id) ON DELETE CASCADE,
  invited_email TEXT        NOT NULL,
  role          TEXT        NOT NULL CHECK (role IN ('admin', 'store_owner')),
  merchant_id   UUID        REFERENCES public.merchants(id),
  invited_by    UUID        NOT NULL REFERENCES auth.users(id),
  status        TEXT        NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'expired', 'cancelled')),
  expires_at    TIMESTAMPTZ NOT NULL DEFAULT now() + interval '7 days',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_brand_invitations_brand ON public.brand_invitations(brand_id);
CREATE INDEX IF NOT EXISTS idx_brand_invitations_email ON public.brand_invitations(invited_email);
COMMENT ON TABLE public.brand_invitations IS '品牌邀请表：邀请管理员或门店加入品牌';

-- ------------------------------------------------------------
-- 4. staff_invitations 表 — 门店员工邀请
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.staff_invitations (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id   UUID        NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  invited_email TEXT        NOT NULL,
  role          TEXT        NOT NULL CHECK (role IN ('manager', 'cashier', 'service')),
  invited_by    UUID        NOT NULL REFERENCES auth.users(id),
  status        TEXT        NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'expired', 'cancelled')),
  expires_at    TIMESTAMPTZ NOT NULL DEFAULT now() + interval '7 days',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_staff_invitations_merchant ON public.staff_invitations(merchant_id);
CREATE INDEX IF NOT EXISTS idx_staff_invitations_email    ON public.staff_invitations(invited_email);
COMMENT ON TABLE public.staff_invitations IS '门店员工邀请表：邀请员工加入门店';

-- ============================================================
-- 第二部分: 修改现有表
-- ============================================================

-- ------------------------------------------------------------
-- 5. merchants 表新增 brand_id
-- ------------------------------------------------------------
ALTER TABLE public.merchants
  ADD COLUMN IF NOT EXISTS brand_id UUID REFERENCES public.brands(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_merchants_brand ON public.merchants(brand_id);
COMMENT ON COLUMN public.merchants.brand_id IS '所属品牌 ID，NULL 表示独立门店（非连锁）';

-- ------------------------------------------------------------
-- 6. deals 表预留 deal_template_id（V2 品牌级 Deal 模板用）
-- ------------------------------------------------------------
ALTER TABLE public.deals
  ADD COLUMN IF NOT EXISTS deal_template_id UUID;

COMMENT ON COLUMN public.deals.deal_template_id IS 'V2 预留：品牌级 Deal 模板 ID，不为 NULL 表示从模板复制而来';

-- ------------------------------------------------------------
-- 7. merchant_staff 表重构
--    现有: staff_user_id, role IN ('scan_only','full_access')
--    目标: user_id, role IN ('manager','cashier','service'), +nickname, +is_active, +updated_at
-- ------------------------------------------------------------

-- 7a. 重命名 staff_user_id → user_id
ALTER TABLE public.merchant_staff
  RENAME COLUMN staff_user_id TO user_id;

-- 7b. 删除旧的 role CHECK 约束，添加新的
-- 先找到并删除旧的 CHECK 约束（约束名可能是自动生成的）
DO $$
DECLARE
  constraint_name TEXT;
BEGIN
  -- 查找 merchant_staff 表上 role 列的 CHECK 约束
  SELECT c.conname INTO constraint_name
  FROM pg_constraint c
  JOIN pg_attribute a ON a.attnum = ANY(c.conkey)
    AND a.attrelid = c.conrelid
  WHERE c.conrelid = 'public.merchant_staff'::regclass
    AND c.contype = 'c'
    AND a.attname = 'role'
  LIMIT 1;

  IF constraint_name IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.merchant_staff DROP CONSTRAINT %I', constraint_name);
  END IF;
END $$;

-- 添加新的 role CHECK
ALTER TABLE public.merchant_staff
  ADD CONSTRAINT merchant_staff_role_check
  CHECK (role IN ('manager', 'cashier', 'service'));

-- 7c. 迁移现有数据的 role 值
UPDATE public.merchant_staff SET role = 'manager' WHERE role = 'full_access';
UPDATE public.merchant_staff SET role = 'cashier' WHERE role = 'scan_only';

-- 7d. 新增列
ALTER TABLE public.merchant_staff
  ADD COLUMN IF NOT EXISTS nickname VARCHAR(50),
  ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

-- 7e. 更新唯一约束（列名变了）
-- 删除旧的 UNIQUE 约束
DO $$
DECLARE
  constraint_name TEXT;
BEGIN
  SELECT c.conname INTO constraint_name
  FROM pg_constraint c
  WHERE c.conrelid = 'public.merchant_staff'::regclass
    AND c.contype = 'u'
  LIMIT 1;

  IF constraint_name IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.merchant_staff DROP CONSTRAINT %I', constraint_name);
  END IF;
END $$;

-- 添加新的唯一约束
ALTER TABLE public.merchant_staff
  ADD CONSTRAINT merchant_staff_merchant_user_unique UNIQUE (merchant_id, user_id);

-- 7f. 更新索引（旧索引引用 staff_user_id，列已重命名为 user_id，索引自动跟随）
-- 但索引名还是旧的，创建新名的索引
DROP INDEX IF EXISTS idx_merchant_staff_user_id;
CREATE INDEX IF NOT EXISTS idx_merchant_staff_user ON public.merchant_staff(user_id);

-- ============================================================
-- 第三部分: RLS 策略
-- ============================================================

-- ------------------------------------------------------------
-- 8. brands 表 RLS
-- ------------------------------------------------------------
ALTER TABLE public.brands ENABLE ROW LEVEL SECURITY;

-- 所有人可读品牌信息
CREATE POLICY "brands_select_all" ON public.brands
  FOR SELECT USING (true);

-- 品牌管理员可修改
CREATE POLICY "brands_modify_by_admin" ON public.brands
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.brand_admins
      WHERE brand_admins.brand_id = brands.id
        AND brand_admins.user_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.brand_admins
      WHERE brand_admins.brand_id = brands.id
        AND brand_admins.user_id = auth.uid()
    )
  );

-- ------------------------------------------------------------
-- 9. brand_admins 表 RLS
-- ------------------------------------------------------------
ALTER TABLE public.brand_admins ENABLE ROW LEVEL SECURITY;

-- 同品牌管理员可互相看到
CREATE POLICY "brand_admins_select_same_brand" ON public.brand_admins
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.brand_admins ba2
      WHERE ba2.brand_id = brand_admins.brand_id
        AND ba2.user_id = auth.uid()
    )
  );

-- 自己可读自己的记录
CREATE POLICY "brand_admins_select_own" ON public.brand_admins
  FOR SELECT USING (user_id = auth.uid());

-- 品牌 owner 可增删管理员
CREATE POLICY "brand_admins_insert_by_owner" ON public.brand_admins
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.brand_admins ba2
      WHERE ba2.brand_id = brand_admins.brand_id
        AND ba2.user_id = auth.uid()
        AND ba2.role = 'owner'
    )
  );

CREATE POLICY "brand_admins_delete_by_owner" ON public.brand_admins
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.brand_admins ba2
      WHERE ba2.brand_id = brand_admins.brand_id
        AND ba2.user_id = auth.uid()
        AND ba2.role = 'owner'
    )
  );

-- ------------------------------------------------------------
-- 10. brand_invitations 表 RLS
-- ------------------------------------------------------------
ALTER TABLE public.brand_invitations ENABLE ROW LEVEL SECURITY;

-- 品牌管理员可管理邀请
CREATE POLICY "brand_invitations_manage" ON public.brand_invitations
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.brand_admins
      WHERE brand_admins.brand_id = brand_invitations.brand_id
        AND brand_admins.user_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.brand_admins
      WHERE brand_admins.brand_id = brand_invitations.brand_id
        AND brand_admins.user_id = auth.uid()
    )
  );

-- 被邀请人可读自己的邀请（通过 email 匹配 auth.email()）
CREATE POLICY "brand_invitations_read_invited" ON public.brand_invitations
  FOR SELECT USING (invited_email = auth.email());

-- ------------------------------------------------------------
-- 11. staff_invitations 表 RLS
-- ------------------------------------------------------------
ALTER TABLE public.staff_invitations ENABLE ROW LEVEL SECURITY;

-- 门店 owner + manager + 品牌管理员可管理
CREATE POLICY "staff_invitations_manage" ON public.staff_invitations
  FOR ALL USING (
    -- 门店 owner
    EXISTS (
      SELECT 1 FROM public.merchants
      WHERE merchants.id = staff_invitations.merchant_id
        AND merchants.user_id = auth.uid()
    )
    OR
    -- 门店 manager
    EXISTS (
      SELECT 1 FROM public.merchant_staff
      WHERE merchant_staff.merchant_id = staff_invitations.merchant_id
        AND merchant_staff.user_id = auth.uid()
        AND merchant_staff.role = 'manager'
        AND merchant_staff.is_active = true
    )
    OR
    -- 品牌管理员
    EXISTS (
      SELECT 1 FROM public.merchants m
      JOIN public.brand_admins ba ON ba.brand_id = m.brand_id
      WHERE m.id = staff_invitations.merchant_id
        AND ba.user_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.merchants
      WHERE merchants.id = staff_invitations.merchant_id
        AND merchants.user_id = auth.uid()
    )
    OR
    EXISTS (
      SELECT 1 FROM public.merchant_staff
      WHERE merchant_staff.merchant_id = staff_invitations.merchant_id
        AND merchant_staff.user_id = auth.uid()
        AND merchant_staff.role = 'manager'
        AND merchant_staff.is_active = true
    )
    OR
    EXISTS (
      SELECT 1 FROM public.merchants m
      JOIN public.brand_admins ba ON ba.brand_id = m.brand_id
      WHERE m.id = staff_invitations.merchant_id
        AND ba.user_id = auth.uid()
    )
  );

-- 被邀请人可读自己的邀请
CREATE POLICY "staff_invitations_read_invited" ON public.staff_invitations
  FOR SELECT USING (invited_email = auth.email());

-- ------------------------------------------------------------
-- 12. merchants 表 RLS 更新 — 品牌管理员 + manager 也可管理
-- ------------------------------------------------------------

-- 删除现有冲突策略
DROP POLICY IF EXISTS "merchants_manage_own" ON public.merchants;
DROP POLICY IF EXISTS "merchants_readable_by_owner_and_full_staff" ON public.merchants;

-- SELECT: 所有人可读（用户端需要展示商家信息）
-- 注意: 初始 schema 已有 merchants RLS enabled
CREATE POLICY "merchants_select_all" ON public.merchants
  FOR SELECT USING (true);

-- INSERT: 门店 owner 自己插入（保留原有逻辑）
-- merchants_insert_own 已存在，不动

-- UPDATE/DELETE: 门店 owner / 品牌管理员 / manager 可修改
CREATE POLICY "merchants_modify" ON public.merchants
  FOR UPDATE USING (
    -- 门店 owner
    user_id = auth.uid()
    OR
    -- 品牌管理员
    (brand_id IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.brand_admins
      WHERE brand_admins.brand_id = merchants.brand_id
        AND brand_admins.user_id = auth.uid()
    ))
    OR
    -- 门店 manager
    EXISTS (
      SELECT 1 FROM public.merchant_staff
      WHERE merchant_staff.merchant_id = merchants.id
        AND merchant_staff.user_id = auth.uid()
        AND merchant_staff.role = 'manager'
        AND merchant_staff.is_active = true
    )
  )
  WITH CHECK (
    user_id = auth.uid()
    OR
    (brand_id IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.brand_admins
      WHERE brand_admins.brand_id = merchants.brand_id
        AND brand_admins.user_id = auth.uid()
    ))
    OR
    EXISTS (
      SELECT 1 FROM public.merchant_staff
      WHERE merchant_staff.merchant_id = merchants.id
        AND merchant_staff.user_id = auth.uid()
        AND merchant_staff.role = 'manager'
        AND merchant_staff.is_active = true
    )
  );

-- DELETE: 仅门店 owner 可删除
CREATE POLICY "merchants_delete_owner_only" ON public.merchants
  FOR DELETE USING (user_id = auth.uid());

-- ------------------------------------------------------------
-- 13. merchant_staff 表 RLS 更新
-- ------------------------------------------------------------

-- 删除旧策略
DROP POLICY IF EXISTS "merchant_owner_manage_staff" ON public.merchant_staff;
DROP POLICY IF EXISTS "staff_read_own_record" ON public.merchant_staff;

-- SELECT: 员工自己 + 门店 owner + 同门店 manager + 品牌管理员
CREATE POLICY "staff_select" ON public.merchant_staff
  FOR SELECT USING (
    -- 员工自己
    user_id = auth.uid()
    OR
    -- 门店 owner
    EXISTS (
      SELECT 1 FROM public.merchants
      WHERE merchants.id = merchant_staff.merchant_id
        AND merchants.user_id = auth.uid()
    )
    OR
    -- 同门店 manager
    EXISTS (
      SELECT 1 FROM public.merchant_staff ms2
      WHERE ms2.merchant_id = merchant_staff.merchant_id
        AND ms2.user_id = auth.uid()
        AND ms2.role = 'manager'
        AND ms2.is_active = true
    )
    OR
    -- 品牌管理员
    EXISTS (
      SELECT 1 FROM public.merchants m
      JOIN public.brand_admins ba ON ba.brand_id = m.brand_id
      WHERE m.id = merchant_staff.merchant_id
        AND ba.user_id = auth.uid()
    )
  );

-- INSERT/UPDATE/DELETE: 门店 owner + manager + 品牌管理员
CREATE POLICY "staff_manage" ON public.merchant_staff
  FOR ALL USING (
    -- 门店 owner
    EXISTS (
      SELECT 1 FROM public.merchants
      WHERE merchants.id = merchant_staff.merchant_id
        AND merchants.user_id = auth.uid()
    )
    OR
    -- 同门店 manager
    EXISTS (
      SELECT 1 FROM public.merchant_staff ms2
      WHERE ms2.merchant_id = merchant_staff.merchant_id
        AND ms2.user_id = auth.uid()
        AND ms2.role = 'manager'
        AND ms2.is_active = true
    )
    OR
    -- 品牌管理员
    EXISTS (
      SELECT 1 FROM public.merchants m
      JOIN public.brand_admins ba ON ba.brand_id = m.brand_id
      WHERE m.id = merchant_staff.merchant_id
        AND ba.user_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.merchants
      WHERE merchants.id = merchant_staff.merchant_id
        AND merchants.user_id = auth.uid()
    )
    OR
    EXISTS (
      SELECT 1 FROM public.merchant_staff ms2
      WHERE ms2.merchant_id = merchant_staff.merchant_id
        AND ms2.user_id = auth.uid()
        AND ms2.role = 'manager'
        AND ms2.is_active = true
    )
    OR
    EXISTS (
      SELECT 1 FROM public.merchants m
      JOIN public.brand_admins ba ON ba.brand_id = m.brand_id
      WHERE m.id = merchant_staff.merchant_id
        AND ba.user_id = auth.uid()
    )
  );

-- ------------------------------------------------------------
-- 14. deals 表 RLS 更新 — 品牌管理员 + manager 也可管理
-- ------------------------------------------------------------

-- 删除旧的 deals 管理策略
DROP POLICY IF EXISTS "deals_merchant_select_own" ON public.deals;
DROP POLICY IF EXISTS "deals_merchant_insert_own" ON public.deals;
DROP POLICY IF EXISTS "deals_merchant_update_own" ON public.deals;
DROP POLICY IF EXISTS "deals_merchant_delete_own" ON public.deals;

-- SELECT: 所有人可读（用户端需要展示）
-- deals_read_active 已存在，但只对 is_active=true 的生效
-- 商家需要看到所有自己的 deal（包括 inactive/pending）
CREATE POLICY "deals_select_all" ON public.deals
  FOR SELECT USING (true);

-- INSERT: 门店 owner + manager + 品牌管理员
CREATE POLICY "deals_insert" ON public.deals
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.merchants
      WHERE merchants.id = deals.merchant_id
        AND merchants.user_id = auth.uid()
    )
    OR
    EXISTS (
      SELECT 1 FROM public.merchant_staff
      WHERE merchant_staff.merchant_id = deals.merchant_id
        AND merchant_staff.user_id = auth.uid()
        AND merchant_staff.role = 'manager'
        AND merchant_staff.is_active = true
    )
    OR
    EXISTS (
      SELECT 1 FROM public.merchants m
      JOIN public.brand_admins ba ON ba.brand_id = m.brand_id
      WHERE m.id = deals.merchant_id
        AND ba.user_id = auth.uid()
    )
  );

-- UPDATE: 门店 owner + manager + 品牌管理员 + admin（保留 admin 策略）
CREATE POLICY "deals_update" ON public.deals
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.merchants
      WHERE merchants.id = deals.merchant_id
        AND merchants.user_id = auth.uid()
    )
    OR
    EXISTS (
      SELECT 1 FROM public.merchant_staff
      WHERE merchant_staff.merchant_id = deals.merchant_id
        AND merchant_staff.user_id = auth.uid()
        AND merchant_staff.role = 'manager'
        AND merchant_staff.is_active = true
    )
    OR
    EXISTS (
      SELECT 1 FROM public.merchants m
      JOIN public.brand_admins ba ON ba.brand_id = m.brand_id
      WHERE m.id = deals.merchant_id
        AND ba.user_id = auth.uid()
    )
  );

-- DELETE: 门店 owner + manager + 品牌管理员
CREATE POLICY "deals_delete" ON public.deals
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.merchants
      WHERE merchants.id = deals.merchant_id
        AND merchants.user_id = auth.uid()
    )
    OR
    EXISTS (
      SELECT 1 FROM public.merchant_staff
      WHERE merchant_staff.merchant_id = deals.merchant_id
        AND merchant_staff.user_id = auth.uid()
        AND merchant_staff.role = 'manager'
        AND merchant_staff.is_active = true
    )
    OR
    EXISTS (
      SELECT 1 FROM public.merchants m
      JOIN public.brand_admins ba ON ba.brand_id = m.brand_id
      WHERE m.id = deals.merchant_id
        AND ba.user_id = auth.uid()
    )
  );

-- ------------------------------------------------------------
-- 15. merchant_photos / merchant_hours RLS — 品牌管理员也可读取
-- ------------------------------------------------------------
CREATE POLICY "merchant_photos_brand_admin_read" ON public.merchant_photos
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.merchants m
      JOIN public.brand_admins ba ON ba.brand_id = m.brand_id
      WHERE m.id = merchant_photos.merchant_id
        AND ba.user_id = auth.uid()
    )
  );

CREATE POLICY "merchant_hours_brand_admin_read" ON public.merchant_hours
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.merchants m
      JOIN public.brand_admins ba ON ba.brand_id = m.brand_id
      WHERE m.id = merchant_hours.merchant_id
        AND ba.user_id = auth.uid()
    )
  );

-- ============================================================
-- 第四部分: RPC 搜索函数更新 — 增加品牌名返回
-- ============================================================

-- 必须先 DROP 再 CREATE（返回类型变了）
DROP FUNCTION IF EXISTS search_deals_nearby(DECIMAL, DECIMAL, DECIMAL, TEXT, INT, INT);
DROP FUNCTION IF EXISTS search_deals_by_city(TEXT, DECIMAL, DECIMAL, TEXT, INT, INT);

-- ------------------------------------------------------------
-- 16. search_deals_nearby — 增加 merchant_brand_name
-- ------------------------------------------------------------
CREATE FUNCTION search_deals_nearby(
  p_lat      DECIMAL,
  p_lng      DECIMAL,
  p_radius_m DECIMAL DEFAULT 24140,
  p_category TEXT    DEFAULT NULL,
  p_limit    INT     DEFAULT 20,
  p_offset   INT     DEFAULT 0
)
RETURNS TABLE(
  id                          UUID,
  merchant_id                 UUID,
  title                       TEXT,
  description                 TEXT,
  category                    TEXT,
  original_price              DECIMAL,
  discount_price              DECIMAL,
  discount_percent            INT,
  discount_label              TEXT,
  image_urls                  TEXT[],
  is_featured                 BOOL,
  rating                      DECIMAL,
  review_count                INT,
  total_sold                  INT,
  expires_at                  TIMESTAMPTZ,
  merchant_name               TEXT,
  merchant_logo_url           TEXT,
  merchant_city               TEXT,
  merchant_homepage_cover_url TEXT,
  distance_meters             DECIMAL,
  merchant_brand_name         TEXT
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
    COALESCE(m.logo_url, b.logo_url),
    m.city,
    m.homepage_cover_url,
    (3958.8 * 2 * ASIN(SQRT(
      POWER(SIN(RADIANS((m.lat - p_lat) / 2)), 2) +
      COS(RADIANS(p_lat)) * COS(RADIANS(m.lat)) *
      POWER(SIN(RADIANS((m.lng - p_lng) / 2)), 2)
    )) * 1609.34)::DECIMAL AS distance_meters,
    b.name AS merchant_brand_name
  FROM deals d
  JOIN merchants m ON d.merchant_id = m.id
  LEFT JOIN brands b ON m.brand_id = b.id
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

-- ------------------------------------------------------------
-- 17. search_deals_by_city — 增加 merchant_brand_name
-- ------------------------------------------------------------
CREATE FUNCTION search_deals_by_city(
  p_city     TEXT,
  p_user_lat DECIMAL DEFAULT NULL,
  p_user_lng DECIMAL DEFAULT NULL,
  p_category TEXT    DEFAULT NULL,
  p_limit    INT     DEFAULT 20,
  p_offset   INT     DEFAULT 0
)
RETURNS TABLE(
  id                          UUID,
  merchant_id                 UUID,
  title                       TEXT,
  description                 TEXT,
  category                    TEXT,
  original_price              DECIMAL,
  discount_price              DECIMAL,
  discount_percent            INT,
  discount_label              TEXT,
  image_urls                  TEXT[],
  is_featured                 BOOL,
  rating                      DECIMAL,
  review_count                INT,
  total_sold                  INT,
  expires_at                  TIMESTAMPTZ,
  merchant_name               TEXT,
  merchant_logo_url           TEXT,
  merchant_city               TEXT,
  merchant_homepage_cover_url TEXT,
  distance_meters             DECIMAL,
  merchant_brand_name         TEXT
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
    COALESCE(m.logo_url, b.logo_url),
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
    b.name AS merchant_brand_name
  FROM deals d
  JOIN merchants m ON d.merchant_id = m.id
  LEFT JOIN brands b ON m.brand_id = b.id
  WHERE d.is_active = true
    AND d.expires_at > NOW()
    AND m.city = p_city
    AND (p_category IS NULL OR d.category = p_category)
  ORDER BY d.is_featured DESC, COALESCE(d.rating, 0) DESC, d.created_at DESC
  OFFSET p_offset LIMIT p_limit;
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION search_deals_by_city TO authenticated, anon;

-- ============================================================
-- 完成
-- ============================================================
-- 验证查询（部署后手动执行）：
-- SELECT COUNT(*) FROM brands;                    -- 应为 0
-- SELECT COUNT(*) FROM brand_admins;              -- 应为 0
-- SELECT COUNT(*) FROM brand_invitations;         -- 应为 0
-- SELECT COUNT(*) FROM staff_invitations;         -- 应为 0
-- SELECT column_name FROM information_schema.columns WHERE table_name = 'merchants' AND column_name = 'brand_id';
-- SELECT column_name FROM information_schema.columns WHERE table_name = 'deals' AND column_name = 'deal_template_id';
-- SELECT column_name FROM information_schema.columns WHERE table_name = 'merchant_staff' AND column_name = 'user_id';
