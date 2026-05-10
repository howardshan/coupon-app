-- =============================================================
-- pgcrypto + generate_referral_code：修复注册时 gen_random_bytes 不存在
--
-- 现象：handle_new_user → generate_referral_code() 调用 gen_random_bytes(1)
--       报错 function gen_random_bytes(integer) does not exist（42883）
-- 原因：生产库未启用 pgcrypto，或扩展在 extensions schema 而函数 search_path 未包含。
--
-- 做法：
--   1. 在 extensions schema 下确保启用 pgcrypto（与 Supabase 托管惯例一致）
--   2. 重建 generate_referral_code，SET search_path = public, extensions
--   3. 授权常用角色使用 extensions schema（旧库若扩展已在 public，IF NOT EXISTS 则跳过，search_path 仍能解析 public）
-- =============================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

GRANT USAGE ON SCHEMA extensions TO postgres, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.generate_referral_code()
RETURNS text
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
  chars  CONSTANT text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  result text := '';
  byte   int;
  i      int;
BEGIN
  FOR attempt IN 1..10 LOOP
    result := '';
    FOR i IN 1..8 LOOP
      byte := get_byte(gen_random_bytes(1), 0) % length(chars) + 1;
      result := result || substr(chars, byte, 1);
    END LOOP;
    IF NOT EXISTS (SELECT 1 FROM public.users WHERE referral_code = result) THEN
      RETURN result;
    END IF;
  END LOOP;
  RAISE EXCEPTION 'Failed to generate unique referral_code after 10 attempts';
END;
$$;

COMMENT ON FUNCTION public.generate_referral_code() IS
  '生成唯一 referral_code；依赖 pgcrypto.gen_random_bytes；search_path 含 extensions。';
