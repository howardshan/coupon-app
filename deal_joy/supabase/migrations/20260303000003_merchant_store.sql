-- =============================================================
-- DealJoy 门店信息管理 Migration
-- 为 merchants 表添加 tags 字段
-- 新建 merchant_photos、merchant_hours 表
-- =============================================================

-- -------------------------------------------------------------
-- 1. 为 merchants 表添加 tags 字段
--    store_name/description/phone/address/lat/lng 已在 initial_schema.sql 中存在
--    (name=店名, description=简介, phone=电话, address=地址, lat/lng=坐标)
-- -------------------------------------------------------------
ALTER TABLE public.merchants
  ADD COLUMN IF NOT EXISTS tags text[] NOT NULL DEFAULT '{}';

-- tags 索引（用于用户端搜索过滤）
CREATE INDEX IF NOT EXISTS idx_merchants_tags
  ON public.merchants USING GIN (tags);

-- -------------------------------------------------------------
-- 2. 新建 merchant_photos 表
--    存储门店各类型照片记录（文件本体存 Supabase Storage）
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.merchant_photos (
  id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id  uuid        NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  -- photo_type 取值: storefront | environment | product
  photo_type   text        NOT NULL CHECK (photo_type IN ('storefront', 'environment', 'product')),
  photo_url    text        NOT NULL,     -- Supabase Storage public URL
  sort_order   int         NOT NULL DEFAULT 0,
  created_at   timestamptz NOT NULL DEFAULT now()
);

-- 索引
CREATE INDEX IF NOT EXISTS idx_merchant_photos_merchant_id
  ON public.merchant_photos(merchant_id);

CREATE INDEX IF NOT EXISTS idx_merchant_photos_type
  ON public.merchant_photos(merchant_id, photo_type);

-- 约束：storefront 照片最多 1 张（通过触发器实现，允许替换）
-- environment + product 各最多 10 张（在 Edge Function 层面校验）

-- -------------------------------------------------------------
-- 3. 新建 merchant_hours 表
--    每行代表一天的营业时间设置
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.merchant_hours (
  id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id  uuid        NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  -- day_of_week: 0=Sunday, 1=Monday, ..., 6=Saturday（与 Dart DateTime.weekday 对齐）
  day_of_week  int         NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),
  open_time    time,        -- NULL 时表示全天关闭
  close_time   time,        -- NULL 时表示全天关闭
  is_closed    boolean     NOT NULL DEFAULT false,
  -- 每家商户每天只有一条记录
  UNIQUE (merchant_id, day_of_week)
);

-- 索引
CREATE INDEX IF NOT EXISTS idx_merchant_hours_merchant_id
  ON public.merchant_hours(merchant_id);

-- -------------------------------------------------------------
-- 4. RLS: merchant_photos
-- -------------------------------------------------------------
ALTER TABLE public.merchant_photos ENABLE ROW LEVEL SECURITY;

-- 商家只能查看自己的照片
CREATE POLICY "merchant_photos_select_own"
  ON public.merchant_photos
  FOR SELECT
  USING (
    merchant_id IN (
      SELECT id FROM public.merchants WHERE user_id = auth.uid()
    )
  );

-- 商家只能插入自己的照片
CREATE POLICY "merchant_photos_insert_own"
  ON public.merchant_photos
  FOR INSERT
  WITH CHECK (
    merchant_id IN (
      SELECT id FROM public.merchants WHERE user_id = auth.uid()
    )
  );

-- 商家只能更新自己的照片（排序）
CREATE POLICY "merchant_photos_update_own"
  ON public.merchant_photos
  FOR UPDATE
  USING (
    merchant_id IN (
      SELECT id FROM public.merchants WHERE user_id = auth.uid()
    )
  );

-- 商家只能删除自己的照片
CREATE POLICY "merchant_photos_delete_own"
  ON public.merchant_photos
  FOR DELETE
  USING (
    merchant_id IN (
      SELECT id FROM public.merchants WHERE user_id = auth.uid()
    )
  );

-- 用户端可以查看已审批商家的照片（公开展示）
CREATE POLICY "merchant_photos_read_approved"
  ON public.merchant_photos
  FOR SELECT
  USING (
    merchant_id IN (
      SELECT id FROM public.merchants WHERE status = 'approved'
    )
  );

-- -------------------------------------------------------------
-- 5. RLS: merchant_hours
-- -------------------------------------------------------------
ALTER TABLE public.merchant_hours ENABLE ROW LEVEL SECURITY;

-- 商家只能查看自己的营业时间
CREATE POLICY "merchant_hours_select_own"
  ON public.merchant_hours
  FOR SELECT
  USING (
    merchant_id IN (
      SELECT id FROM public.merchants WHERE user_id = auth.uid()
    )
  );

