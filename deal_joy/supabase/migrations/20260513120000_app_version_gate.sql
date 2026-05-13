-- =============================================================
-- 移动端强制更新闸门：按 app_key 配置最低版本与商店链接
-- 客户端 anon 可读；仅 service_role 可写（管理后台）
-- =============================================================

CREATE TABLE IF NOT EXISTS public.app_version_gate (
  app_key               text PRIMARY KEY
    CHECK (app_key IN ('consumer', 'merchant')),
  force_update_enabled  boolean NOT NULL DEFAULT false,
  min_supported_version text NOT NULL DEFAULT '0.0.0',
  message_title         text,
  message_body          text,
  ios_store_url         text,
  android_store_url     text,
  updated_at            timestamptz NOT NULL DEFAULT now(),
  updated_by            uuid REFERENCES public.users (id),
  CONSTRAINT app_version_gate_min_semver CHECK (
    min_supported_version ~ '^\d+\.\d+(\.\d+)?$'
  )
);

COMMENT ON TABLE public.app_version_gate IS
  'App 强制更新闸门：force_update_enabled 且当前版本低于 min_supported_version 时拦截';

INSERT INTO public.app_version_gate (app_key, force_update_enabled, min_supported_version)
VALUES
  ('consumer', false, '0.0.0'),
  ('merchant', false, '0.0.0')
ON CONFLICT (app_key) DO NOTHING;

ALTER TABLE public.app_version_gate ENABLE ROW LEVEL SECURITY;

CREATE POLICY "app_version_gate_select_all"
  ON public.app_version_gate
  FOR SELECT
  USING (true);

CREATE POLICY "app_version_gate_insert_service_role"
  ON public.app_version_gate
  FOR INSERT
  TO service_role
  WITH CHECK (true);

CREATE POLICY "app_version_gate_update_service_role"
  ON public.app_version_gate
  FOR UPDATE
  TO service_role
  USING (true)
  WITH CHECK (true);

CREATE POLICY "app_version_gate_delete_service_role"
  ON public.app_version_gate
  FOR DELETE
  TO service_role
  USING (true);
