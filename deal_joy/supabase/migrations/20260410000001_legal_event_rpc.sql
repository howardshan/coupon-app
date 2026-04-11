-- ============================================================================
-- 法律事件记录 RPC
-- 用于写入 consent_prompted / consent_declined 等非 consent_given 的事件
-- record_user_consent 仅处理 consent_given 并更新 user_consents 表，
-- 其他事件类型通过本 RPC 写入审计日志（不修改 user_consents）
-- ============================================================================

CREATE OR REPLACE FUNCTION public.record_legal_event(
  p_user_id UUID,
  p_event_type TEXT,
  p_document_slug TEXT,
  p_actor_role TEXT,
  p_details JSONB DEFAULT '{}'::jsonb,
  p_ip_address INET DEFAULT NULL,
  p_user_agent TEXT DEFAULT NULL,
  p_device_info TEXT DEFAULT NULL,
  p_app_version TEXT DEFAULT NULL,
  p_platform TEXT DEFAULT NULL,
  p_locale TEXT DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_doc RECORD;
  v_hash TEXT;
  v_log_id UUID;
BEGIN
  -- 校验 event_type（只允许本 RPC 处理的非 consent_given 事件）
  IF p_event_type NOT IN ('consent_prompted', 'consent_declined', 'consent_superseded') THEN
    RAISE EXCEPTION 'record_legal_event only handles prompted/declined/superseded events. Use record_user_consent for consent_given.';
  END IF;

  -- 获取文档信息
  SELECT id, slug, title, current_version
  INTO v_doc
  FROM legal_documents
  WHERE slug = p_document_slug AND is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Legal document not found: %', p_document_slug;
  END IF;

  -- 生成审计日志 ID
  v_log_id := gen_random_uuid();

  -- 计算完整性哈希
  v_hash := encode(
    digest(
      v_log_id::text || p_user_id::text || p_event_type || v_doc.id::text || v_doc.current_version::text || now()::text,
      'sha256'
    ),
    'hex'
  );

  -- 写入审计日志
  INSERT INTO legal_audit_log (
    id, user_id, actor_id, actor_role,
    event_type, document_id, document_slug, document_title, document_version,
    details,
    ip_address, user_agent, device_info, app_version, platform, locale,
    integrity_hash
  ) VALUES (
    v_log_id, p_user_id, p_user_id, p_actor_role,
    p_event_type, v_doc.id, v_doc.slug, v_doc.title, v_doc.current_version,
    p_details,
    p_ip_address, p_user_agent, p_device_info, p_app_version, p_platform, p_locale,
    v_hash
  );
END;
$function$;

-- 授予权限
GRANT EXECUTE ON FUNCTION public.record_legal_event TO authenticated;

COMMENT ON FUNCTION public.record_legal_event IS
  '写入 consent_prompted / consent_declined / consent_superseded 等审计事件。consent_given 请用 record_user_consent。';
