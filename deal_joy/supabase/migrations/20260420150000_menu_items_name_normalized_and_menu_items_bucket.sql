-- menu_items：规范化名、唯一约束、历史去重、menu-items 存储桶
-- 规则与 admin/lib/menu-item-name.ts 中 normalizeMenuItemName 一致：trim、去掉最后一个「.」及之后（扩展名）、大小写敏感

-- 1) 规范化函数
CREATE OR REPLACE FUNCTION public.normalize_menu_item_name(p_input text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_input IS NULL THEN ''
    WHEN btrim(p_input) = '' THEN ''
    ELSE
      regexp_replace(btrim(p_input), '\.[^.]+$', '')
  END;
$$;

COMMENT ON FUNCTION public.normalize_menu_item_name(text) IS
'商品名/文件名规范化：trim 后去掉最后一个点及后缀；与 admin normalizeMenuItemName 对齐。';

-- 2) 列与初次回填
ALTER TABLE public.menu_items
  ADD COLUMN IF NOT EXISTS name_normalized text;

UPDATE public.menu_items
SET name_normalized = public.normalize_menu_item_name(name)
WHERE name_normalized IS NULL
   OR name_normalized <> public.normalize_menu_item_name(name);

-- 3) 同步触发器（先于去重，使去重时只改 name 即可）
CREATE OR REPLACE FUNCTION public.menu_items_sync_name_normalized()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.name_normalized := public.normalize_menu_item_name(NEW.name);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_menu_items_sync_name_normalized ON public.menu_items;
CREATE TRIGGER trg_menu_items_sync_name_normalized
  BEFORE INSERT OR UPDATE OF name ON public.menu_items
  FOR EACH ROW
  EXECUTE FUNCTION public.menu_items_sync_name_normalized();

-- 4) 去重：同一 merchant 下 name_normalized 相同则保留先创建的一条，其余在 name 上附加 id 段（触发器会重算 name_normalized）
UPDATE public.menu_items mi
SET
  name = mi.name
    || ' ['
    || substr(replace(mi.id::text, '-', ''), 1, 8)
    || ']'
WHERE mi.id IN (
  SELECT id
  FROM (
    SELECT
      id,
      row_number() OVER (
        PARTITION BY merchant_id, name_normalized
        ORDER BY created_at ASC, id ASC
      ) AS rn
    FROM public.menu_items
  ) x
  WHERE x.rn > 1
);

-- 5) 非空 + 唯一
ALTER TABLE public.menu_items
  ALTER COLUMN name_normalized SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_menu_items_merchant_name_normalized
  ON public.menu_items (merchant_id, name_normalized);

-- 6) Storage：menu-items 公开读，商家可写自己 merchant_id 路径；管理端用 service_role 无 RLS
INSERT INTO storage.buckets (id, name, public)
VALUES ('menu-items', 'menu-items', true)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "menu_items_bucket_public_read" ON storage.objects;
CREATE POLICY "menu_items_bucket_public_read"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'menu-items');

DROP POLICY IF EXISTS "menu_items_bucket_merchant_write" ON storage.objects;
CREATE POLICY "menu_items_bucket_merchant_write"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'menu-items'
    AND auth.role() = 'authenticated'
    AND (storage.foldername(name))[1] IN (
      SELECT m.id::text FROM public.merchants m WHERE m.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "menu_items_bucket_merchant_update" ON storage.objects;
CREATE POLICY "menu_items_bucket_merchant_update"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'menu-items'
    AND auth.role() = 'authenticated'
    AND (storage.foldername(name))[1] IN (
      SELECT m.id::text FROM public.merchants m WHERE m.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "menu_items_bucket_merchant_delete" ON storage.objects;
CREATE POLICY "menu_items_bucket_merchant_delete"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'menu-items'
    AND auth.role() = 'authenticated'
    AND (storage.foldername(name))[1] IN (
      SELECT m.id::text FROM public.merchants m WHERE m.user_id = auth.uid()
    )
  );
