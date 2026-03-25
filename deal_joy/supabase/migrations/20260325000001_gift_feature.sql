-- =============================================================================
-- Gift Feature Migration
-- Adds gift_status enum, coupon_gifts table, and related schema changes
-- to support the "Send as Gift" functionality.
-- =============================================================================

-- Step 1: Create gift_status enum
-- Tracks the lifecycle of a gift: pending -> claimed or recalled/expired
DO $$ BEGIN
  CREATE TYPE gift_status AS ENUM ('pending', 'claimed', 'recalled', 'expired');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Step 2: Add 'gifted' to customer_item_status enum
-- Marks an order item whose coupon has been gifted to another user
ALTER TYPE customer_item_status ADD VALUE IF NOT EXISTS 'gifted';

-- Step 3: Add gift-related columns to coupons table
-- current_holder_user_id: tracks who currently holds the coupon (may differ from buyer after gifting)
-- is_gifted: flag indicating this coupon was sent as a gift
ALTER TABLE coupons
  ADD COLUMN IF NOT EXISTS current_holder_user_id uuid REFERENCES users(id),
  ADD COLUMN IF NOT EXISTS is_gifted boolean NOT NULL DEFAULT false;

-- Backfill: set current_holder to the original buyer for all existing coupons
UPDATE coupons
SET current_holder_user_id = user_id
WHERE current_holder_user_id IS NULL;

-- Step 4: Create coupon_gifts table
-- Records each gift transaction, including recipient info and claim token
CREATE TABLE IF NOT EXISTS coupon_gifts (
  id                uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  order_item_id     uuid        NOT NULL REFERENCES order_items(id) ON DELETE CASCADE,
  gifter_user_id    uuid        NOT NULL REFERENCES users(id),
  recipient_user_id uuid        REFERENCES users(id),         -- NULL until claimed by a registered user
  recipient_email   text,                                     -- email used to notify recipient
  recipient_phone   text,                                     -- phone used to notify recipient (optional)
  gift_message      text,                                     -- optional personal message from gifter
  status            gift_status NOT NULL DEFAULT 'pending',
  claim_token       text        NOT NULL UNIQUE DEFAULT encode(gen_random_bytes(32), 'hex'),
  token_expires_at  timestamptz NOT NULL DEFAULT (now() + interval '30 days'),
  claimed_at        timestamptz,
  recalled_at       timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),

  -- At least one contact method must be provided so we can notify the recipient
  CONSTRAINT recipient_contact_required
    CHECK (recipient_email IS NOT NULL OR recipient_phone IS NOT NULL)
);

-- Indexes for common query patterns
CREATE INDEX IF NOT EXISTS idx_coupon_gifts_order_item_id  ON coupon_gifts(order_item_id);
CREATE INDEX IF NOT EXISTS idx_coupon_gifts_gifter_user_id ON coupon_gifts(gifter_user_id);
CREATE INDEX IF NOT EXISTS idx_coupon_gifts_claim_token    ON coupon_gifts(claim_token);
CREATE INDEX IF NOT EXISTS idx_coupon_gifts_status         ON coupon_gifts(status);

-- Auto-update updated_at on every row change
CREATE TRIGGER set_coupon_gifts_updated_at
  BEFORE UPDATE ON coupon_gifts
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Enable Row Level Security
ALTER TABLE coupon_gifts ENABLE ROW LEVEL SECURITY;

-- Gifter can view all gifts they have sent
CREATE POLICY "gifter_view_own_gifts" ON coupon_gifts
  FOR SELECT USING (gifter_user_id = auth.uid());

-- Gifter can create a gift record (sending a gift)
CREATE POLICY "gifter_insert_gifts" ON coupon_gifts
  FOR INSERT WITH CHECK (gifter_user_id = auth.uid());

-- Gifter can update their own gift record (e.g., recall before claim)
CREATE POLICY "gifter_update_gifts" ON coupon_gifts
  FOR UPDATE USING (gifter_user_id = auth.uid());

-- Registered recipient can view gifts sent to them
CREATE POLICY "recipient_view_received_gifts" ON coupon_gifts
  FOR SELECT USING (recipient_user_id = auth.uid());

-- Step 5: Register email types for gift notifications
-- C12: confirmation email to the gifter after sending a gift
-- C13: notification email to the recipient when a gift arrives
INSERT INTO email_type_settings (email_code, email_type, description, global_enabled, user_configurable)
VALUES
  ('C12', 'gift_sent_confirmation',     'Gift coupon sent confirmation to gifter',          true, true),
  ('C13', 'gift_received_notification', 'Gift coupon received notification to recipient',   true, false)
ON CONFLICT (email_code) DO NOTHING;
