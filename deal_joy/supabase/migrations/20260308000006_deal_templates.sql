-- ============================================================
-- V2.2 Deal 模板 — 一键多店发布
-- deal_templates 表 + deals.deal_template_id 关联字段
-- ============================================================

-- 1. Deal 模板表
CREATE TABLE IF NOT EXISTS public.deal_templates (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  brand_id      UUID NOT NULL REFERENCES public.brands(id) ON DELETE CASCADE,
  created_by    UUID NOT NULL REFERENCES auth.users(id),
  title         TEXT NOT NULL,
  description   TEXT NOT NULL DEFAULT '',
  category      TEXT NOT NULL DEFAULT '',
  original_price DECIMAL NOT NULL DEFAULT 0,
  discount_price DECIMAL NOT NULL DEFAULT 0,
  discount_label TEXT DEFAULT '',
  stock_limit   INT DEFAULT 100,
  package_contents TEXT DEFAULT '',
  usage_notes   TEXT DEFAULT '',
  usage_days    TEXT[] DEFAULT '{}',
  max_per_person INT,
  is_stackable  BOOL DEFAULT true,
  validity_type TEXT DEFAULT 'fixed_date',   -- 'fixed_date' | 'days_after_purchase'
  validity_days INT DEFAULT 30,
  refund_policy TEXT DEFAULT 'Refund anytime before use, refund when expired',
  image_urls    TEXT[] DEFAULT '{}',
  dishes        JSONB DEFAULT '[]',
  deal_type     TEXT DEFAULT 'regular',
  badge_text    TEXT,
  deal_category_id UUID,
  is_active     BOOL DEFAULT true,
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  updated_at    TIMESTAMPTZ DEFAULT NOW()
);

-- 2. deals 表新增 deal_template_id 关联字段
ALTER TABLE public.deals ADD COLUMN IF NOT EXISTS deal_template_id UUID REFERENCES public.deal_templates(id) ON DELETE SET NULL;

-- 3. 模板关联的门店（哪些门店已发布该模板）
CREATE TABLE IF NOT EXISTS public.deal_template_stores (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  template_id   UUID NOT NULL REFERENCES public.deal_templates(id) ON DELETE CASCADE,
  merchant_id   UUID NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  deal_id       UUID REFERENCES public.deals(id) ON DELETE SET NULL,  -- 该门店对应的 deal 记录
  is_customized BOOL DEFAULT false,  -- 门店是否自行修改过（不再跟随模板同步）
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(template_id, merchant_id)
);

-- 4. RLS 策略
ALTER TABLE public.deal_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.deal_template_stores ENABLE ROW LEVEL SECURITY;

-- deal_templates: 品牌管理员可读写
CREATE POLICY "deal_templates_brand_admin_select" ON public.deal_templates
  FOR SELECT TO authenticated
  USING (
    brand_id IN (
      SELECT brand_id FROM public.brand_admins WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "deal_templates_brand_admin_insert" ON public.deal_templates
  FOR INSERT TO authenticated
  WITH CHECK (
    brand_id IN (
      SELECT brand_id FROM public.brand_admins WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "deal_templates_brand_admin_update" ON public.deal_templates
  FOR UPDATE TO authenticated
  USING (
    brand_id IN (
      SELECT brand_id FROM public.brand_admins WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "deal_templates_brand_admin_delete" ON public.deal_templates
  FOR DELETE TO authenticated
  USING (
    brand_id IN (
      SELECT brand_id FROM public.brand_admins WHERE user_id = auth.uid()
    )
  );

-- deal_template_stores: 品牌管理员可读写
CREATE POLICY "deal_template_stores_brand_admin_select" ON public.deal_template_stores
  FOR SELECT TO authenticated
  USING (
    template_id IN (
      SELECT dt.id FROM public.deal_templates dt
      JOIN public.brand_admins ba ON ba.brand_id = dt.brand_id
      WHERE ba.user_id = auth.uid()
    )
  );

CREATE POLICY "deal_template_stores_brand_admin_all" ON public.deal_template_stores
  FOR ALL TO authenticated
  USING (
    template_id IN (
      SELECT dt.id FROM public.deal_templates dt
      JOIN public.brand_admins ba ON ba.brand_id = dt.brand_id
      WHERE ba.user_id = auth.uid()
    )
  );

-- 5. 索引
CREATE INDEX IF NOT EXISTS idx_deal_templates_brand_id ON public.deal_templates(brand_id);
CREATE INDEX IF NOT EXISTS idx_deals_deal_template_id ON public.deals(deal_template_id);
CREATE INDEX IF NOT EXISTS idx_deal_template_stores_template_id ON public.deal_template_stores(template_id);
