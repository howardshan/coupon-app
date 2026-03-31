-- =============================================================
-- 赠送券给应用内好友 — 数据库变更
-- =============================================================

-- 1. 放宽 coupon_gifts 表的 recipient_contact_required 约束
--    好友赠送时只有 recipient_user_id，可能没有 email/phone
ALTER TABLE coupon_gifts DROP CONSTRAINT IF EXISTS recipient_contact_required;
ALTER TABLE coupon_gifts ADD CONSTRAINT recipient_contact_required
  CHECK (recipient_email IS NOT NULL OR recipient_phone IS NOT NULL OR recipient_user_id IS NOT NULL);

-- 2. 添加 gift_type 列区分赠送渠道
--    'external' = email/phone 外部赠送（默认）
--    'in_app'   = 应用内好友赠送（自动 claim）
ALTER TABLE coupon_gifts ADD COLUMN IF NOT EXISTS gift_type text NOT NULL DEFAULT 'external';
COMMENT ON COLUMN coupon_gifts.gift_type IS 'external = email/phone, in_app = friend gift (auto-claimed)';

-- 3. coupons 表新增 gifted_from_user_id（赠送者 user ID）
--    区别于已有的 gifted_from（引用 coupons.id）
ALTER TABLE coupons ADD COLUMN IF NOT EXISTS gifted_from_user_id uuid REFERENCES users(id);
CREATE INDEX IF NOT EXISTS idx_coupons_gifted_from_user_id ON coupons(gifted_from_user_id);

-- 4. coupon_gifts 表加索引（按 recipient_user_id 查询）
CREATE INDEX IF NOT EXISTS idx_coupon_gifts_recipient_user_id ON coupon_gifts(recipient_user_id);

-- 5. coupons RLS 策略 — 允许受赠人通过 current_holder_user_id 查看券
CREATE POLICY coupons_holder_select ON coupons
  FOR SELECT
  USING (auth.uid() = current_holder_user_id);

-- 6. 注册新邮件类型
INSERT INTO email_type_settings (email_code, email_name, recipient_type, description, global_enabled, user_configurable)
VALUES
  ('C15', 'friend_gift_received', 'customer', 'Notification when a friend gifts you a coupon (auto-claimed)', true, true),
  ('C16', 'friend_gift_recalled', 'customer', 'Notification when a friend recalls a gifted coupon', true, true)
ON CONFLICT (email_code) DO NOTHING;
