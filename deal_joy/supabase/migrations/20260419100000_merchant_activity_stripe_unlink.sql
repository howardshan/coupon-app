-- 扩展商户活动时间线：Stripe 解绑审批结果（Admin Server Action 写入审计）
-- 配套 admin/lib/merchant-activity-events.ts、merchant-admin-timeline.ts

ALTER TABLE public.merchant_activity_events
  DROP CONSTRAINT IF EXISTS merchant_activity_events_event_type_check;

ALTER TABLE public.merchant_activity_events
  ADD CONSTRAINT merchant_activity_events_event_type_check
  CHECK (event_type IN (
    'application_submitted',
    'admin_approved',
    'admin_rejected',
    'admin_revoked_to_pending',
    'store_online_merchant',
    'store_offline_merchant',
    'store_online_admin',
    'store_offline_admin',
    'store_closed_merchant',
    'stripe_unlink_approved',
    'stripe_unlink_rejected'
  ));
