-- M22: 员工邀请邮件类型
-- 触发：商家端邀请员工后发送给被邀请人

INSERT INTO email_type_settings (email_code, email_name, recipient_type, global_enabled, user_configurable, description)
VALUES (
  'M22',
  'Staff Invitation',
  'merchant',
  true,
  false,
  'Staff invitation — sent to invited email when a merchant invites a new staff member'
)
ON CONFLICT (email_code) DO UPDATE
  SET email_name        = EXCLUDED.email_name,
      global_enabled    = EXCLUDED.global_enabled,
      user_configurable = EXCLUDED.user_configurable,
      description       = EXCLUDED.description;
