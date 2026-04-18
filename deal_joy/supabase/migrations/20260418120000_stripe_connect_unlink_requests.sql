-- =============================================================
-- Sprint 1：Stripe Connect 解绑申请单 + 商家/品牌 RLS + 邮件类型 M19–M21
-- 规格：docs/plans/2026-04-08-stripe-connect-unlink-request-v1.md
-- =============================================================

-- 判断当前用户是否可对该 subject 发起/查看解绑申请（商家主+full_access 员工 / 品牌管理员）
CREATE OR REPLACE FUNCTION public.can_access_stripe_unlink_request(
  p_subject_type text,
  p_subject_id uuid
) RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_subject_type = 'merchant' THEN
    RETURN public.can_read_merchant(p_subject_id);
  END IF;
  IF p_subject_type = 'brand' THEN
    RETURN public.is_brand_admin(p_subject_id);
  END IF;
  RETURN false;
END;
$$;

COMMENT ON FUNCTION public.can_access_stripe_unlink_request(text, uuid) IS
  'Stripe 解绑申请：商家侧可读/可建单的主体权限（merchant=门店可读；brand=品牌管理员）';

-- ─────────────────────────────────────────────────────────────
-- 主表
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.stripe_connect_unlink_requests (
  id                    uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  subject_type          text        NOT NULL
    CHECK (subject_type IN ('merchant', 'brand')),
  subject_id            uuid        NOT NULL,
  merchant_id           uuid        NOT NULL REFERENCES public.merchants (id) ON DELETE RESTRICT,
  requested_by_user_id  uuid        NOT NULL REFERENCES public.users (id) ON DELETE RESTRICT,
  status                text        NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'approved', 'rejected')),
  request_note          text,
  reason_code           text,
  rejected_reason       text,
  reviewed_by_admin_id  uuid        REFERENCES public.users (id) ON DELETE SET NULL,
  reviewed_at           timestamptz,
  unbind_applied_at     timestamptz,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_stripe_unlink_merchant_created
  ON public.stripe_connect_unlink_requests (merchant_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_stripe_unlink_status_created
  ON public.stripe_connect_unlink_requests (status, created_at DESC);

-- 同一 subject 仅允许一条 pending
CREATE UNIQUE INDEX IF NOT EXISTS uq_stripe_unlink_one_pending_per_subject
  ON public.stripe_connect_unlink_requests (subject_type, subject_id)
  WHERE (status = 'pending');

CREATE TRIGGER trg_stripe_unlink_requests_updated_at
  BEFORE UPDATE ON public.stripe_connect_unlink_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

COMMENT ON TABLE public.stripe_connect_unlink_requests IS
  'Stripe Connect 解绑申请：仅平台库解绑，审批/执行由 Service Role 或管理端完成';

COMMENT ON COLUMN public.stripe_connect_unlink_requests.merchant_id IS
  '冗余：关联门店行，便于 RLS 与按店查询；brand 解绑时须为属于该 brand 的某一门店 id';

COMMENT ON COLUMN public.stripe_connect_unlink_requests.unbind_applied_at IS
  '平台库解绑（清 stripe_account_id 等）已执行时间，用于幂等与审计';

-- ─────────────────────────────────────────────────────────────
-- RLS：商家/品牌只读+插入 pending；无 UPDATE/DELETE（走 service_role）
-- 管理员 is_admin 只读
-- ─────────────────────────────────────────────────────────────
ALTER TABLE public.stripe_connect_unlink_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "stripe_unlink_select_admin"
  ON public.stripe_connect_unlink_requests
  FOR SELECT
  USING (public.is_admin());

CREATE POLICY "stripe_unlink_select_merchant_brand"
  ON public.stripe_connect_unlink_requests
  FOR SELECT
  USING (public.can_access_stripe_unlink_request(subject_type, subject_id));

CREATE POLICY "stripe_unlink_insert_merchant_brand"
  ON public.stripe_connect_unlink_requests
  FOR INSERT
  WITH CHECK (
    auth.uid() = requested_by_user_id
    AND status = 'pending'
    AND public.can_access_stripe_unlink_request(subject_type, subject_id)
    AND (
      (subject_type = 'merchant' AND subject_id = merchant_id)
      OR (
        subject_type = 'brand'
        AND EXISTS (
          SELECT 1
          FROM public.merchants m
          WHERE m.id = merchant_id
            AND m.brand_id = subject_id
        )
      )
    )
  );

-- ─────────────────────────────────────────────────────────────
-- 邮件类型 M19–M21（当前最大已用 M18）
-- ─────────────────────────────────────────────────────────────
INSERT INTO public.email_type_settings (email_code, email_name, recipient_type, user_configurable)
VALUES
  ('M19', 'Stripe Unlink Request Submitted', 'merchant', FALSE),
  ('M20', 'Stripe Unlink Approved',            'merchant', FALSE),
  ('M21', 'Stripe Unlink Rejected',              'merchant', FALSE)
ON CONFLICT (email_code) DO NOTHING;
