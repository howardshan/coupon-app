-- =============================================================
-- Platform Subscription 追踪
-- 为每个商家存储：v2 账号创建时间、平台订阅 ID、订阅状态
-- =============================================================

-- ── 1. merchants 表扩展 ────────────────────────────────────────
ALTER TABLE public.merchants
  ADD COLUMN IF NOT EXISTS stripe_v2_account_id         TEXT,
  ADD COLUMN IF NOT EXISTS stripe_v2_onboarding_url     TEXT,
  ADD COLUMN IF NOT EXISTS stripe_v2_onboarding_expires timestamptz,
  ADD COLUMN IF NOT EXISTS stripe_platform_sub_id       TEXT,
  ADD COLUMN IF NOT EXISTS stripe_platform_sub_status   TEXT DEFAULT 'none';

COMMENT ON COLUMN public.merchants.stripe_v2_account_id         IS 'Accounts v2 API で作成した connected account id (acct_xxx)';
COMMENT ON COLUMN public.merchants.stripe_v2_onboarding_url     IS '直近に発行した account link URL';
COMMENT ON COLUMN public.merchants.stripe_v2_onboarding_expires IS 'account link の有効期限';
COMMENT ON COLUMN public.merchants.stripe_platform_sub_id       IS '平台向け月額サブスクリプション ID (sub_xxx)';
COMMENT ON COLUMN public.merchants.stripe_platform_sub_status   IS 'none | incomplete | active | past_due | canceled';

-- ── 2. brands 表にも同じ列を追加（ブランド単位での課金用）──────
ALTER TABLE public.brands
  ADD COLUMN IF NOT EXISTS stripe_v2_account_id         TEXT,
  ADD COLUMN IF NOT EXISTS stripe_platform_sub_id       TEXT,
  ADD COLUMN IF NOT EXISTS stripe_platform_sub_status   TEXT DEFAULT 'none';

-- ── 3. platform_subscription_product: 一行テーブル（商品設定）─
CREATE TABLE IF NOT EXISTS public.platform_subscription_product (
  id           int PRIMARY KEY DEFAULT 1,
  stripe_product_id TEXT NOT NULL,
  stripe_price_id   TEXT NOT NULL,
  unit_amount       int  NOT NULL DEFAULT 1000, -- セント
  currency          text NOT NULL DEFAULT 'usd',
  interval          text NOT NULL DEFAULT 'month',
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT platform_subscription_product_single_row CHECK (id = 1)
);

ALTER TABLE public.platform_subscription_product ENABLE ROW LEVEL SECURITY;

-- service_role のみ操作可
CREATE POLICY "platform_subscription_product_service_role"
  ON public.platform_subscription_product FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- admin も読み取り可（管理画面用）
CREATE POLICY "platform_subscription_product_admin_read"
  ON public.platform_subscription_product FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE id = auth.uid() AND role = 'admin'
    )
  );
