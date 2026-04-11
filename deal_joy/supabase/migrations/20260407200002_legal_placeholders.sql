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
  ('REFUND_POLICY_URL', '[REFUND POLICY URL]', 'https://crunchyplum.com/legal/refund-policy',  'Full URL to Refund Policy page'),
  ('GIFT_TERMS_URL',    '[GIFT TERMS URL]',    'https://crunchyplum.com/legal/gift-terms',    'Full URL to Gift Terms page'),
  ('DMCA_AGENT_NAME',   '[NAME]',              '',  'DMCA designated agent full name'),
  ('DMCA_AGENT_EMAIL',  '[DMCA EMAIL]',        '',  'DMCA designated agent email address'),
  ('WEBSITE_URL',       '[WEBSITE URL]',       'https://crunchyplum.com',  'Company website URL'),
  ('COMPANY_ADDRESS',   '[ADDRESS]',           '616 Rockcrossing Ln, Allen, TX 75013', 'Company mailing address'),
  ('MERCHANT_SUPPORT_EMAIL', '[MERCHANT SUPPORT EMAIL]', '', 'Merchant support email address (may differ from customer support)'),
  ('COMMISSION_RATE',        '[COMMISSION RATE]',        '', 'Platform commission percentage (e.g. 20)'),
  ('RESERVE_RATE',           '[RESERVE RATE]',           '', 'Rolling reserve percentage (e.g. 10)'),
  ('MINIMUM_WITHDRAWAL_AMOUNT', '[MINIMUM WITHDRAWAL AMOUNT]', '', 'Minimum merchant withdrawal amount in USD (e.g. $50.00)'),
  ('PRIVACY_EMAIL',             '[PRIVACY EMAIL]',             '', 'Privacy/data protection contact email (e.g. privacy@crunchyplum.com)')
ON CONFLICT (key) DO NOTHING;

-- RPC：获取所有占位符并替换文档内容中的占位符
-- 带 merchant_id 版本：优先使用商家独立佣金，否则用平台默认
DROP FUNCTION IF EXISTS render_legal_document(TEXT);
DROP FUNCTION IF EXISTS render_legal_document(TEXT, UUID);

CREATE FUNCTION render_legal_document(p_content_html TEXT, p_merchant_id UUID DEFAULT NULL)
RETURNS TEXT AS $$
DECLARE
  v_rec RECORD;
  v_result TEXT := p_content_html;
  v_commission_rate DECIMAL;
BEGIN
  -- 替换所有已配置的占位符
  FOR v_rec IN SELECT placeholder, value FROM legal_placeholders WHERE value != '' LOOP
    v_result := replace(v_result, v_rec.placeholder, v_rec.value);
  END LOOP;

  -- 佣金比例：优先使用商家独立 rate，否则用平台默认
  IF p_merchant_id IS NOT NULL THEN
    SELECT commission_rate INTO v_commission_rate
    FROM merchants WHERE id = p_merchant_id AND commission_rate IS NOT NULL;
  END IF;
  -- 回退到平台默认
  IF v_commission_rate IS NULL THEN
    SELECT commission_rate INTO v_commission_rate FROM platform_commission_config LIMIT 1;
  END IF;
  IF v_commission_rate IS NOT NULL THEN
    v_result := replace(v_result, '[COMMISSION RATE]',
      trim(trailing '0' from trim(trailing '.' from (v_commission_rate * 100)::TEXT)));
  END IF;

  -- 自动替换日期和年份
  v_result := replace(v_result, '[DATE]', to_char(CURRENT_DATE, 'Month DD, YYYY'));
  v_result := replace(v_result, '[YEAR]', to_char(CURRENT_DATE, 'YYYY'));

  RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
