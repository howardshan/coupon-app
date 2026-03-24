-- 添加 C14（管理员拒绝退款通知）和 M17（Deal审批通过通知）到邮件类型设置表

INSERT INTO email_type_settings (email_code, email_name, description, global_enabled, user_configurable, recipient_type)
VALUES
  (
    'C14',
    'Admin Refund Rejected',
    'Admin refund rejected — final decision notification sent to customer when admin declines escalated refund request',
    true,
    false,
    'customer'
  ),
  (
    'M17',
    'Deal Approved',
    'Deal approved — notification sent to merchant when admin approves and publishes a deal',
    true,
    false,
    'merchant'
  )
ON CONFLICT (email_code) DO NOTHING;
