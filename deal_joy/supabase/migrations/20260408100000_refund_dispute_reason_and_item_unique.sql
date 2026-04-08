-- 核销后争议退款（按 order_item）：API/商家端使用 reason 列名；与 user_reason 同步
-- 同一 order_item 仅允许一条 pending_merchant / pending_admin 申请

ALTER TABLE public.refund_requests
  ADD COLUMN IF NOT EXISTS reason text;

UPDATE public.refund_requests
SET reason = COALESCE(reason, user_reason)
WHERE reason IS NULL AND user_reason IS NOT NULL;

COMMENT ON COLUMN public.refund_requests.reason IS '用户申请理由（与 user_reason 同步，供 API 扁平字段）';

DROP INDEX IF EXISTS idx_refund_requests_one_pending_per_order_item;

CREATE UNIQUE INDEX idx_refund_requests_one_pending_per_order_item
  ON public.refund_requests (order_item_id)
  WHERE order_item_id IS NOT NULL
    AND status IN ('pending_merchant', 'pending_admin');
