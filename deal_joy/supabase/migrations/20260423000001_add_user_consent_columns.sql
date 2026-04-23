-- 补充 public.users 缺失的同意字段，供 handle_new_user 触发器使用
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS marketing_opt_in  boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS analytics_opt_in  boolean NOT NULL DEFAULT false;
