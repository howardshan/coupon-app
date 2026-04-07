-- ============================================================
-- 法律文档占位符配置表
-- 平台方在 Admin 后台统一填写，发布法律文档时自动替换
-- ============================================================

CREATE TABLE IF NOT EXISTS legal_placeholders (
  key         TEXT PRIMARY KEY,           -- 占位符 key，如 'SUPPORT_EMAIL'
  placeholder TEXT NOT NULL,              -- 在文档中的占位符文本，如 '[SUPPORT EMAIL]'
  value       TEXT NOT NULL DEFAULT '',   -- 平台方填写的实际值
  description TEXT,                       -- 说明，帮助管理员理解用途
  created_at  TIMESTAMPTZ DEFAULT now(),
  updated_at  TIMESTAMPTZ DEFAULT now()
);

-- 自动更新 updated_at
CREATE OR REPLACE FUNCTION update_legal_placeholders_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_legal_placeholders_updated_at
  BEFORE UPDATE ON legal_placeholders
  FOR EACH ROW EXECUTE FUNCTION update_legal_placeholders_updated_at();

-- RLS：所有已登录用户可读（App 端渲染文档时需要），admin 可写
ALTER TABLE legal_placeholders ENABLE ROW LEVEL SECURITY;

CREATE POLICY "legal_placeholders_select_authenticated"
  ON legal_placeholders FOR SELECT
  TO authenticated
  USING (true);

-- 初始占位符数据
INSERT INTO legal_placeholders (key, placeholder, value, description) VALUES
  ('SUPPORT_EMAIL',     '[SUPPORT EMAIL]',     '',  'Customer support email address (e.g. support@crunchyplum.com)'),
  ('REFUND_POLICY_URL', '[REFUND POLICY URL]', '',  'Full URL to Refund Policy page'),
  ('GIFT_TERMS_URL',    '[GIFT TERMS URL]',    '',  'Full URL to Gift Terms page'),
  ('DMCA_AGENT_NAME',   '[NAME]',              '',  'DMCA designated agent full name'),
  ('DMCA_AGENT_EMAIL',  '[DMCA EMAIL]',        '',  'DMCA designated agent email address'),
  ('WEBSITE_URL',       '[WEBSITE URL]',       '',  'Company website URL (e.g. https://crunchyplum.com)'),
  ('COMPANY_ADDRESS',   '[ADDRESS]',           '616 Rockcrossing Ln, Allen, TX 75013', 'Company mailing address')
ON CONFLICT (key) DO NOTHING;

-- RPC：获取所有占位符并替换文档内容中的占位符
CREATE OR REPLACE FUNCTION render_legal_document(p_content_html TEXT)
RETURNS TEXT AS $$
DECLARE
  v_rec RECORD;
  v_result TEXT := p_content_html;
BEGIN
  -- 替换所有已配置的占位符
  FOR v_rec IN SELECT placeholder, value FROM legal_placeholders WHERE value != '' LOOP
    v_result := replace(v_result, v_rec.placeholder, v_rec.value);
  END LOOP;

  -- 自动替换日期和年份
  v_result := replace(v_result, '[DATE]', to_char(CURRENT_DATE, 'Month DD, YYYY'));
  v_result := replace(v_result, '[YEAR]', to_char(CURRENT_DATE, 'YYYY'));

  RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
