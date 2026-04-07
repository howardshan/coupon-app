-- ============================================================
-- 法律文档系统 — 完整 Migration
-- 包含：4 张表、RLS 策略、防篡改 Triggers、RPC 函数、初始数据
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- 1. legal_documents — 法律文档主表
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS legal_documents (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  slug        TEXT UNIQUE NOT NULL,          -- 'terms-of-service', 'privacy-policy' 等
  title       TEXT NOT NULL,                  -- 显示标题
  document_type TEXT NOT NULL                 -- 'user' | 'merchant' | 'both'
    CHECK (document_type IN ('user', 'merchant', 'both')),
  requires_re_consent BOOLEAN DEFAULT false,  -- 更新后是否需要用户重新同意
  current_version     INTEGER DEFAULT 0,      -- 当前已发布版本号（0=尚无发布版本）
  is_active           BOOLEAN DEFAULT true,
  created_at  TIMESTAMPTZ DEFAULT now(),
  updated_at  TIMESTAMPTZ DEFAULT now()
);

-- 自动更新 updated_at
CREATE OR REPLACE FUNCTION update_legal_documents_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_legal_documents_updated_at
  BEFORE UPDATE ON legal_documents
  FOR EACH ROW EXECUTE FUNCTION update_legal_documents_updated_at();

-- ────────────────────────────────────────────────────────────
-- 2. legal_document_versions — 版本历史（已发布版本不可修改/删除）
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS legal_document_versions (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  document_id   UUID NOT NULL REFERENCES legal_documents(id) ON DELETE CASCADE,
  version       INTEGER NOT NULL,
  content_html  TEXT NOT NULL,                 -- 富文本 HTML 内容
  summary_of_changes TEXT,                     -- 本次更新摘要（给用户看）
  published_at  TIMESTAMPTZ,                   -- null = 草稿, 非 null = 已发布
  published_by  UUID REFERENCES public.users(id),
  created_at    TIMESTAMPTZ DEFAULT now(),
  UNIQUE(document_id, version)
);

-- 已发布版本禁止修改或删除（合规要求）
CREATE OR REPLACE FUNCTION prevent_published_version_modification()
RETURNS TRIGGER AS $$
BEGIN
  IF OLD.published_at IS NOT NULL THEN
    RAISE EXCEPTION 'COMPLIANCE: Published legal document versions cannot be modified or deleted.';
    RETURN NULL;
  END IF;
  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prevent_published_version_update
  BEFORE UPDATE ON legal_document_versions
  FOR EACH ROW EXECUTE FUNCTION prevent_published_version_modification();

CREATE TRIGGER trg_prevent_published_version_delete
  BEFORE DELETE ON legal_document_versions
  FOR EACH ROW EXECUTE FUNCTION prevent_published_version_modification();

-- ────────────────────────────────────────────────────────────
-- 3. user_consents — 用户/商家当前同意状态（快速查询用）
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS user_consents (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  document_id   UUID NOT NULL REFERENCES legal_documents(id) ON DELETE CASCADE,
  version       INTEGER NOT NULL,
  consented_at  TIMESTAMPTZ DEFAULT now(),
  ip_address    INET,
  user_agent    TEXT,
  UNIQUE(user_id, document_id)
);

CREATE INDEX idx_user_consents_user_id ON user_consents(user_id);

-- ────────────────────────────────────────────────────────────
-- 4. legal_audit_log — 不可篡改审计日志（核心合规表）
--    用于审计、合规、诉讼举证
--    APPEND-ONLY: 禁止 UPDATE / DELETE
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS legal_audit_log (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- 事件主体
  user_id         UUID NOT NULL,                -- 涉及的用户/商家
  actor_id        UUID,                          -- 操作人（用户自己 or admin）
  actor_role      TEXT NOT NULL                   -- 'user' | 'merchant' | 'admin' | 'system'
    CHECK (actor_role IN ('user', 'merchant', 'admin', 'system')),

  -- 事件类型
  event_type      TEXT NOT NULL
    CHECK (event_type IN (
      'consent_given',            -- 用户同意某文档
      'consent_superseded',       -- 新版本发布导致旧同意失效
      'consent_prompted',         -- 用户被弹窗要求同意（但尚未操作）
      'consent_declined',         -- 用户拒绝同意（关闭弹窗/App）
      'document_created',         -- Admin 创建新法律文档
      'document_published',       -- Admin 发布新版本
      'document_setting_changed', -- Admin 修改文档设置
      'document_deactivated',     -- Admin 停用法律文档
      'document_activated'        -- Admin 启用法律文档
    )),

  -- 关联文档（冗余存储，防止文档 slug/title 修改后丢失历史关联）
  document_id     UUID REFERENCES legal_documents(id),
  document_slug   TEXT,
  document_title  TEXT,
  document_version INTEGER,

  -- 详情（JSONB，根据 event_type 存储不同内容）
  -- consent_given:          { "consent_method": "registration|barrier|manual", "trigger_context": "app_launch|checkout|withdrawal|..." }
  -- document_published:     { "summary_of_changes": "...", "previous_version": 2, "requires_re_consent": true }
  -- consent_superseded:     { "old_version": 1, "new_version": 2 }
  -- document_setting_changed: { "field": "requires_re_consent", "old_value": false, "new_value": true }
  details         JSONB DEFAULT '{}',

  -- 客户端环境信息（尽可能详细）
  ip_address      INET,
  user_agent      TEXT,
  device_info     TEXT,                          -- 设备型号 "iPhone 15 Pro, iOS 18.2"
  app_version     TEXT,                          -- App 版本号
  platform        TEXT                           -- 'ios' | 'android' | 'web' | 'admin'
    CHECK (platform IN ('ios', 'android', 'web', 'admin')),
  locale          TEXT,                          -- 客户端语言

  -- 时间戳
  created_at      TIMESTAMPTZ DEFAULT now() NOT NULL,

  -- 完整性校验哈希（SHA256，防篡改验证）
  integrity_hash  TEXT NOT NULL
);

