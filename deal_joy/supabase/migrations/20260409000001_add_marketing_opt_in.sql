-- 1. 在 users 表添加 marketing_opt_in 和 analytics_opt_in 字段（默认 false）
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS marketing_opt_in boolean NOT NULL DEFAULT false;

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS analytics_opt_in boolean NOT NULL DEFAULT false;

-- 2. 更新 handle_new_user trigger：从 metadata 读取 marketing_opt_in 和 analytics_opt_in
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  INSERT INTO public.users (
    id, email, full_name, avatar_url, username,
    registration_source, date_of_birth, marketing_opt_in, analytics_opt_in
  )
  VALUES (
    new.id,
    new.email,
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
