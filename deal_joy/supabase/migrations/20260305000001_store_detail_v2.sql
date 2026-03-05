-- =============================================================
-- 商家详情页 V2：头图模式 + Deal 分类 + Deal 类型扩展
-- =============================================================

-- -------------------------------------------------------------
-- 1. merchants 表新增头图模式字段
-- -------------------------------------------------------------
ALTER TABLE public.merchants
  ADD COLUMN IF NOT EXISTS header_photo_style text NOT NULL DEFAULT 'single',
  ADD COLUMN IF NOT EXISTS header_photos text[] DEFAULT '{}';

-- header_photo_style: 'single'（轮播）或 'triple'（三图并排）
-- header_photos: triple 模式存 3 张 URL

-- -------------------------------------------------------------
-- 2. deal_categories 表（商家自定义 Deal 分类）
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.deal_categories (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id   uuid        NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  name          text        NOT NULL,
  sort_order    int         NOT NULL DEFAULT 0,
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_deal_categories_merchant
  ON public.deal_categories(merchant_id, sort_order);

ALTER TABLE public.deal_categories ENABLE ROW LEVEL SECURITY;

-- 已审批商家的分类公开可读
DROP POLICY IF EXISTS "deal_categories_read" ON public.deal_categories;
CREATE POLICY "deal_categories_read" ON public.deal_categories
  FOR SELECT USING (true);

-- 商家管理自己的分类
DROP POLICY IF EXISTS "deal_categories_manage_own" ON public.deal_categories;
CREATE POLICY "deal_categories_manage_own" ON public.deal_categories
  FOR ALL USING (
    merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid())
  );

