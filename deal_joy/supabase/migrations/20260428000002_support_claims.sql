-- support_claims 表：admin 在客服面板为用户创建的工单
CREATE TABLE public.support_claims (
  id                uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id   uuid        REFERENCES public.conversations(id) ON DELETE SET NULL,
  user_id           uuid        NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  created_by        uuid        NOT NULL REFERENCES public.users(id),

  subject_type      text        NOT NULL DEFAULT 'general'
                                CHECK (subject_type IN ('order', 'deal', 'general')),
  order_id          uuid        REFERENCES public.orders(id) ON DELETE SET NULL,
  order_item_id     uuid        REFERENCES public.order_items(id) ON DELETE SET NULL,
  deal_id           uuid        REFERENCES public.deals(id) ON DELETE SET NULL,

  claim_type        text        NOT NULL
                                CHECK (claim_type IN ('refund','compensation','dispute','quality','service','other')),
  priority          text        NOT NULL DEFAULT 'normal'
                                CHECK (priority IN ('low','normal','high','urgent')),
  status            text        NOT NULL DEFAULT 'open'
                                CHECK (status IN ('open','investigating','pending_response','resolved','closed')),
  title             text        NOT NULL,
  description       text        NOT NULL,
  internal_notes    text,

  resolution_type   text        CHECK (resolution_type IN ('refund','store_credit','after_sales','no_action','other')),
  resolution_amount numeric(10,2),
  resolution_notes  text,
  resolved_at       timestamptz,
  resolved_by       uuid        REFERENCES public.users(id),

  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_support_claims_user_id         ON public.support_claims(user_id);
CREATE INDEX idx_support_claims_conversation_id ON public.support_claims(conversation_id);
CREATE INDEX idx_support_claims_status          ON public.support_claims(status);
CREATE INDEX idx_support_claims_created_at      ON public.support_claims(created_at DESC);

ALTER TABLE public.support_claims ENABLE ROW LEVEL SECURITY;

CREATE POLICY "admin_all_support_claims" ON public.support_claims
  USING  (EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin'))
  WITH CHECK (EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin'));

CREATE TRIGGER set_support_claims_updated_at
  BEFORE UPDATE ON public.support_claims
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
