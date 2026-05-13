-- 按邮箱查询 auth 侧验证状态（供注册页区分「已验证 / 待验证」）
-- 不暴露其他字段；SECURITY DEFINER 读取 auth.users

CREATE OR REPLACE FUNCTION public.email_auth_status(p_email text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_email   text := lower(trim(p_email));
  v_conf    timestamptz;
BEGIN
  IF v_email IS NULL OR v_email = '' THEN
    RETURN 'none';
  END IF;

  SELECT u.email_confirmed_at
    INTO v_conf
    FROM auth.users u
   WHERE lower(u.email) = v_email
   LIMIT 1;

  IF NOT FOUND THEN
    RETURN 'none';
  END IF;

  IF v_conf IS NOT NULL THEN
    RETURN 'confirmed';
  END IF;

  RETURN 'unconfirmed';
END;
$$;

COMMENT ON FUNCTION public.email_auth_status(text) IS
  'Returns none | unconfirmed | confirmed for signup/login UX (no PII beyond existence).';

REVOKE ALL ON FUNCTION public.email_auth_status(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.email_auth_status(text) TO anon;
GRANT EXECUTE ON FUNCTION public.email_auth_status(text) TO authenticated;