-- 索引
CREATE INDEX idx_legal_audit_log_user_id ON legal_audit_log(user_id, created_at DESC);
CREATE INDEX idx_legal_audit_log_document_id ON legal_audit_log(document_id, created_at DESC);
CREATE INDEX idx_legal_audit_log_event_type ON legal_audit_log(event_type, created_at DESC);

-- APPEND-ONLY: 禁止任何人（包括 service_role）UPDATE 或 DELETE
CREATE OR REPLACE FUNCTION prevent_audit_log_modification()
RETURNS TRIGGER AS $$
BEGIN
  RAISE EXCEPTION 'COMPLIANCE: legal_audit_log is append-only. UPDATE and DELETE are strictly prohibited.';
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prevent_audit_log_update
  BEFORE UPDATE ON legal_audit_log
  FOR EACH ROW EXECUTE FUNCTION prevent_audit_log_modification();

CREATE TRIGGER trg_prevent_audit_log_delete
  BEFORE DELETE ON legal_audit_log
  FOR EACH ROW EXECUTE FUNCTION prevent_audit_log_modification();

-- ────────────────────────────────────────────────────────────
-- 5. RLS 策略
-- ────────────────────────────────────────────────────────────
ALTER TABLE legal_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE legal_document_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_consents ENABLE ROW LEVEL SECURITY;
ALTER TABLE legal_audit_log ENABLE ROW LEVEL SECURITY;

-- legal_documents: 所有已登录用户可读
CREATE POLICY "legal_documents_select_authenticated"
  ON legal_documents FOR SELECT
  TO authenticated
  USING (true);

-- legal_documents: admin 可写（通过 service_role 绕过）

-- legal_document_versions: 已登录用户可读已发布版本
CREATE POLICY "legal_document_versions_select_published"
  ON legal_document_versions FOR SELECT
  TO authenticated
  USING (published_at IS NOT NULL);

-- user_consents: 用户只能读自己的
CREATE POLICY "user_consents_select_own"
  ON user_consents FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

-- user_consents: 用户只能写自己的
CREATE POLICY "user_consents_insert_own"
  ON user_consents FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "user_consents_update_own"
  ON user_consents FOR UPDATE
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- legal_audit_log: 仅允许 INSERT
CREATE POLICY "legal_audit_log_insert_authenticated"
  ON legal_audit_log FOR INSERT
  TO authenticated
  WITH CHECK (true);

-- legal_audit_log: 用户只能读自己的记录
CREATE POLICY "legal_audit_log_select_own"
  ON legal_audit_log FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

-- Admin 通过 service_role 客户端读写所有表，不受 RLS 限制

-- ────────────────────────────────────────────────────────────
-- 6. RPC 函数
-- ────────────────────────────────────────────────────────────

-- 检查用户是否有待同意的文档（App 启动时 / 关键操作前调用）
CREATE OR REPLACE FUNCTION check_pending_consents(p_user_id UUID, p_role TEXT)
RETURNS TABLE(
  document_id UUID,
  slug TEXT,
  title TEXT,
  current_version INTEGER,
  user_version INTEGER,
  summary_of_changes TEXT
) AS $$
  SELECT
    ld.id,
    ld.slug,
    ld.title,
    ld.current_version,
    COALESCE(uc.version, 0),
    ldv.summary_of_changes
  FROM legal_documents ld
  LEFT JOIN user_consents uc
    ON uc.document_id = ld.id AND uc.user_id = p_user_id
  LEFT JOIN legal_document_versions ldv
    ON ldv.document_id = ld.id AND ldv.version = ld.current_version
  WHERE ld.is_active = true
    AND ld.requires_re_consent = true
    AND ld.current_version > 0
    AND (ld.document_type = p_role OR ld.document_type = 'both')
    AND (uc.version IS NULL OR uc.version < ld.current_version);
