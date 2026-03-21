-- =============================================================
-- DealJoy 邮件系统基础表
-- Migration: 20260321200000_email_system.sql
-- 新增 4 张表：email_type_settings, email_logs,
--             user_email_preferences, merchant_email_preferences
-- =============================================================

-- ─────────────────────────────────────────────────────────────
-- 1. email_type_settings
--    全局邮件开关 + 管理员收件人配置
--    覆盖全部 37 种邮件类型（C/M/A 系列）
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS email_type_settings (
  id                     UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  email_code             TEXT        NOT NULL UNIQUE,
  email_name             TEXT        NOT NULL,
  recipient_type         TEXT        NOT NULL CHECK (recipient_type IN ('customer', 'merchant', 'admin')),
  -- 全局开关：管理员控制，关闭后该类邮件完全停发
  global_enabled         BOOLEAN     NOT NULL DEFAULT TRUE,
  -- 是否允许用户/商家在个人设置中自主关闭
  user_configurable      BOOLEAN     NOT NULL DEFAULT TRUE,
  -- 仅 A 系列使用：管理员通知收件人列表
  admin_recipient_emails JSONB       NOT NULL DEFAULT '[]',
  description            TEXT,
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_by             UUID        REFERENCES users(id)
);

-- ─────────────────────────────────────────────────────────────
-- 1a. 预置全部 37 种邮件类型
-- ─────────────────────────────────────────────────────────────

-- C 系列（客户端，13 种）
INSERT INTO email_type_settings (email_code, email_name, recipient_type, user_configurable) VALUES
  ('C1',  'Welcome Email',                    'customer', FALSE),
  ('C2',  'Order Confirmation',               'customer', FALSE),
  ('C3',  'Coupon Redeemed Notification',     'customer', TRUE),
  ('C4',  'Coupon Expiring Reminder',         'customer', TRUE),
  ('C5',  'Auto-Refund on Expiry',            'customer', FALSE),
  ('C6',  'Store Credit Added',               'customer', FALSE),
  ('C7',  'Refund Request Received',          'customer', FALSE),
  ('C8',  'Stripe Refund Completed',          'customer', FALSE),
  ('C9',  'After-Sales Submitted',            'customer', FALSE),
  ('C10', 'After-Sales Approved',             'customer', FALSE),
  ('C11', 'After-Sales Rejected',             'customer', FALSE),
  ('C12', 'Password Reset',                   'customer', FALSE),
  ('C13', 'Merchant Replied to After-Sales',  'customer', TRUE)
ON CONFLICT (email_code) DO NOTHING;

-- M 系列（商家端，16 种）
INSERT INTO email_type_settings (email_code, email_name, recipient_type, user_configurable) VALUES
  ('M1',  'Merchant Welcome Email',                  'merchant', FALSE),
  ('M2',  'Application Received',                    'merchant', FALSE),
  ('M3',  'Merchant Approved',                       'merchant', FALSE),
  ('M4',  'Merchant Rejected',                       'merchant', FALSE),
  ('M5',  'New Order Notification',                  'merchant', TRUE),
  ('M6',  'Deal Expiring Reminder',                  'merchant', TRUE),
  ('M7',  'Coupon Redeemed Notification',            'merchant', TRUE),
  ('M8',  'Pre-Redemption Refund Notification',      'merchant', FALSE),
  ('M9',  'After-Sales Request Received',            'merchant', FALSE),
  ('M10', 'After-Sales Approved Confirmation',       'merchant', FALSE),
  ('M11', 'After-Sales Rejected — Escalated',        'merchant', FALSE),
  ('M12', 'Platform Final Decision',                 'merchant', FALSE),
  ('M13', 'Monthly Settlement Report',               'merchant', TRUE),
  ('M14', 'Withdrawal Request Received',             'merchant', FALSE),
  ('M15', 'Withdrawal Completed',                    'merchant', FALSE),
  ('M16', 'Deal Rejected by Admin',                  'merchant', FALSE)
ON CONFLICT (email_code) DO NOTHING;

