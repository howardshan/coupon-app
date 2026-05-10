-- merchant_contracts 表增加 DocuSign 相关字段
-- business_name: 商家在 DocuSign 合同里亲自填写的公司/DBA 名称
-- sent_at:        合同发送时间

ALTER TABLE merchant_contracts
  ADD COLUMN IF NOT EXISTS business_name text,
  ADD COLUMN IF NOT EXISTS sent_at timestamptz;

-- 索引：按 docusign_envelope_id 快速查找（webhook 回调使用）
CREATE INDEX IF NOT EXISTS merchant_contracts_envelope_id_idx
  ON merchant_contracts (docusign_envelope_id)
  WHERE docusign_envelope_id IS NOT NULL;
