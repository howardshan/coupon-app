-- =============================================================
-- 退款流程：refund_failed 状态 + refund_rejected_at（管理员拒绝后展示 Refund Rejected）
-- =============================================================

-- 1. order_status 枚举增加 refund_failed（Stripe 退款失败时使用）
-- 若已存在会报错，可忽略或先检查 pg_enum
ALTER TYPE public.order_status ADD VALUE 'refund_failed';

-- 2. orders 表增加 refund_rejected_at（管理员拒绝退款时写入，详情页多维度展示 Refund Rejected）
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS refund_rejected_at TIMESTAMPTZ;

COMMENT ON COLUMN public.orders.refund_rejected_at IS 'Admin rejected refund at; when set with status=unused, detail UI shows Refund Rejected tag.';
