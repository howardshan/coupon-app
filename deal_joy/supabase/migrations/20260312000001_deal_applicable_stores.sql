-- ============================================================
-- deal_applicable_stores 表
-- 替代 deals.applicable_merchant_ids 数组字段，支持 per-store 状态追踪
-- ============================================================

-- 1. 枚举类型
CREATE TYPE deal_store_scope AS ENUM (
  'store_only',         -- 独立门店 Deal 或品牌下单店自建 Deal
  'brand_multi_store'   -- 品牌多店通用 Deal
);

CREATE TYPE deal_store_status AS ENUM (
  'active',                       -- 门店已确认，Deal 上线，用户可见
  'pending_store_confirmation',   -- 等待门店老板/店长确认
  'declined',                     -- 门店拒绝参与此 Deal
  'removed'                       -- 门店主动退出或被品牌踢出
);

-- 2. 创建 deal_applicable_stores 表
CREATE TABLE public.deal_applicable_stores (
  id                   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  deal_id              UUID        NOT NULL REFERENCES public.deals(id) ON DELETE CASCADE,
  store_id             UUID        NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  menu_item_id         UUID        REFERENCES public.menu_items(id) ON DELETE SET NULL,
  deal_scope           deal_store_scope  NOT NULL,
  status               deal_store_status NOT NULL DEFAULT 'pending_store_confirmation',
  -- 冗余存储门店原价，防止菜品改价后影响已上线 Deal 的折扣显示
  store_original_price NUMERIC(10,2),

  created_by           UUID        REFERENCES auth.users(id),
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- Accept 或 Decline 操作人和时间
  confirmed_by         UUID        REFERENCES auth.users(id),
  confirmed_at         TIMESTAMPTZ,

  -- 门店退出操作人和时间（主动退出或被品牌踢出）
  removed_by           UUID        REFERENCES auth.users(id),
  removed_at           TIMESTAMPTZ,

  UNIQUE (deal_id, store_id)
);

-- 3. 索引
CREATE INDEX idx_das_deal_id  ON public.deal_applicable_stores(deal_id);
CREATE INDEX idx_das_store_id ON public.deal_applicable_stores(store_id);
CREATE INDEX idx_das_status   ON public.deal_applicable_stores(status);
-- 快速查询某门店所有待确认 Deal
CREATE INDEX idx_das_pending  ON public.deal_applicable_stores(store_id, status)
  WHERE status = 'pending_store_confirmation';
-- 快速查询某个 Deal 的 active 门店（用户端展示）
CREATE INDEX idx_das_active   ON public.deal_applicable_stores(deal_id, status)
  WHERE status = 'active';

-- 4. RLS
ALTER TABLE public.deal_applicable_stores ENABLE ROW LEVEL SECURITY;

-- 门店用户可查看自己门店的记录（包括 pending 通知）
CREATE POLICY "das_store_select_own"
  ON public.deal_applicable_stores FOR SELECT
  USING (
    store_id IN (
      SELECT id FROM public.merchants WHERE user_id = auth.uid()
    )
  );

-- 门店用户可更新自己门店的记录（Accept / Decline / Remove）
CREATE POLICY "das_store_update_own"
  ON public.deal_applicable_stores FOR UPDATE
  USING (
    store_id IN (
      SELECT id FROM public.merchants WHERE user_id = auth.uid()
    )
  );

-- 品牌管理员可查看自己品牌下所有门店的记录
CREATE POLICY "das_brand_admin_select"
  ON public.deal_applicable_stores FOR SELECT
  USING (
    store_id IN (
      SELECT m.id
      FROM public.merchants m
      JOIN public.brand_admins ba ON ba.brand_id = m.brand_id
      WHERE ba.user_id = auth.uid()
    )
  );

-- 用户端可查看 active 记录（Deal 详情页展示适用门店）
CREATE POLICY "das_public_select_active"
  ON public.deal_applicable_stores FOR SELECT
  USING (status = 'active');

-- 5. 数据迁移：把现有 deals 表的 applicable_merchant_ids 数组转为表记录
--    store_only deals（applicable_merchant_ids IS NULL）→ 1 条 active 记录
INSERT INTO public.deal_applicable_stores (deal_id, store_id, deal_scope, status, created_at)
SELECT
  d.id,
  d.merchant_id,
  'store_only'::deal_store_scope,
  'active'::deal_store_status,
  d.created_at
FROM public.deals d
WHERE d.applicable_merchant_ids IS NULL
ON CONFLICT (deal_id, store_id) DO NOTHING;

--    brand_multi_store deals（applicable_merchant_ids IS NOT NULL）→ 每个门店一条 active 记录
INSERT INTO public.deal_applicable_stores (deal_id, store_id, deal_scope, status, created_at)
SELECT
  d.id,
  unnest(d.applicable_merchant_ids),
  'brand_multi_store'::deal_store_scope,
  'active'::deal_store_status,
  d.created_at
FROM public.deals d
WHERE d.applicable_merchant_ids IS NOT NULL
ON CONFLICT (deal_id, store_id) DO NOTHING;

-- 6. pg_cron：每小时检查，超过 48 小时未处理的 pending → 自动 Decline
-- 注意：需确保 Supabase 项目已启用 pg_cron 扩展
SELECT cron.schedule(
  'auto-decline-pending-stores',
  '0 * * * *',
  $$
  UPDATE public.deal_applicable_stores
  SET
    status       = 'declined'::deal_store_status,
    confirmed_at = now()
  WHERE status = 'pending_store_confirmation'
    AND created_at < now() - INTERVAL '48 hours';
  $$
);
