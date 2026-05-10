-- =============================================================
-- handle_new_user：禁止静默失败，避免「auth.users 已创建但 public.users 无行」
--
-- 背景：若函数外层使用 EXCEPTION WHEN OTHERS 仅 WARNING 并 RETURN new，
--       会导致后台（读 public.users）看不到用户，且客户端仍显示注册成功。
--
-- 本迁移：
--   1. 移除「吞掉所有异常」行为 — INSERT 失败时触发器抛出错误，整条注册事务回滚。
--   2. 对 date_of_birth / marketing_opt_in / analytics_opt_in 做安全解析，
--      非法字符串降级为 NULL/false，减少无谓失败。
--   3. 保留 ON CONFLICT (id) DO NOTHING，便于幂等（极少重复触发）。
--
-- 部署：supabase db push --project-ref <ref>（或你们既有 CI 迁移流程）
-- =============================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  resolved_email text;
  v_dob          date;
  v_marketing    boolean;
  v_analytics    boolean;
BEGIN
  resolved_email := COALESCE(
    NULLIF(BTRIM(COALESCE(new.email::text, '')), ''),
    NULLIF(BTRIM(COALESCE(new.raw_user_meta_data->>'email', '')), ''),
    'oauth-' || replace(new.id::text, '-', '') || '@users.local'
  );

  v_dob := NULL;
  IF new.raw_user_meta_data ? 'date_of_birth'
     AND NULLIF(BTRIM(new.raw_user_meta_data->>'date_of_birth'), '') IS NOT NULL
  THEN
    BEGIN
      v_dob := (new.raw_user_meta_data->>'date_of_birth')::date;
    EXCEPTION
      WHEN invalid_text_representation THEN
        v_dob := NULL;
    END;
  END IF;

  v_marketing := false;
  IF new.raw_user_meta_data ? 'marketing_opt_in' THEN
    BEGIN
      v_marketing := COALESCE((new.raw_user_meta_data->>'marketing_opt_in')::boolean, false);
    EXCEPTION
      WHEN invalid_text_representation THEN
        v_marketing := false;
    END;
  END IF;

  v_analytics := false;
  IF new.raw_user_meta_data ? 'analytics_opt_in' THEN
    BEGIN
      v_analytics := COALESCE((new.raw_user_meta_data->>'analytics_opt_in')::boolean, false);
    EXCEPTION
      WHEN invalid_text_representation THEN
        v_analytics := false;
    END;
  END IF;

  INSERT INTO public.users (
    id, email, full_name, avatar_url, username,
    registration_source, date_of_birth,
    marketing_opt_in, analytics_opt_in,
    referral_code
  )
  VALUES (
    new.id,
    resolved_email,
    new.raw_user_meta_data->>'full_name',
    new.raw_user_meta_data->>'avatar_url',
    new.raw_user_meta_data->>'username',
    COALESCE(new.raw_app_meta_data->>'provider', 'email'),
    v_dob,
    v_marketing,
    v_analytics,
    public.generate_referral_code()
  )
  ON CONFLICT (id) DO NOTHING;

  RETURN new;
END;
$$;

COMMENT ON FUNCTION public.handle_new_user() IS
  'auth.users AFTER INSERT：写入 public.users；失败则抛出错误使注册回滚；opt-in/dob 非法值降级。';
