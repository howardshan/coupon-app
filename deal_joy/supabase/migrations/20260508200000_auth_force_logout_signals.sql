-- =============================================================
-- 整账号删除：跨端即时登出信号（Realtime INSERT）
-- 仅 full 删号流程写入；客户端订阅本表后弹窗再 signOut
-- =============================================================

CREATE TABLE IF NOT EXISTS public.auth_force_logout_signals (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  reason     text NOT NULL DEFAULT 'account_deleted',
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_auth_force_logout_signals_user_id
  ON public.auth_force_logout_signals (user_id, created_at DESC);

COMMENT ON TABLE public.auth_force_logout_signals IS
  '整账号删除前广播：其他设备 Realtime 收到后提示用户并登出';

ALTER TABLE public.auth_force_logout_signals ENABLE ROW LEVEL SECURITY;

-- 仅允许查看自己的信号行（用于 Realtime postgres_changes）
CREATE POLICY "auth_force_logout_signals_select_own"
  ON public.auth_force_logout_signals
  FOR SELECT
  USING (auth.uid() = user_id);

-- INSERT/UPDATE/DELETE：authenticated 无策略即拒绝；service_role 绕过 RLS

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = 'auth_force_logout_signals'
    ) THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.auth_force_logout_signals;
    END IF;
  END IF;
END $$;
