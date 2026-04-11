-- =============================================================
-- 修复：after_sales_requests 由 Edge Function（service_role）插入时，
-- 触发器 log_after_sales_event 把 JWT role 写入 after_sales_events.actor_role，
-- 但 CHECK 仅允许 user|merchant|platform|system，导致 service_role / authenticated 等
-- 违反约束，整笔 INSERT 失败（客户端看到 insert_failed 500）。
-- =============================================================

CREATE OR REPLACE FUNCTION public.log_after_sales_event()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_actor UUID := auth.uid();
  v_role_raw TEXT := COALESCE(
    current_setting('request.jwt.claims', true)::json->>'role',
    'system'
  );
  v_role TEXT;
  v_action TEXT;
  v_payload JSONB := '{}';
BEGIN
  -- 将 JWT role 映射为 after_sales_events.actor_role 允许的值
  v_role := CASE v_role_raw
    WHEN 'user' THEN 'user'
    WHEN 'merchant' THEN 'merchant'
    WHEN 'platform' THEN 'platform'
    WHEN 'system' THEN 'system'
    WHEN 'authenticated' THEN 'user'
    ELSE 'system'
  END;

  IF TG_OP = 'INSERT' THEN
    v_action := 'submitted';
    v_payload := jsonb_build_object(
      'status', NEW.status,
      'reason_code', NEW.reason_code
    );
  ELSE
    IF NEW.status IS DISTINCT FROM OLD.status THEN
      v_action := 'status_' || NEW.status;
      v_payload := jsonb_build_object(
        'old_status', OLD.status,
        'new_status', NEW.status
      );
    ELSE
      v_action := 'updated';
      v_payload := jsonb_build_object(
        'diff', to_jsonb(NEW) - ARRAY(SELECT column_name::text
                                      FROM information_schema.columns
                                      WHERE table_schema = 'public'
                                        AND table_name = 'after_sales_requests'
                                        AND column_name IN ('id'))
      );
    END IF;
  END IF;

  INSERT INTO public.after_sales_events(request_id, actor_role, actor_id, action, payload)
  VALUES (NEW.id, v_role, v_actor, v_action, v_payload);
  RETURN NEW;
END;
$$;
