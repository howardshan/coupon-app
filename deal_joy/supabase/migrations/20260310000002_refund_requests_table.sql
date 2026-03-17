-- =============================================================
-- refund_requests 表：追踪核销后的退款申请审批链路
-- 状态流:
--   pending_merchant → approved_merchant（商家同意，触发退款）
--   pending_merchant → rejected_merchant → pending_admin（商家拒绝，升级管理员）
--   pending_admin → approved_admin（管理员同意，触发退款）
--   pending_admin → rejected_admin（管理员最终拒绝）
--   approved_merchant / approved_admin → completed（退款执行完成）
-- =============================================================

CREATE TABLE IF NOT EXISTS public.refund_requests (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id            UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  user_id             UUID NOT NULL REFERENCES public.users(id),
  merchant_id         UUID NOT NULL REFERENCES public.merchants(id),

  -- 退款金额（支持部分退款）
  refund_amount       NUMERIC(10,2) NOT NULL CHECK (refund_amount > 0),

  -- 涉及的单品快照（部分退款时填写，来自 orders.selected_options 或 deals.dishes 解析）
  -- 格式: [{"name": "Grilled Salmon", "qty": 1, "unit_price": 28.00, "refund_amount": 25.20}]
  refund_items        JSONB,

  -- 申请状态
  status              TEXT NOT NULL DEFAULT 'pending_merchant'
    CHECK (status IN (
      'pending_merchant',   -- 等待商家审批
      'approved_merchant',  -- 商家已同意（触发退款）
      'rejected_merchant',  -- 商家已拒绝（升级至管理员）
      'pending_admin',      -- 等待管理员仲裁
      'approved_admin',     -- 管理员已同意（触发退款）
      'rejected_admin',     -- 管理员最终拒绝
      'completed',          -- 退款已完成
      'cancelled'           -- 用户主动撤回
    )),

  -- 用户填写的退款理由（必填，最少10字）
  user_reason         TEXT NOT NULL,

  -- 商家决定
  merchant_decision   TEXT CHECK (merchant_decision IN ('approved', 'rejected')),
  merchant_reason     TEXT,            -- 商家拒绝时必填
  merchant_decided_at TIMESTAMPTZ,
  merchant_decided_by UUID REFERENCES public.users(id),

  -- 管理员决定
  admin_decision      TEXT CHECK (admin_decision IN ('approved', 'rejected')),
  admin_reason        TEXT,
  admin_decided_at    TIMESTAMPTZ,
  admin_decided_by    UUID REFERENCES public.users(id),

  -- 退款完成时间
  completed_at        TIMESTAMPTZ,

  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 索引
CREATE INDEX IF NOT EXISTS idx_refund_requests_order_id
  ON public.refund_requests(order_id);
CREATE INDEX IF NOT EXISTS idx_refund_requests_merchant_id
  ON public.refund_requests(merchant_id);
CREATE INDEX IF NOT EXISTS idx_refund_requests_user_id
  ON public.refund_requests(user_id);
CREATE INDEX IF NOT EXISTS idx_refund_requests_status
  ON public.refund_requests(status);
CREATE INDEX IF NOT EXISTS idx_refund_requests_created_at
  ON public.refund_requests(created_at DESC);

-- RLS
ALTER TABLE public.refund_requests ENABLE ROW LEVEL SECURITY;

-- 用户只能查看自己提交的退款申请
CREATE POLICY "refund_requests_user_select" ON public.refund_requests
  FOR SELECT USING (auth.uid() = user_id);

-- 用户只能插入自己的退款申请
CREATE POLICY "refund_requests_user_insert" ON public.refund_requests
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- 商家可以查看属于自己门店的退款申请
CREATE POLICY "refund_requests_merchant_select" ON public.refund_requests
  FOR SELECT USING (
    merchant_id IN (
      SELECT ms.merchant_id
      FROM public.merchant_staff ms
      WHERE ms.user_id = auth.uid()
    )
  );

-- service_role 全权限（Edge Function 使用）
CREATE POLICY "refund_requests_service_all" ON public.refund_requests
  FOR ALL USING (auth.role() = 'service_role');

COMMENT ON TABLE public.refund_requests IS
  '核销后退款申请表，支持商家→管理员三级审批链路';
