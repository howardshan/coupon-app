-- 商家自定义菜品分类 + menu_items 上架状态（与 dealjoy_merchant 一致）
-- 若已在 SQL Editor 执行过 dealjoy_merchant/supabase_menu_categories.sql，本迁移为幂等补全

-- 1) menu_categories
CREATE TABLE IF NOT EXISTS public.menu_categories (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id uuid        NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  name        text        NOT NULL,
  sort_order  int         NOT NULL DEFAULT 0,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_menu_categories_merchant
  ON public.menu_categories(merchant_id);

CREATE UNIQUE INDEX IF NOT EXISTS idx_menu_categories_unique_name
  ON public.menu_categories(merchant_id, name);

ALTER TABLE public.menu_categories ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "menu_categories_read_approved" ON public.menu_categories;
CREATE POLICY "menu_categories_read_approved" ON public.menu_categories
  FOR SELECT USING (
    merchant_id IN (SELECT id FROM public.merchants WHERE status = 'approved')
  );

DROP POLICY IF EXISTS "menu_categories_manage_own" ON public.menu_categories;
CREATE POLICY "menu_categories_manage_own" ON public.menu_categories
  FOR ALL USING (
    merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid())
  );

-- 2) menu_items.category_id
ALTER TABLE public.menu_items
  ADD COLUMN IF NOT EXISTS category_id uuid REFERENCES public.menu_categories(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_menu_items_category_id
  ON public.menu_items(category_id);

-- 3) menu_items.status（active = 在售，inactive = 下架）
ALTER TABLE public.menu_items
  ADD COLUMN IF NOT EXISTS status text;

UPDATE public.menu_items
SET status = 'active'
WHERE status IS NULL OR trim(status) NOT IN ('active', 'inactive');

ALTER TABLE public.menu_items ALTER COLUMN status SET DEFAULT 'active';
ALTER TABLE public.menu_items ALTER COLUMN status SET NOT NULL;

ALTER TABLE public.menu_items DROP CONSTRAINT IF EXISTS menu_items_status_check;
ALTER TABLE public.menu_items
  ADD CONSTRAINT menu_items_status_check CHECK (status IN ('active', 'inactive'));
