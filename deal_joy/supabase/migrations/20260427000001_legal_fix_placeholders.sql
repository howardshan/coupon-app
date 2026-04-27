-- ============================================================
-- 补充法律文档缺失占位符
-- 1. SERVICE_FEE — TOS Section 5 和 Refund Policy 均引用但表中缺失
-- 2. EFFECTIVE_DATE / LAST_UPDATED — 各文档头部占位符未定义
-- ============================================================

INSERT INTO legal_placeholders (key, placeholder, value, description) VALUES
  ('SERVICE_FEE',    '[SERVICE FEE]',    '$0.99',          'Per-coupon service fee charged to consumers at checkout'),
  ('EFFECTIVE_DATE', '[EFFECTIVE DATE]', 'April 27, 2026', 'Effective date displayed in legal document headers'),
  ('LAST_UPDATED',   '[LAST UPDATED]',   'April 27, 2026', 'Last-updated date displayed in legal document headers')
ON CONFLICT (key) DO UPDATE
  SET value      = EXCLUDED.value,
      description = EXCLUDED.description,
      updated_at  = now();
