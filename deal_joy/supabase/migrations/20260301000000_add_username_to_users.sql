-- =============================================================
-- Add username column to users table
-- Requirement 1.1.1: username (2-30 chars, alphanumeric, unique)
-- =============================================================

-- 添加 username 列
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS username TEXT;

-- 唯一约束
ALTER TABLE public.users
  ADD CONSTRAINT users_username_unique UNIQUE (username);

-- 长度和格式约束（2-30字符，英文字母和数字）
ALTER TABLE public.users
  ADD CONSTRAINT users_username_format
  CHECK (username ~ '^[a-zA-Z0-9]{2,30}$');

-- 更新 handle_new_user trigger 以支持 username
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  INSERT INTO public.users (id, email, full_name, avatar_url, username)
  VALUES (
    new.id,
    new.email,
    new.raw_user_meta_data->>'full_name',
    new.raw_user_meta_data->>'avatar_url',
    new.raw_user_meta_data->>'username'
  );
  RETURN new;
END;
$$;
