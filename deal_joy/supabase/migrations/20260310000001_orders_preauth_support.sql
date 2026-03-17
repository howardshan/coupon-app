-- =============================================================
-- 预授权支付支持：为 orders 表添加 is_captured 字段
-- is_captured = false：预授权已放，尚未扣款（capture_method: manual）
-- is_captured = true：已扣款（即时扣款或已完成 capture）
-- =============================================================

-- 新增 is_captured 字段（默认 true，兼容现有所有订单）
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS is_captured BOOLEAN NOT NULL DEFAULT true;

-- 已有订单全部视为已扣款，保持现有行为
UPDATE public.orders SET is_captured = true WHERE is_captured IS NULL;

-- 更新字段注释
COMMENT ON COLUMN public.orders.is_captured IS
  'true=已扣款; false=预授权未扣款(capture_method:manual)，待核销时执行 capture';

COMMENT ON COLUMN public.orders.status IS
  'authorized | unused | used | refunded | refund_pending_merchant | refund_pending_admin | refund_rejected | refund_failed | expired';
