-- OAuth（如 Sign in with Apple）可能无 auth.users.email；public.users.email 为 NOT NULL。
-- 使用 metadata 邮箱或稳定占位，避免 trigger 插入失败；商家入驻时 merchant-register 会用 contact_email 覆盖。

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  resolved_email text;
BEGIN
  resolved_email := COALESCE(
    NULLIF(BTRIM(COALESCE(new.email::text, '')), ''),
    NULLIF(BTRIM(COALESCE(new.raw_user_meta_data->>'email', '')), ''),
    'oauth-' || replace(new.id::text, '-', '') || '@users.local'
  );

  INSERT INTO public.users (
    id, email, full_name, avatar_url, username,
    registration_source, date_of_birth, marketing_opt_in, analytics_opt_in
  )
  VALUES (
    new.id,
    resolved_email,
    new.raw_user_meta_data->>'full_name',
    new.raw_user_meta_data->>'avatar_url',
    new.raw_user_meta_data->>'username',
    COALESCE(new.raw_app_meta_data->>'provider', 'email'),
    CASE
      WHEN new.raw_user_meta_data->>'date_of_birth' IS NOT NULL
      THEN (new.raw_user_meta_data->>'date_of_birth')::date
      ELSE NULL
    END,
    COALESCE((new.raw_user_meta_data->>'marketing_opt_in')::boolean, false),
    COALESCE((new.raw_user_meta_data->>'analytics_opt_in')::boolean, false)
  );
  RETURN new;
END;
$$;
