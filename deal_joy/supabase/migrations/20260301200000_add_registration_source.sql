-- =============================================================
-- Add registration_source column to users table
-- 记录用户注册来源（email / google / apple 等）
-- =============================================================

-- 添加 registration_source 列
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS registration_source TEXT DEFAULT 'email';

-- 更新 handle_new_user trigger：自动从 auth.users 的 app_metadata 读取 provider
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  INSERT INTO public.users (id, email, full_name, avatar_url, username, registration_source)
  VALUES (
    new.id,
    new.email,
    new.raw_user_meta_data->>'full_name',
    new.raw_user_meta_data->>'avatar_url',
    new.raw_user_meta_data->>'username',
    COALESCE(new.raw_app_meta_data->>'provider', 'email')
  );
  RETURN new;
END;
$$;

-- 回填已有用户的 registration_source（从 auth.users 读取）
UPDATE public.users u
SET registration_source = COALESCE(
  (SELECT raw_app_meta_data->>'provider' FROM auth.users a WHERE a.id = u.id),
  'email'
)
WHERE u.registration_source IS NULL OR u.registration_source = 'email';
