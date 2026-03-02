-- =============================================================
-- 登录追踪：last_login_at + login_history 表
-- =============================================================

-- 1. users 表添加 last_login_at 字段
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS last_login_at TIMESTAMPTZ;

-- 2. 创建 login_history 表
CREATE TABLE IF NOT EXISTS public.login_history (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  logged_in_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  provider    TEXT,          -- 'email' | 'google' | 'apple'
  ip_address  TEXT,          -- 由客户端或 edge function 填入
  user_agent  TEXT,          -- 设备/浏览器信息
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 索引：按用户 + 时间查询
CREATE INDEX IF NOT EXISTS idx_login_history_user_id
  ON public.login_history(user_id, logged_in_at DESC);

-- 3. RLS 策略：用户只能查看自己的登录记录
ALTER TABLE public.login_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own login history"
  ON public.login_history FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own login history"
  ON public.login_history FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- 4. 触发器：登录时自动更新 users.last_login_at
-- 注意：Supabase auth 不直接触发 public 表的 trigger，
-- 所以 last_login_at 由客户端在登录成功后调用 RPC 更新
CREATE OR REPLACE FUNCTION public.record_login(
  p_provider TEXT DEFAULT 'email',
  p_ip_address TEXT DEFAULT NULL,
  p_user_agent TEXT DEFAULT NULL
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  -- 更新 last_login_at
  UPDATE public.users
  SET last_login_at = now(), updated_at = now()
  WHERE id = auth.uid();

  -- 插入登录历史
  INSERT INTO public.login_history (user_id, provider, ip_address, user_agent)
  VALUES (auth.uid(), p_provider, p_ip_address, p_user_agent);
END;
$$;
