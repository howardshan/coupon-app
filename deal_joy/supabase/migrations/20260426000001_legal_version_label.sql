-- legal_document_versions 加 version_label 字段（可自定义展示版本，如 "v2.1"）
ALTER TABLE legal_document_versions
  ADD COLUMN IF NOT EXISTS version_label TEXT;

-- legal_documents 加 current_version_label 字段，与 current_version 同步更新
ALTER TABLE legal_documents
  ADD COLUMN IF NOT EXISTS current_version_label TEXT;
