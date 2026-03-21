-- ============================================================
-- Order System V3: 多 deal 购物车结账 + 双状态 order_items
--
-- 变更摘要:
--   1. 新建 customer_item_status / merchant_item_status enum
--   2. 新建 cart_items 表（DB 持久化购物车，每张券一行）
--   3. 新建 order_items 表（核心，双状态，每张券一行）
--   4. 修改 orders 表（新增 items_amount, service_fee_total, paid_at）
--   5. 修改 coupons 表（新增 order_item_id, coupon_code）
--   6. 新建 store_credits / store_credit_transactions 表
--   7. 修改 refund_requests 表（新增 order_item_id, refund_method）
--   8. 修改 orders.order_number 前缀为 CP-
-- ============================================================


-- ============================================================
-- Step 1: 新建 Enum
-- ============================================================
DO $$ BEGIN
  CREATE TYPE customer_item_status AS ENUM (
    'unused',          -- 未使用，显示 QR Code + Cancel
    'used',            -- 已核销，显示 Refund Request + Write a Review
    'expired',         -- 已过期（auto-refund 处理前瞬态）
    'refund_pending',  -- 退款处理中（原路退，等 Stripe）
    'refund_review',   -- 售后审核中（核销后，商家/管理员审核）
    'refund_reject',   -- 退款被拒
    'refund_success'   -- 退款成功
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE merchant_item_status AS ENUM (
    'unused',          -- 未核销（所有适用门店可见）
    'unpaid',          -- 已核销，待结算（仅核销门店）
    'pending',         -- 结算处理中（仅核销门店）
    'paid',            -- 已结算（仅核销门店）
    'refund_request',  -- 退款申请中（仅核销门店）
    'refund_review',   -- 管理员审核中（仅核销门店）
    'refund_reject',   -- 退款被拒（仅核销门店）
    'refund_success'   -- 退款成功（仅核销门店）
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;


-- ============================================================
-- Step 2: cart_items 表（每张券一行，不合并 quantity）
-- ============================================================
CREATE TABLE IF NOT EXISTS public.cart_items (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id               uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  deal_id               uuid NOT NULL REFERENCES public.deals(id),
  unit_price            numeric(10,2) NOT NULL,  -- 加入时快照单价
  purchased_merchant_id uuid REFERENCES public.merchants(id),
  applicable_store_ids  uuid[],
  selected_options      jsonb,                   -- deal option groups 快照
  created_at            timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_cart_items_user_id ON public.cart_items(user_id);
CREATE INDEX IF NOT EXISTS idx_cart_items_deal_id ON public.cart_items(deal_id);

ALTER TABLE public.cart_items ENABLE ROW LEVEL SECURITY;

-- 用户只能操作自己的购物车
DO $$ BEGIN
  CREATE POLICY "users_manage_own_cart" ON public.cart_items
    FOR ALL USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;


-- ============================================================
-- Step 3: order_items 表
-- ============================================================
CREATE TABLE IF NOT EXISTS public.order_items (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id              uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  deal_id               uuid NOT NULL REFERENCES public.deals(id),
  coupon_id             uuid REFERENCES public.coupons(id),  -- 触发器回填

  -- 金额（单张）
  unit_price            numeric(10,2) NOT NULL,
  service_fee           numeric(10,2) NOT NULL DEFAULT 0,  -- $0.99 / 同 Deal 张数

  -- 门店快照
  purchased_merchant_id uuid REFERENCES public.merchants(id),
  applicable_store_ids  uuid[],

  -- 选项组快照
  selected_options      jsonb,

  -- 核销信息
  redeemed_merchant_id  uuid REFERENCES public.merchants(id),
  redeemed_at           timestamptz,
  redeemed_by           uuid REFERENCES auth.users(id),

  -- 退款信息
  refunded_at           timestamptz,
  refund_reason         text,
  refund_amount         numeric(10,2),
  refund_method         text CHECK (refund_method IN ('store_credit', 'original_payment')),

  -- 双端状态
  customer_status       customer_item_status NOT NULL DEFAULT 'unused',
  merchant_status       merchant_item_status NOT NULL DEFAULT 'unused',

  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_order_items_order_id             ON public.order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_items_deal_id              ON public.order_items(deal_id);
CREATE INDEX IF NOT EXISTS idx_order_items_coupon_id            ON public.order_items(coupon_id);
CREATE INDEX IF NOT EXISTS idx_order_items_customer_status      ON public.order_items(customer_status);
CREATE INDEX IF NOT EXISTS idx_order_items_redeemed_merchant_id ON public.order_items(redeemed_merchant_id);

ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;

-- 用户查看自己的订单项
DO $$ BEGIN
  CREATE POLICY "users_view_own_order_items" ON public.order_items
    FOR SELECT USING (
      order_id IN (SELECT id FROM public.orders WHERE user_id = auth.uid())
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- 商家查看与自己门店相关的订单项
DO $$ BEGIN
  CREATE POLICY "merchant_view_order_items" ON public.order_items
    FOR SELECT USING (
      EXISTS (
        SELECT 1 FROM public.merchant_staff ms
        WHERE ms.user_id = auth.uid()
          AND (
            ms.merchant_id = ANY(order_items.applicable_store_ids)
            OR ms.merchant_id = order_items.purchased_merchant_id
          )
      )
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- service_role 全权限
DO $$ BEGIN
  CREATE POLICY "service_role_all_order_items" ON public.order_items
    FOR ALL TO service_role USING (true) WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- updated_at 自动更新
CREATE OR REPLACE FUNCTION public.set_order_items_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_order_items_updated_at ON public.order_items;
CREATE TRIGGER trg_order_items_updated_at
  BEFORE UPDATE ON public.order_items
  FOR EACH ROW EXECUTE FUNCTION public.set_order_items_updated_at();


-- ============================================================
-- Step 4: 修改 orders 表
-- ============================================================
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS items_amount      numeric(10,2),
  ADD COLUMN IF NOT EXISTS service_fee_total numeric(10,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS paid_at           timestamptz;

-- 更新 order_number 生成表达式（DJ- → CP-）
-- 注意: GENERATED ALWAYS 列不能直接 ALTER，需要 DROP + ADD
-- 但这会影响现有数据，所以我们只对新插入的行生效
-- 实际处理：通过 Edge Function 生成 order_number，不再用 GENERATED 列
-- 暂时保留旧 GENERATED 列不动，新系统不依赖它

-- 标记旧字段为 deprecated（注释）
COMMENT ON COLUMN public.orders.deal_id IS 'DEPRECATED in V3: deal_id moved to order_items';
COMMENT ON COLUMN public.orders.coupon_id IS 'DEPRECATED in V3: coupon created by order_items trigger';
COMMENT ON COLUMN public.orders.quantity IS 'DEPRECATED in V3: each order_item = 1 coupon';
COMMENT ON COLUMN public.orders.unit_price IS 'DEPRECATED in V3: unit_price moved to order_items';
COMMENT ON COLUMN public.orders.is_captured IS 'DEPRECATED in V3: no more manual capture';


-- ============================================================
-- Step 5: 修改 coupons 表
-- ============================================================
ALTER TABLE public.coupons
  ADD COLUMN IF NOT EXISTS order_item_id uuid
    REFERENCES public.order_items(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS coupon_code char(16) UNIQUE;

-- 为现有 coupons 补充 coupon_code（16 位随机字母数字）
UPDATE public.coupons
SET coupon_code = UPPER(SUBSTRING(REPLACE(gen_random_uuid()::text, '-', ''), 1, 16))
WHERE coupon_code IS NULL;


-- ============================================================
-- Step 6: store_credits + store_credit_transactions 表
-- ============================================================
CREATE TABLE IF NOT EXISTS public.store_credits (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE UNIQUE,
  amount     numeric(10,2) NOT NULL DEFAULT 0 CHECK (amount >= 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.store_credits ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "users_view_own_credits" ON public.store_credits
    FOR SELECT USING (user_id = auth.uid());
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "service_role_all_credits" ON public.store_credits
    FOR ALL TO service_role USING (true) WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS public.store_credit_transactions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES public.users(id),
  order_item_id   uuid REFERENCES public.order_items(id),
  amount          numeric(10,2) NOT NULL,  -- 正数=增加，负数=扣减
  type            text NOT NULL CHECK (type IN ('refund_credit', 'purchase_deduction')),
  description     text,
  created_at      timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.store_credit_transactions ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "users_view_own_sct" ON public.store_credit_transactions
    FOR SELECT USING (user_id = auth.uid());
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "service_role_all_sct" ON public.store_credit_transactions
    FOR ALL TO service_role USING (true) WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;


-- ============================================================
-- Step 7: 修改 refund_requests 表
-- ============================================================
ALTER TABLE public.refund_requests
  ADD COLUMN IF NOT EXISTS order_item_id uuid
    REFERENCES public.order_items(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS refund_method text
    CHECK (refund_method IN ('store_credit', 'original_payment'));
