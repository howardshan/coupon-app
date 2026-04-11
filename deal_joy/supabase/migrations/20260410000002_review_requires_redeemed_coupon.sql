-- ============================================================================
-- 评价资格校验：只有"购买并核销过 coupon"的用户才能为该 deal 写评价
--
-- 问题背景：
-- 原有 RLS 策略 reviews_insert_own 只校验 auth.uid() = user_id，
-- 任何登录用户都可以对任意 deal 发起 review，绕过购买/核销前置条件。
--
-- 修复方案：
-- 更新 INSERT 策略，要求 coupons 表中存在
--   (user_id = auth.uid(), deal_id = NEW.deal_id, status = 'used')
-- 的记录。
-- ============================================================================

-- 删除旧策略
DROP POLICY IF EXISTS "reviews_insert_own" ON public.reviews;

-- 新策略：必须持有已核销的 coupon 才能写评价
CREATE POLICY "reviews_insert_own_with_redeemed_coupon" ON public.reviews
  FOR INSERT
  WITH CHECK (
    auth.uid() = user_id
    AND EXISTS (
      SELECT 1
      FROM public.coupons c
      WHERE c.user_id = auth.uid()
        AND c.deal_id = reviews.deal_id
        AND c.status = 'used'
    )
  );

COMMENT ON POLICY "reviews_insert_own_with_redeemed_coupon" ON public.reviews IS
  '只有持有已核销（status=used）coupon 的用户才能写对应 deal 的评价。防止未购买用户刷评价。';
