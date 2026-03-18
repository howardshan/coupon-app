-- =============================================
-- Migration: After-sales (Post-Verification Refund)
-- =============================================

begin;

-- -----------------------------------------------------------------------------
-- 1) Supporting ENUM types
-- -----------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'after_sale_status') THEN
    CREATE TYPE public.after_sale_status AS ENUM (
      'pending',
      'merchant_approved',
      'merchant_rejected',
      'awaiting_platform',
      'platform_approved',
      'platform_rejected',
      'refunded',
      'closed'
    );
  END IF;
END$$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'after_sale_reason') THEN
    CREATE TYPE public.after_sale_reason AS ENUM (
      'mistaken_redemption',
      'bad_experience',
      'service_issue',
      'quality_issue',
      'other'
    );
  END IF;
END$$;

-- -----------------------------------------------------------------------------
-- 2) Core tables
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.after_sales_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  coupon_id UUID NOT NULL REFERENCES public.coupons(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  merchant_id UUID NOT NULL REFERENCES public.merchants(id) ON DELETE RESTRICT,
  store_id UUID NOT NULL REFERENCES public.merchants(id) ON DELETE RESTRICT,
  status public.after_sale_status NOT NULL DEFAULT 'pending',
  reason_code public.after_sale_reason NOT NULL,
  reason_detail TEXT NOT NULL,
  refund_amount NUMERIC(10,2) NOT NULL DEFAULT 0,
  user_attachments TEXT[] NOT NULL DEFAULT '{}'::TEXT[],
  merchant_feedback TEXT,
  merchant_attachments TEXT[] NOT NULL DEFAULT '{}'::TEXT[],
  platform_feedback TEXT,
  platform_attachments TEXT[] NOT NULL DEFAULT '{}'::TEXT[],
  escalated_at TIMESTAMPTZ,
  platform_decided_at TIMESTAMPTZ,
  refunded_at TIMESTAMPTZ,
  closed_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ NOT NULL,
  timeline JSONB NOT NULL DEFAULT '[]'::JSONB,
  metadata JSONB NOT NULL DEFAULT '{}'::JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.after_sales_events (
  id BIGSERIAL PRIMARY KEY,
  request_id UUID NOT NULL REFERENCES public.after_sales_requests(id) ON DELETE CASCADE,
  actor_role TEXT NOT NULL CHECK (actor_role IN ('user','merchant','platform','system')),
  actor_id UUID,
  action TEXT NOT NULL,
  payload JSONB DEFAULT '{}'::JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- -----------------------------------------------------------------------------
-- 3) Helper functions & triggers
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS set_updated_at ON public.after_sales_requests;
CREATE TRIGGER set_updated_at
BEFORE UPDATE ON public.after_sales_requests
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

CREATE OR REPLACE FUNCTION public.log_after_sales_event()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_actor UUID := auth.uid();
  v_role TEXT := COALESCE(current_setting('request.jwt.claims', true)::json->>'role', 'system');
  v_action TEXT;
  v_payload JSONB := '{}';
BEGIN
  IF TG_OP = 'INSERT' THEN
    v_action := 'submitted';
    v_payload := jsonb_build_object(
      'status', NEW.status,
      'reason_code', NEW.reason_code
    );
  ELSE
    IF NEW.status IS DISTINCT FROM OLD.status THEN
      v_action := 'status_' || NEW.status;
      v_payload := jsonb_build_object(
        'old_status', OLD.status,
        'new_status', NEW.status
      );
    ELSE
      v_action := 'updated';
      v_payload := jsonb_build_object(
        'diff', to_jsonb(NEW) - ARRAY(SELECT column_name::text
                                      FROM information_schema.columns
                                      WHERE table_schema = 'public'
                                        AND table_name = 'after_sales_requests'
                                        AND column_name IN ('id'))
      );
    END IF;
  END IF;

  INSERT INTO public.after_sales_events(request_id, actor_role, actor_id, action, payload)
  VALUES (NEW.id, COALESCE(v_role, 'system'), v_actor, v_action, v_payload);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS log_after_sales_event_trigger ON public.after_sales_requests;
CREATE TRIGGER log_after_sales_event_trigger
AFTER INSERT OR UPDATE ON public.after_sales_requests
FOR EACH ROW
EXECUTE FUNCTION public.log_after_sales_event();

-- -----------------------------------------------------------------------------
-- 4) Constraints & indexes
-- -----------------------------------------------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS idx_after_sales_unique_active_coupon
ON public.after_sales_requests(coupon_id)
WHERE status NOT IN ('refunded','closed','platform_rejected');

