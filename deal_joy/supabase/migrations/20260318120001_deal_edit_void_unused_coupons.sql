-- 克隆编辑 Deal 后：旧 Deal 未用券作废 merchant_edit；订单 voided
ALTER TYPE public.coupon_status ADD VALUE IF NOT EXISTS 'voided';
ALTER TYPE public.order_status ADD VALUE IF NOT EXISTS 'voided';

ALTER TABLE public.coupons
  ADD COLUMN IF NOT EXISTS void_reason text,
  ADD COLUMN IF NOT EXISTS voided_at timestamptz;

COMMENT ON COLUMN public.coupons.void_reason IS 'Void reason e.g. merchant_edit';
COMMENT ON COLUMN public.coupons.voided_at IS 'When coupon was voided';
