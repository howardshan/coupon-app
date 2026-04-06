-- 商户审批与可见性等活动时间线事件（追加写入，供 Admin 详情页展示完整历史）
-- 注释：INSERT 主要由 service_role / Edge Function / Server Action 完成；authenticated 仅 SELECT。

CREATE TABLE IF NOT EXISTS public.merchant_activity_events (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id     uuid NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  created_at      timestamptz NOT NULL DEFAULT now(),
  event_type      text NOT NULL,
  actor_type      text NOT NULL,
  actor_user_id   uuid REFERENCES public.users(id) ON DELETE SET NULL,
  detail          text,
  CONSTRAINT merchant_activity_events_actor_type_check
    CHECK (actor_type IN ('admin', 'merchant_owner', 'system')),
  CONSTRAINT merchant_activity_events_event_type_check
    CHECK (event_type IN (
      'application_submitted',
      'admin_approved',
      'admin_rejected',
      'admin_revoked_to_pending',
      'store_online_merchant',
      'store_offline_merchant',
      'store_online_admin',
      'store_offline_admin',
      'store_closed_merchant'
    ))
);

CREATE INDEX IF NOT EXISTS idx_merchant_activity_events_merchant_created
  ON public.merchant_activity_events (merchant_id, created_at ASC);

COMMENT ON TABLE public.merchant_activity_events IS '商户侧活动审计：申请提交、审批、上下线、闭店等；detail 存驳回原因等';

ALTER TABLE public.merchant_activity_events ENABLE ROW LEVEL SECURITY;

-- Admin 可读全部
CREATE POLICY "admin_read_all_merchant_activity_events"
  ON public.merchant_activity_events
  FOR SELECT
  USING (public.is_admin());

-- 门店主账号可读本店事件
CREATE POLICY "merchant_owner_read_own_activity_events"
  ON public.merchant_activity_events
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.merchants m
      WHERE m.id = merchant_activity_events.merchant_id
        AND m.user_id = auth.uid()
    )
  );

-- 无 INSERT/UPDATE/DELETE 策略：仅 service_role 等绕过 RLS 写入