CREATE INDEX IF NOT EXISTS idx_after_sales_requests_status
ON public.after_sales_requests(status, merchant_id, store_id);

CREATE INDEX IF NOT EXISTS idx_after_sales_requests_user
ON public.after_sales_requests(user_id);

CREATE INDEX IF NOT EXISTS idx_after_sales_events_request
ON public.after_sales_events(request_id);

-- -----------------------------------------------------------------------------
-- 5) Views for app consumption
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.view_user_after_sales_requests AS
SELECT
  r.id,
  r.order_id,
  r.coupon_id,
  r.status,
  r.reason_code,
  r.reason_detail,
  r.refund_amount,
  r.user_attachments,
  r.merchant_feedback,
  r.merchant_attachments,
  r.platform_feedback,
  r.platform_attachments,
  r.timeline,
  r.expires_at,
  r.refunded_at,
  r.created_at,
  r.updated_at,
  o.order_number,
  o.total_amount,
  c.used_at,
  d.title AS deal_title
FROM public.after_sales_requests r
JOIN public.orders o ON o.id = r.order_id
JOIN public.coupons c ON c.id = r.coupon_id
LEFT JOIN public.deals d ON d.id = o.deal_id;

CREATE OR REPLACE VIEW public.view_merchant_after_sales_requests AS
SELECT
  r.id,
  r.order_id,
  r.coupon_id,
  r.status,
  r.reason_code,
  r.reason_detail,
  r.refund_amount,
  r.user_attachments,
  r.merchant_feedback,
  r.merchant_attachments,
  r.platform_feedback,
  r.platform_attachments,
  r.expires_at,
  r.created_at,
  r.updated_at,
  r.merchant_id,
  r.store_id,
  o.total_amount,
  o.order_number,
  o.user_id,
  u.full_name AS user_name,
  s.name AS store_name,
  d.title AS deal_title
FROM public.after_sales_requests r
JOIN public.orders o ON o.id = r.order_id
JOIN public.users u ON u.id = o.user_id
JOIN public.merchants s ON s.id = r.store_id
LEFT JOIN public.deals d ON d.id = o.deal_id;

-- -----------------------------------------------------------------------------
-- 6) Row Level Security
-- -----------------------------------------------------------------------------
ALTER TABLE public.after_sales_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.after_sales_events ENABLE ROW LEVEL SECURITY;

-- user policies
CREATE POLICY IF NOT EXISTS user_select_after_sales
ON public.after_sales_requests
FOR SELECT
USING (auth.uid() = user_id);

CREATE POLICY IF NOT EXISTS user_insert_after_sales
ON public.after_sales_requests
FOR INSERT
WITH CHECK (auth.uid() = user_id);

CREATE POLICY IF NOT EXISTS user_update_after_sales
ON public.after_sales_requests
FOR UPDATE
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id AND status IN ('awaiting_platform','pending'));

-- merchant read policy
CREATE POLICY IF NOT EXISTS merchant_select_after_sales
ON public.after_sales_requests
FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM public.merchants m
    WHERE m.id = after_sales_requests.merchant_id
      AND m.user_id = auth.uid()
  )
  OR EXISTS (
    SELECT 1 FROM public.merchant_staff ms
    WHERE ms.merchant_id = after_sales_requests.merchant_id
      AND ms.user_id = auth.uid()
      AND ms.is_active = true
  )
);