-- -------------------------------------------------------------
-- 3. deals 表新增字段
-- -------------------------------------------------------------
ALTER TABLE public.deals
  ADD COLUMN IF NOT EXISTS deal_type text NOT NULL DEFAULT 'regular',
  ADD COLUMN IF NOT EXISTS deal_category_id uuid REFERENCES public.deal_categories(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS badge_text text;

-- deal_type: 'voucher'（代金券）| 'regular'（普通套餐/单品）
-- badge_text: 自定义角标，如 "Best Value", "New"

CREATE INDEX IF NOT EXISTS idx_deals_category
  ON public.deals(deal_category_id);

-- -------------------------------------------------------------
-- 4. 种子数据
-- -------------------------------------------------------------
DO $$
DECLARE
  v_m1 uuid; -- Texas BBQ House
  v_m2 uuid; -- Hot Pot Paradise
  v_m3 uuid; -- Sakura Sushi Bar
  v_cat1 uuid;
  v_cat2 uuid;
  v_cat3 uuid;
  v_cat4 uuid;
  v_cat5 uuid;
  v_cat6 uuid;
  v_cat7 uuid;
  v_cat8 uuid;
BEGIN
  SELECT id INTO v_m1 FROM public.merchants WHERE name = 'Texas BBQ House' LIMIT 1;
  SELECT id INTO v_m2 FROM public.merchants WHERE name = 'Hot Pot Paradise' LIMIT 1;
  SELECT id INTO v_m3 FROM public.merchants WHERE name = 'Sakura Sushi Bar' LIMIT 1;

  IF v_m1 IS NULL THEN RETURN; END IF;

  -- ── 更新商家头图模式 ──────────────────────────────
  -- Texas BBQ House: triple 模式（使用已有门店照片）
  UPDATE public.merchants SET
    header_photo_style = 'triple',
    header_photos = ARRAY[
      'https://images.unsplash.com/photo-1555396273-367ea4eb4db5?w=800',
      'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?w=800',
      'https://images.unsplash.com/photo-1552566626-52f8b828add9?w=800'
    ]
  WHERE id = v_m1;

  -- Hot Pot Paradise: single 模式（默认轮播）
  UPDATE public.merchants SET
    header_photo_style = 'single',
    header_photos = '{}'
  WHERE id = v_m2;

  -- Sakura Sushi Bar: triple 模式
  UPDATE public.merchants SET
    header_photo_style = 'triple',
    header_photos = ARRAY[
      'https://images.unsplash.com/photo-1579027989536-b7b1f875659b?w=800',
      'https://images.unsplash.com/photo-1553621042-f6e147245754?w=800',
      'https://images.unsplash.com/photo-1540914124281-342587941389?w=800'
    ]
  WHERE id = v_m3;

  -- ── Deal 分类 ──────────────────────────────────────
  -- Texas BBQ House 分类
  INSERT INTO public.deal_categories (id, merchant_id, name, sort_order) VALUES
    (gen_random_uuid(), v_m1, 'Combo Sets', 0),
    (gen_random_uuid(), v_m1, 'Single Items', 1),
    (gen_random_uuid(), v_m1, 'Family Packs', 2);

  SELECT id INTO v_cat1 FROM public.deal_categories WHERE merchant_id = v_m1 AND name = 'Combo Sets' LIMIT 1;
  SELECT id INTO v_cat2 FROM public.deal_categories WHERE merchant_id = v_m1 AND name = 'Single Items' LIMIT 1;
  SELECT id INTO v_cat3 FROM public.deal_categories WHERE merchant_id = v_m1 AND name = 'Family Packs' LIMIT 1;

  -- Hot Pot Paradise 分类
  INSERT INTO public.deal_categories (merchant_id, name, sort_order) VALUES
    (v_m2, 'Couple Set', 0),
    (v_m2, 'Group Set', 1),
    (v_m2, 'Single Items', 2);

  SELECT id INTO v_cat4 FROM public.deal_categories WHERE merchant_id = v_m2 AND name = 'Couple Set' LIMIT 1;
  SELECT id INTO v_cat5 FROM public.deal_categories WHERE merchant_id = v_m2 AND name = 'Group Set' LIMIT 1;
  SELECT id INTO v_cat6 FROM public.deal_categories WHERE merchant_id = v_m2 AND name = 'Single Items' LIMIT 1;

  -- Sakura Sushi Bar 分类
  INSERT INTO public.deal_categories (merchant_id, name, sort_order) VALUES
    (v_m3, 'Omakase', 0),
    (v_m3, 'Roll Combos', 1);

  SELECT id INTO v_cat7 FROM public.deal_categories WHERE merchant_id = v_m3 AND name = 'Omakase' LIMIT 1;
  SELECT id INTO v_cat8 FROM public.deal_categories WHERE merchant_id = v_m3 AND name = 'Roll Combos' LIMIT 1;

  -- ── 更新现有 deals 的类型和分类 ──────────────────────
  -- 给每个商家的第一个 deal 设为 voucher 类型
  UPDATE public.deals SET
    deal_type = 'voucher',
    badge_text = NULL
  WHERE merchant_id = v_m1
    AND id = (SELECT id FROM public.deals WHERE merchant_id = v_m1 ORDER BY created_at ASC LIMIT 1);

  UPDATE public.deals SET
    deal_type = 'voucher',
    badge_text = NULL
  WHERE merchant_id = v_m2
    AND id = (SELECT id FROM public.deals WHERE merchant_id = v_m2 ORDER BY created_at ASC LIMIT 1);

  -- 给其余 deals 分配分类和角标
  UPDATE public.deals SET
    deal_type = 'regular',
    deal_category_id = v_cat1,
    badge_text = 'Best Value'
  WHERE merchant_id = v_m1
    AND deal_type = 'regular'
    AND id = (SELECT id FROM public.deals WHERE merchant_id = v_m1 AND deal_type = 'regular' ORDER BY created_at ASC LIMIT 1);

  UPDATE public.deals SET
    deal_type = 'regular',
    deal_category_id = v_cat2
  WHERE merchant_id = v_m1
    AND deal_type = 'regular'
    AND deal_category_id IS NULL
    AND id = (SELECT id FROM public.deals WHERE merchant_id = v_m1 AND deal_type = 'regular' AND deal_category_id IS NULL ORDER BY created_at ASC LIMIT 1);

  UPDATE public.deals SET
    deal_type = 'regular',
    deal_category_id = v_cat4,
    badge_text = 'Popular'
  WHERE merchant_id = v_m2
    AND deal_type = 'regular'
    AND id = (SELECT id FROM public.deals WHERE merchant_id = v_m2 AND deal_type = 'regular' ORDER BY created_at ASC LIMIT 1);

  UPDATE public.deals SET
    deal_type = 'regular',
    deal_category_id = v_cat5,
    badge_text = 'New'
  WHERE merchant_id = v_m2
    AND deal_type = 'regular'
    AND deal_category_id IS NULL
    AND id = (SELECT id FROM public.deals WHERE merchant_id = v_m2 AND deal_type = 'regular' AND deal_category_id IS NULL ORDER BY created_at ASC LIMIT 1);

  UPDATE public.deals SET
    deal_type = 'regular',
    deal_category_id = v_cat7
  WHERE merchant_id = v_m3
    AND id = (SELECT id FROM public.deals WHERE merchant_id = v_m3 ORDER BY created_at ASC LIMIT 1 OFFSET 1);

  UPDATE public.deals SET
    deal_type = 'regular',
    deal_category_id = v_cat8,
    badge_text = 'Chef Pick'
  WHERE merchant_id = v_m3
    AND deal_category_id IS NULL
    AND id = (SELECT id FROM public.deals WHERE merchant_id = v_m3 AND deal_category_id IS NULL ORDER BY created_at ASC LIMIT 1);

END $$;
