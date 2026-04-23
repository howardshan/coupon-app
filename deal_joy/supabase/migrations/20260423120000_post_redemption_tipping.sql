-- Post-redemption tipping: deals config + coupon_tips + storage bucket + RLS
-- See docs/plans/2026-04-23-post-redemption-tipping.md

-- ---------------------------------------------------------------------------
-- 1) deals: tipping configuration (defaults preserve existing behavior)
-- ---------------------------------------------------------------------------
ALTER TABLE public.deals
  ADD COLUMN IF NOT EXISTS tips_enabled boolean NOT NULL DEFAULT false;

ALTER TABLE public.deals
  ADD COLUMN IF NOT EXISTS tips_mode text;

ALTER TABLE public.deals
  ADD COLUMN IF NOT EXISTS tips_preset_1 numeric(10, 2),
  ADD COLUMN IF NOT EXISTS tips_preset_2 numeric(10, 2),
  ADD COLUMN IF NOT EXISTS tips_preset_3 numeric(10, 2);

DO $$
BEGIN
  ALTER TABLE public.deals
    ADD CONSTRAINT deals_tips_mode_check
    CHECK (tips_mode IS NULL OR tips_mode IN ('percent', 'fixed'));
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON COLUMN public.deals.tips_enabled IS 'If true, merchant may collect optional tip after redemption for this deal.';
COMMENT ON COLUMN public.deals.tips_mode IS 'percent: presets are 0-100 portions of order_items.unit_price; fixed: presets are USD amounts.';
COMMENT ON COLUMN public.deals.tips_preset_1 IS 'First preset (percent or fixed per tips_mode).';
COMMENT ON COLUMN public.deals.tips_preset_2 IS 'Second preset.';
COMMENT ON COLUMN public.deals.tips_preset_3 IS 'Third preset.';

-- ---------------------------------------------------------------------------
-- 2) coupon_tips: one paid tip per coupon (partial unique index below)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.coupon_tips (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  coupon_id uuid NOT NULL REFERENCES public.coupons(id) ON DELETE CASCADE,
  order_item_id uuid REFERENCES public.order_items(id) ON DELETE SET NULL,
  deal_id uuid NOT NULL REFERENCES public.deals(id) ON DELETE RESTRICT,
  merchant_id uuid NOT NULL REFERENCES public.merchants(id) ON DELETE RESTRICT,
  payer_user_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
  amount_cents integer NOT NULL CHECK (amount_cents >= 0),
  currency text NOT NULL DEFAULT 'usd',
  tips_mode_snapshot text,
  preset_choice text,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'paid', 'failed', 'canceled')),
  stripe_payment_intent_id text UNIQUE,
  signature_storage_path text,
  created_by_merchant_user_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  paid_at timestamptz
);

CREATE INDEX IF NOT EXISTS idx_coupon_tips_coupon_id ON public.coupon_tips(coupon_id);
CREATE INDEX IF NOT EXISTS idx_coupon_tips_order_item_id ON public.coupon_tips(order_item_id);
CREATE INDEX IF NOT EXISTS idx_coupon_tips_merchant_created ON public.coupon_tips(merchant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_coupon_tips_stripe_pi ON public.coupon_tips(stripe_payment_intent_id)
  WHERE stripe_payment_intent_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_coupon_tips_one_paid_per_coupon
  ON public.coupon_tips(coupon_id)
  WHERE status = 'paid';

COMMENT ON TABLE public.coupon_tips IS 'Optional post-redemption tip payment per coupon; Stripe PI in metadata type=tip.';

DROP TRIGGER IF EXISTS set_coupon_tips_updated_at ON public.coupon_tips;
CREATE TRIGGER set_coupon_tips_updated_at
  BEFORE UPDATE ON public.coupon_tips
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

ALTER TABLE public.coupon_tips ENABLE ROW LEVEL SECURITY;

-- Staff / store owner of redeeming merchant can read tips for their store
DROP POLICY IF EXISTS coupon_tips_select_merchant_scope ON public.coupon_tips;
CREATE POLICY coupon_tips_select_merchant_scope
  ON public.coupon_tips
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.merchant_staff ms
      WHERE ms.user_id = auth.uid()
        AND ms.is_active = true
        AND ms.merchant_id = coupon_tips.merchant_id
    )
    OR EXISTS (
      SELECT 1
      FROM public.merchants m
      WHERE m.id = coupon_tips.merchant_id
        AND m.user_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1
      FROM public.brand_admins ba
      JOIN public.merchants m ON m.brand_id = ba.brand_id AND m.id = coupon_tips.merchant_id
      WHERE ba.user_id = auth.uid()
    )
  );

-- Payer (when set) can read own tip rows
DROP POLICY IF EXISTS coupon_tips_select_payer ON public.coupon_tips;
CREATE POLICY coupon_tips_select_payer
  ON public.coupon_tips
  FOR SELECT
  TO authenticated
  USING (payer_user_id IS NOT NULL AND payer_user_id = auth.uid());

-- Writes only via service_role Edge Functions (no INSERT/UPDATE for authenticated)
-- ---------------------------------------------------------------------------
-- 3) Storage: private bucket for signatures (uploads via service_role / signed URL from Edge)
-- ---------------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public)
VALUES ('tip-signatures', 'tip-signatures', false)
ON CONFLICT (id) DO NOTHING;

-- No public SELECT; service_role bypasses RLS. Optional: allow merchant read own paths later.