-- admin/service policies
CREATE POLICY IF NOT EXISTS admin_all_after_sales
ON public.after_sales_requests
FOR ALL
USING (
  auth.role() = 'service_role'
  OR EXISTS (
    SELECT 1 FROM public.users u
    WHERE u.id = auth.uid() AND u.role IN ('admin','super_admin')
  )
)
WITH CHECK (
  auth.role() = 'service_role'
  OR EXISTS (
    SELECT 1 FROM public.users u
    WHERE u.id = auth.uid() AND u.role IN ('admin','super_admin')
  )
);

-- mirror policies for events
CREATE POLICY IF NOT EXISTS user_select_after_sales_events
ON public.after_sales_events
FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM public.after_sales_requests r
    WHERE r.id = after_sales_events.request_id
      AND r.user_id = auth.uid()
  )
);

CREATE POLICY IF NOT EXISTS merchant_select_after_sales_events
ON public.after_sales_events
FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM public.after_sales_requests r
    WHERE r.id = after_sales_events.request_id
      AND (
        EXISTS (
          SELECT 1 FROM public.merchants m
          WHERE m.id = r.merchant_id AND m.user_id = auth.uid()
        )
        OR EXISTS (
          SELECT 1 FROM public.merchant_staff ms
          WHERE ms.merchant_id = r.merchant_id
            AND ms.user_id = auth.uid()
            AND ms.is_active = true
        )
      )
  )
);

CREATE POLICY IF NOT EXISTS admin_all_after_sales_events
ON public.after_sales_events
FOR ALL
USING (
  auth.role() = 'service_role'
  OR EXISTS (
    SELECT 1 FROM public.users u
    WHERE u.id = auth.uid() AND u.role IN ('admin','super_admin')
  )
)
WITH CHECK (
  auth.role() = 'service_role'
  OR EXISTS (
    SELECT 1 FROM public.users u
    WHERE u.id = auth.uid() AND u.role IN ('admin','super_admin')
  )
);

-- -----------------------------------------------------------------------------
-- 7) Storage bucket (evidence uploads) & policy placeholders
-- -----------------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public)
SELECT 'after-sales-evidence', 'after-sales-evidence', false
WHERE NOT EXISTS (
  SELECT 1 FROM storage.buckets WHERE id = 'after-sales-evidence'
);

-- stub policies: service role full access, others denied until app-layer signed URLs are used
CREATE POLICY IF NOT EXISTS "after_sales_evidence_service"
ON storage.objects
FOR ALL
USING (bucket_id = 'after-sales-evidence' AND auth.role() = 'service_role')
WITH CHECK (bucket_id = 'after-sales-evidence' AND auth.role() = 'service_role');

CREATE POLICY IF NOT EXISTS "after_sales_evidence_readonly_stub"
ON storage.objects
FOR SELECT
USING (
  bucket_id = 'after-sales-evidence'
  AND auth.role() = 'service_role'
);
COMMENT ON POLICY "after_sales_evidence_readonly_stub" ON storage.objects
IS 'TODO: replace with fine-grained actor-based read policy once storage metadata wiring is ready.';

-- -----------------------------------------------------------------------------
-- 8) Comments for clarity
-- -----------------------------------------------------------------------------
COMMENT ON TABLE public.after_sales_requests IS 'After-sales refund requests for coupons already redeemed';
COMMENT ON TABLE public.after_sales_events IS 'Timeline/audit log for after-sales requests';
COMMENT ON COLUMN public.after_sales_requests.timeline IS 'Cached timeline JSON, kept in sync by application logic';
COMMENT ON COLUMN public.after_sales_requests.store_id IS 'Linked store (temp: references merchants until dedicated stores table ships)';

commit;