$$ LANGUAGE sql SECURITY DEFINER;

-- 获取法律文档内容（给 App 展示用）
CREATE OR REPLACE FUNCTION get_legal_document_content(p_slug TEXT, p_version INTEGER DEFAULT NULL)
RETURNS TABLE(
  document_id UUID,
  slug TEXT,
  title TEXT,
  version INTEGER,
  content_html TEXT,
  summary_of_changes TEXT,
  published_at TIMESTAMPTZ
) AS $$
  SELECT
    ld.id,
    ld.slug,
    ld.title,
    ldv.version,
    ldv.content_html,
    ldv.summary_of_changes,
    ldv.published_at
  FROM legal_documents ld
  JOIN legal_document_versions ldv
    ON ldv.document_id = ld.id
  WHERE ld.slug = p_slug
    AND ldv.published_at IS NOT NULL
    AND ldv.version = COALESCE(p_version, ld.current_version);
$$ LANGUAGE sql SECURITY DEFINER;

-- 记录用户同意（写入 user_consents + legal_audit_log）
CREATE OR REPLACE FUNCTION record_user_consent(
  p_user_id UUID,
  p_document_slug TEXT,
  p_actor_role TEXT,
  p_consent_method TEXT,           -- 'registration' | 'barrier' | 'manual'
  p_trigger_context TEXT,          -- 'app_launch' | 'checkout' | 'registration' | ...
  p_ip_address INET DEFAULT NULL,
  p_user_agent TEXT DEFAULT NULL,
  p_device_info TEXT DEFAULT NULL,
  p_app_version TEXT DEFAULT NULL,
  p_platform TEXT DEFAULT NULL,
  p_locale TEXT DEFAULT NULL
) RETURNS VOID AS $$
DECLARE
  v_doc RECORD;
  v_hash TEXT;
  v_log_id UUID;
BEGIN
  -- 获取文档信息
  SELECT id, slug, title, current_version
  INTO v_doc
  FROM legal_documents
  WHERE slug = p_document_slug AND is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Legal document not found: %', p_document_slug;
  END IF;

  -- 写入/更新 user_consents（快速查询表）
  INSERT INTO user_consents (user_id, document_id, version, consented_at, ip_address, user_agent)
  VALUES (p_user_id, v_doc.id, v_doc.current_version, now(), p_ip_address, p_user_agent)
  ON CONFLICT (user_id, document_id)
  DO UPDATE SET
    version = v_doc.current_version,
    consented_at = now(),
    ip_address = p_ip_address,
    user_agent = p_user_agent;

  -- 生成审计日志 ID
  v_log_id := gen_random_uuid();

  -- 计算完整性哈希
  v_hash := encode(
    digest(
      v_log_id::text || p_user_id::text || 'consent_given' || v_doc.id::text || v_doc.current_version::text || now()::text,
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
    'consent_given', v_doc.id, v_doc.slug, v_doc.title, v_doc.current_version,
    jsonb_build_object(
      'consent_method', p_consent_method,
      'trigger_context', p_trigger_context
    ),
    p_ip_address, p_user_agent, p_device_info, p_app_version, p_platform, p_locale,
    v_hash
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ────────────────────────────────────────────────────────────
-- 7. 初始数据 — 7 个法律文档（内容待 Admin 填写）
-- ────────────────────────────────────────────────────────────
INSERT INTO legal_documents (slug, title, document_type, requires_re_consent, current_version) VALUES
  ('terms-of-service',     'Terms of Service',      'both',     true,  0),
  ('privacy-policy',       'Privacy Policy',        'both',     true,  0),
  ('refund-policy',        'Refund Policy',         'user',     false, 0),
  ('merchant-agreement',   'Merchant Agreement',    'merchant', true,  0),
  ('payment-terms',        'Payment Terms',         'both',     false, 0),
  ('advertising-terms',    'Advertising Terms',     'merchant', false, 0),
  ('gift-terms',           'Gift Terms',            'user',     false, 0)
ON CONFLICT (slug) DO NOTHING;

-- 需要 pgcrypto 扩展（用于 SHA256 哈希）
CREATE EXTENSION IF NOT EXISTS pgcrypto;
