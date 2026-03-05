-- 创建 menu_categories 表（商家自定义菜品分类）
-- 在 Supabase SQL Editor 中执行此脚本

-- ============================================================
-- 1. 创建 menu_categories 表
-- ============================================================
CREATE TABLE IF NOT EXISTS public.menu_categories (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id uuid        NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  name        text        NOT NULL,
  sort_order  int         NOT NULL DEFAULT 0,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_menu_categories_merchant
  ON public.menu_categories(merchant_id);

-- 同一商家下分类名不能重复
CREATE UNIQUE INDEX IF NOT EXISTS idx_menu_categories_unique_name
  ON public.menu_categories(merchant_id, name);

ALTER TABLE public.menu_categories ENABLE ROW LEVEL SECURITY;

-- 用户端：已审批商家的分类公开可读
CREATE POLICY "menu_categories_read_approved" ON public.menu_categories
  FOR SELECT USING (
    merchant_id IN (SELECT id FROM public.merchants WHERE status = 'approved')
  );

-- 商家端：管理自己的分类
CREATE POLICY "menu_categories_manage_own" ON public.menu_categories
  FOR ALL USING (
    merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid())
  );

-- ============================================================
-- 2. 为 menu_items 添加 category_id 外键
-- ============================================================
ALTER TABLE public.menu_items
  ADD COLUMN IF NOT EXISTS category_id uuid REFERENCES public.menu_categories(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_menu_items_category_id
  ON public.menu_items(category_id);