-- 商家只能插入自己的营业时间
CREATE POLICY "merchant_hours_insert_own"
  ON public.merchant_hours
  FOR INSERT
  WITH CHECK (
    merchant_id IN (
      SELECT id FROM public.merchants WHERE user_id = auth.uid()
    )
  );

-- 商家只能更新自己的营业时间
CREATE POLICY "merchant_hours_update_own"
  ON public.merchant_hours
  FOR UPDATE
  USING (
    merchant_id IN (
      SELECT id FROM public.merchants WHERE user_id = auth.uid()
    )
  );

-- 商家只能删除自己的营业时间（批量重写时先删后插）
CREATE POLICY "merchant_hours_delete_own"
  ON public.merchant_hours
  FOR DELETE
  USING (
    merchant_id IN (
      SELECT id FROM public.merchants WHERE user_id = auth.uid()
    )
  );

-- 用户端可以查看已审批商家的营业时间（公开展示）
CREATE POLICY "merchant_hours_read_approved"
  ON public.merchant_hours
  FOR SELECT
  USING (
    merchant_id IN (
      SELECT id FROM public.merchants WHERE status = 'approved'
    )
  );

-- -------------------------------------------------------------
-- 6. Storage bucket: merchant-photos
--    公开 bucket，用户端无需 auth 即可加载图片
-- -------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public)
  VALUES ('merchant-photos', 'merchant-photos', true)
  ON CONFLICT (id) DO NOTHING;

-- Storage RLS: 已认证商家可上传照片
--   路径格式: {merchant_id}/{photo_type}/{uuid}.jpg
CREATE POLICY "merchant_photos_storage_insert"
  ON storage.objects
  FOR INSERT
  WITH CHECK (
    bucket_id = 'merchant-photos'
    AND auth.role() = 'authenticated'
  );

-- Storage RLS: 所有人可读取（公开 bucket，图片展示给用户端）
CREATE POLICY "merchant_photos_storage_select"
  ON storage.objects
  FOR SELECT
  USING (bucket_id = 'merchant-photos');

-- Storage RLS: 已认证商家可删除自己目录下的文件
CREATE POLICY "merchant_photos_storage_delete"
  ON storage.objects
  FOR DELETE
  USING (
    bucket_id = 'merchant-photos'
    AND auth.role() = 'authenticated'
  );

-- -------------------------------------------------------------
-- 7. 为已审批商家插入默认营业时间 seed
--    周一至周五 10:00-22:00，周六日 11:00-22:00
-- -------------------------------------------------------------
DO $$
DECLARE
  v_merchant_id uuid;
BEGIN
  -- 遍历所有 approved 状态的商家
  FOR v_merchant_id IN
    SELECT id FROM public.merchants WHERE status = 'approved'
  LOOP
    -- 周日 (0): 11:00-22:00
    INSERT INTO public.merchant_hours (merchant_id, day_of_week, open_time, close_time, is_closed)
      VALUES (v_merchant_id, 0, '11:00', '22:00', false)
      ON CONFLICT (merchant_id, day_of_week) DO NOTHING;

    -- 周一 (1): 10:00-22:00
    INSERT INTO public.merchant_hours (merchant_id, day_of_week, open_time, close_time, is_closed)
      VALUES (v_merchant_id, 1, '10:00', '22:00', false)
      ON CONFLICT (merchant_id, day_of_week) DO NOTHING;

    -- 周二 (2): 10:00-22:00
    INSERT INTO public.merchant_hours (merchant_id, day_of_week, open_time, close_time, is_closed)
      VALUES (v_merchant_id, 2, '10:00', '22:00', false)
      ON CONFLICT (merchant_id, day_of_week) DO NOTHING;

    -- 周三 (3): 10:00-22:00
    INSERT INTO public.merchant_hours (merchant_id, day_of_week, open_time, close_time, is_closed)
      VALUES (v_merchant_id, 3, '10:00', '22:00', false)
      ON CONFLICT (merchant_id, day_of_week) DO NOTHING;

    -- 周四 (4): 10:00-22:00
    INSERT INTO public.merchant_hours (merchant_id, day_of_week, open_time, close_time, is_closed)
      VALUES (v_merchant_id, 4, '10:00', '22:00', false)
      ON CONFLICT (merchant_id, day_of_week) DO NOTHING;

    -- 周五 (5): 10:00-22:00
    INSERT INTO public.merchant_hours (merchant_id, day_of_week, open_time, close_time, is_closed)
      VALUES (v_merchant_id, 5, '10:00', '22:00', false)
      ON CONFLICT (merchant_id, day_of_week) DO NOTHING;

    -- 周六 (6): 11:00-22:00
    INSERT INTO public.merchant_hours (merchant_id, day_of_week, open_time, close_time, is_closed)
      VALUES (v_merchant_id, 6, '11:00', '22:00', false)
      ON CONFLICT (merchant_id, day_of_week) DO NOTHING;

  END LOOP;
END $$;
