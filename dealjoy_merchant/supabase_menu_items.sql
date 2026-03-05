-- 创建 menu_items 表（商家菜品/商品管理）
-- 在 Supabase SQL Editor 中执行此脚本

CREATE TABLE IF NOT EXISTS public.menu_items (
  id                   uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id          uuid        NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  name                 text        NOT NULL,
  image_url            text,
  price                numeric(8,2),
  -- category 取值: 'signature' | 'popular' | 'regular'
  category             text        NOT NULL DEFAULT 'regular',
  -- status 取值: 'active' | 'inactive'
  status               text        NOT NULL DEFAULT 'active',
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

-- 商家端：管理自己的菜品（增删改查）
CREATE POLICY "menu_items_manage_own" ON public.menu_items
  FOR ALL USING (
    merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid())
  );
