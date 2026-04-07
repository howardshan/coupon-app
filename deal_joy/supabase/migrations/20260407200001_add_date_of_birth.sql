-- ============================================================
-- 用户生日字段 + 未满 18 岁禁止交易
-- ============================================================

-- 1. 添加 date_of_birth 列到 users 表
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS date_of_birth DATE;

-- 2. 更新 handle_new_user trigger：自动从 auth.users metadata 读取 date_of_birth
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  INSERT INTO public.users (id, email, full_name, avatar_url, username, registration_source, date_of_birth)
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
    END
  );
  RETURN new;
END;
$$;

-- 3. RPC 函数：检查用户是否满 18 岁（App 端结账前调用）
CREATE OR REPLACE FUNCTION check_user_age_eligible(p_user_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
  v_dob DATE;
BEGIN
  SELECT date_of_birth INTO v_dob
  FROM public.users
  WHERE id = p_user_id;

  -- 未填写生日视为不合格
  IF v_dob IS NULL THEN
    RETURN FALSE;
  END IF;

  -- 年龄 >= 18
  RETURN (v_dob <= CURRENT_DATE - INTERVAL '18 years');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
