-- =============================================================
-- Migration: 5.团购券核销 — 核销相关表结构
-- 创建时间: 2026-03-03
-- 说明: 给 coupons 表补充核销字段，新建 redemption_log 审计表
-- =============================================================

-- -------------------------------------------------------------
-- 1. coupons 表补充核销相关字段
-- -------------------------------------------------------------

-- 核销时间（核销时写入，撤销时清空）
ALTER TABLE public.coupons
  ADD COLUMN IF NOT EXISTS redeemed_at timestamptz;

-- 执行核销的商家ID
ALTER TABLE public.coupons
  ADD COLUMN IF NOT EXISTS redeemed_by_merchant_id uuid
    REFERENCES public.merchants(id);

-- 撤销时间（NULL 表示未撤销，有值表示已撤销）
ALTER TABLE public.coupons
  ADD COLUMN IF NOT EXISTS reverted_at timestamptz;

-- 为新字段添加索引
CREATE INDEX IF NOT EXISTS idx_coupons_redeemed_at
  ON public.coupons(redeemed_at)
  WHERE redeemed_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_coupons_redeemed_by_merchant_id
  ON public.coupons(redeemed_by_merchant_id)
  WHERE redeemed_by_merchant_id IS NOT NULL;

-- -------------------------------------------------------------
-- 2. 新建 redemption_log 核销操作审计日志表
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.redemption_log (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  coupon_id       uuid NOT NULL REFERENCES public.coupons(id) ON DELETE CASCADE,
  merchant_id     uuid NOT NULL REFERENCES public.merchants(id),
  -- 操作类型: redeem=核销, revert=撤销核销
  action          text NOT NULL CHECK (action IN ('redeem', 'revert')),
  actor_user_id   uuid NOT NULL REFERENCES auth.users(id),
  created_at      timestamptz NOT NULL DEFAULT now()
);

-- 索引：按券ID查询某张券的操作历史
CREATE INDEX IF NOT EXISTS idx_redemption_log_coupon_id
  ON public.redemption_log(coupon_id);

-- 索引：按商家查询所有核销记录（核销历史页面主查询）
CREATE INDEX IF NOT EXISTS idx_redemption_log_merchant_id
  ON public.redemption_log(merchant_id);

-- 索引：按时间倒序（历史列表默认排序）
CREATE INDEX IF NOT EXISTS idx_redemption_log_created_at
  ON public.redemption_log(created_at DESC);

-- -------------------------------------------------------------
-- 3. RLS — redemption_log 行级安全策略
-- -------------------------------------------------------------
ALTER TABLE public.redemption_log ENABLE ROW LEVEL SECURITY;

-- 商家只能查看自己门店的核销日志
CREATE POLICY "redemption_log_merchant_select"
  ON public.redemption_log
  FOR SELECT
  USING (
    merchant_id IN (
      SELECT id FROM public.merchants WHERE user_id = auth.uid()
    )
  );

-- 商家只能插入自己门店的核销记录
-- 注意：实际写入由 Edge Function（service_role）完成，此策略作为安全兜底
CREATE POLICY "redemption_log_merchant_insert"
  ON public.redemption_log
  FOR INSERT
  WITH CHECK (
    merchant_id IN (
      SELECT id FROM public.merchants WHERE user_id = auth.uid()
    )
  );

-- -------------------------------------------------------------
-- 4. coupons 表补充 RLS 策略
-- 原有 coupons_merchant_scan 策略已支持商家 UPDATE
-- 补充：商家可以 SELECT 自己门店的券（用于核销确认页展示券信息）
-- -------------------------------------------------------------

-- 检查是否已存在商家查询券的策略，不存在则创建
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'coupons'
      AND policyname = 'coupons_merchant_select'
  ) THEN
    CREATE POLICY "coupons_merchant_select"
      ON public.coupons
      FOR SELECT
      USING (
        merchant_id IN (
          SELECT id FROM public.merchants WHERE user_id = auth.uid()
        )
      );
  END IF;
END $$;
