-- Admin 后台对 merchant_staff 的操作写入活动时间线审计

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
    'stripe_unlink_rejected',
    'admin_staff_invited',
    'admin_staff_role_changed',
    'admin_staff_removed',
    'admin_staff_status_changed'
  ));
