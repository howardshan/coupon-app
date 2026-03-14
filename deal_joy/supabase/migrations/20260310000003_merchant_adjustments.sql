-- =============================================================
-- merchant_adjustments：商家账户调整记录
-- 用途：记录因退款超出可结算金额产生的欠款（负数），
--       以及管理员手动清零欠款的记录（正数）
-- 与 settlements 表配合，earnings RPC 汇总时可累加此表
-- =============================================================

CREATE TABLE IF NOT EXISTS public.merchant_adjustments (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id         UUID NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,

  -- 金额：负数 = 欠款扣除（退款超出结算），正数 = 欠款偿还（管理员操作）
  amount              NUMERIC(10,2) NOT NULL,

  -- 调整类型
  adjustment_type     TEXT NOT NULL DEFAULT 'refund_deduction'
    CHECK (adjustment_type IN (
      'refund_deduction',  -- 退款扣除（系统自动创建）
      'debt_repayment'     -- 欠款偿还（管理员手动创建）
    )),

  -- 说明文字，如 "Refund deduction: order DJ-XXXXXXXX"
  reason              TEXT NOT NULL,

  -- 关联的退款申请（可选，仅 refund_deduction 类型有值）
  refund_request_id   UUID REFERENCES public.refund_requests(id),

  -- 操作人（管理员 user_id）
  created_by          UUID REFERENCES auth.users(id),

  created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 索引
CREATE INDEX IF NOT EXISTS idx_merchant_adjustments_merchant_id
  ON public.merchant_adjustments(merchant_id);
CREATE INDEX IF NOT EXISTS idx_merchant_adjustments_created_at
  ON public.merchant_adjustments(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_merchant_adjustments_refund_request_id
  ON public.merchant_adjustments(refund_request_id);

-- RLS
ALTER TABLE public.merchant_adjustments ENABLE ROW LEVEL SECURITY;

-- 商家只能查看自己的调整记录
CREATE POLICY "merchant_adjustments_merchant_select" ON public.merchant_adjustments
  FOR SELECT USING (
    merchant_id IN (
      SELECT ms.merchant_id
      FROM public.merchant_staff ms
      WHERE ms.user_id = auth.uid()
      UNION
      SELECT id FROM public.merchants WHERE user_id = auth.uid()
    )
  );

-- 只有 service_role 可以写入（Edge Function 和管理后台操作）
CREATE POLICY "merchant_adjustments_service_all" ON public.merchant_adjustments
  FOR ALL USING (auth.role() = 'service_role');

COMMENT ON TABLE public.merchant_adjustments IS
  '商家账户调整记录：退款扣除（负数欠款）和欠款偿还（正数）';
COMMENT ON COLUMN public.merchant_adjustments.amount IS
  '负数=欠款扣除，正数=欠款偿还';
