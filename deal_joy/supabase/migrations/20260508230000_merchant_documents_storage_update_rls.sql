-- merchant-documents：补充 UPDATE 策略，覆盖 Storage upsert / 覆盖上传
-- 背景：客户端 uploadBinary(..., upsert: true) 在对象已存在时会更新 storage.objects，
--       原有迁移仅有 INSERT/SELECT/DELETE，缺 UPDATE 会导致 RLS 403。

DROP POLICY IF EXISTS "merchant_docs_storage_update" ON storage.objects;

CREATE POLICY "merchant_docs_storage_update"
  ON storage.objects
  FOR UPDATE
  USING (
    bucket_id = 'merchant-documents'
    AND auth.role() = 'authenticated'
  )
  WITH CHECK (
    bucket_id = 'merchant-documents'
    AND auth.role() = 'authenticated'
  );
