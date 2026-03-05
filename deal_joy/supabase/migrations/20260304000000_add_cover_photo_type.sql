-- =============================================================
-- 新增 cover 照片类型 + 放宽 storefront 上限
-- cover: 店铺详情页顶部轮播封面照（最多5张）
-- storefront: 门头照（从1张放宽到3张，由 Edge Function 校验）
-- =============================================================

-- 放宽 photo_type CHECK 约束，新增 'cover' 类型
ALTER TABLE public.merchant_photos
  DROP CONSTRAINT IF EXISTS merchant_photos_photo_type_check;

ALTER TABLE public.merchant_photos
  ADD CONSTRAINT merchant_photos_photo_type_check
  CHECK (photo_type IN ('storefront', 'environment', 'product', 'cover'));