-- A 系列（后台管理端，8 种）
INSERT INTO email_type_settings (email_code, email_name, recipient_type, user_configurable, admin_recipient_emails) VALUES
  ('A1', 'Admin Account Created',             'admin', FALSE, '[]'),
  ('A2', 'New Merchant Application',          'admin', FALSE, '[]'),
  ('A3', 'Daily Digest',                      'admin', FALSE, '[]'),
  ('A4', 'Large Refund Alert',                'admin', FALSE, '[]'),
  ('A5', 'After-Sales Escalated',             'admin', FALSE, '[]'),
  ('A6', 'After-Sales Closed',                'admin', FALSE, '[]'),
  ('A7', 'Withdrawal Request Pending',        'admin', FALSE, '[]'),
  ('A8', 'System Error Alert',                'admin', FALSE, '[]')
ON CONFLICT (email_code) DO NOTHING;

-- RLS
ALTER TABLE email_type_settings ENABLE ROW LEVEL SECURITY;

-- 管理员可读写
CREATE POLICY "email_type_settings_admin_all" ON email_type_settings
  FOR ALL
  USING (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin'));

-- 已认证用户可读（UI 联动：查询 global_enabled 决定是否显示偏好选项）
CREATE POLICY "email_type_settings_authenticated_read" ON email_type_settings
  FOR SELECT
  USING (auth.role() = 'authenticated');


-- ─────────────────────────────────────────────────────────────
-- 2. email_logs
--    邮件发送日志 + 内容存档（含 HTML 正文供管理端预览）
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS email_logs (
  id                 UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  recipient_email    TEXT        NOT NULL,
  recipient_type     TEXT        NOT NULL CHECK (recipient_type IN ('customer', 'merchant', 'admin')),
  email_code         TEXT        NOT NULL,
  -- 关联业务主键（order_id / order_item_id / merchant_id 等）
  reference_id       UUID,
  subject            TEXT        NOT NULL,
  -- 存储实际发送的 HTML 正文，供管理端预览
  html_body          TEXT,
  status             TEXT        NOT NULL DEFAULT 'pending'
                       CHECK (status IN ('pending', 'sent', 'failed', 'bounced')),
  smtp2go_message_id TEXT,
  error_message      TEXT,
  retry_count        INTEGER     NOT NULL DEFAULT 0,
  sent_at            TIMESTAMPTZ,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 幂等性检查索引（24h 内不重复发送同类邮件到同一收件人）
CREATE INDEX idx_email_logs_dedup
  ON email_logs (email_code, reference_id, recipient_email, created_at DESC);

-- 管理端按类型/状态/时间筛选索引
CREATE INDEX idx_email_logs_filter
  ON email_logs (recipient_type, email_code, status, created_at DESC);

-- RLS
ALTER TABLE email_logs ENABLE ROW LEVEL SECURITY;

-- service_role 写入（Edge Functions 使用 service_role client）
CREATE POLICY "email_logs_service_write" ON email_logs
  FOR ALL
  USING (auth.role() = 'service_role');

-- 管理员可读全部日志
CREATE POLICY "email_logs_admin_read" ON email_logs
  FOR SELECT
  USING (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin'));


-- ─────────────────────────────────────────────────────────────
-- 3. user_email_preferences
--    客户端邮件偏好（仅 user_configurable = TRUE 的邮件类型）
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS user_email_preferences (
  user_id    UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  email_code TEXT        NOT NULL,
  enabled    BOOLEAN     NOT NULL DEFAULT TRUE,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, email_code)
);

-- RLS：用户只能读写自己的偏好
ALTER TABLE user_email_preferences ENABLE ROW LEVEL SECURITY;

CREATE POLICY "user_email_prefs_own" ON user_email_preferences
  FOR ALL
  USING (auth.uid() = user_id);


-- ─────────────────────────────────────────────────────────────
-- 4. merchant_email_preferences
--    商家端邮件偏好（仅 user_configurable = TRUE 的邮件类型）
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS merchant_email_preferences (
  merchant_id UUID        NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
  email_code  TEXT        NOT NULL,
  enabled     BOOLEAN     NOT NULL DEFAULT TRUE,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (merchant_id, email_code)
);

-- RLS：商家只能读写自己的偏好（通过 merchants.user_id 校验）
ALTER TABLE merchant_email_preferences ENABLE ROW LEVEL SECURITY;

CREATE POLICY "merchant_email_prefs_own" ON merchant_email_preferences
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM merchants
      WHERE merchants.id = merchant_email_preferences.merchant_id
        AND merchants.user_id = auth.uid()
    )
  );
