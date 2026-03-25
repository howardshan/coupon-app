-- 注册 M18 邮件类型：提现失败通知（发给商家）
-- 触发时机：Stripe Transfer 失败（stripe-webhook transfer.failed 事件）

INSERT INTO email_type_settings (email_code, email_name, recipient_type, user_configurable)
VALUES ('M18', 'Withdrawal Failed', 'merchant', FALSE)
ON CONFLICT (email_code) DO NOTHING;
