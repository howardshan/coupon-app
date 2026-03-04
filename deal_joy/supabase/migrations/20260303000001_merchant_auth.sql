-- =============================================================
-- DealJoy 商家认证模块 Migration
-- 在现有 merchants 表基础上补充字段，新建 merchant_documents 表
-- =============================================================

-- -------------------------------------------------------------
-- 1. 为 merchants 表补充商家注册所需字段
--    （merchants 表已存在，只做 ALTER TABLE）
-- -------------------------------------------------------------

-- 公司正式法律名称（区别于店铺展示名 name）
ALTER TABLE public.merchants
  ADD COLUMN IF NOT EXISTS company_name text;

-- 联系人姓名
ALTER TABLE public.merchants
  ADD COLUMN IF NOT EXISTS contact_name text;

-- 联系邮箱（可能与 auth 邮箱一致）
ALTER TABLE public.merchants
  ADD COLUMN IF NOT EXISTS contact_email text;

-- 商家类别（枚举值在前端定义，DB 存文本）
-- 取值: Restaurant | SpaAndMassage | HairAndBeauty | Fitness
--        FunAndGames | NailAndLash | Wellness | Other
ALTER TABLE public.merchants
  ADD COLUMN IF NOT EXISTS category text;

-- EIN / Tax ID，格式 XX-XXXXXXX
ALTER TABLE public.merchants
  ADD COLUMN IF NOT EXISTS ein text;

-- 审核被拒原因（approved 时为 null）
ALTER TABLE public.merchants
  ADD COLUMN IF NOT EXISTS rejection_reason text;

-- Stripe Connect 账户 ID（V1 暂不使用，预留）
ALTER TABLE public.merchants
  ADD COLUMN IF NOT EXISTS stripe_account_id text;

-- 申请提交时间戳
ALTER TABLE public.merchants
  ADD COLUMN IF NOT EXISTS submitted_at timestamptz;

-- -------------------------------------------------------------
-- 2. 新建 merchant_documents 表
--    存储商家上传的各类证件文件 URL
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.merchant_documents (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id   uuid        NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  -- document_type 取值:
  --   business_license | health_permit | food_service_license
  --   cosmetology_license | massage_therapy_license | facility_license
  --   general_business_permit | storefront_photo | owner_id
  document_type text        NOT NULL,
  file_url      text        NOT NULL,    -- Supabase Storage public/signed URL
  file_name     text,
  file_size     int,
  mime_type     text,
  uploaded_at   timestamptz NOT NULL DEFAULT now()
);

-- 索引
CREATE INDEX IF NOT EXISTS idx_merchant_documents_merchant_id
  ON public.merchant_documents(merchant_id);

CREATE INDEX IF NOT EXISTS idx_merchant_documents_type
  ON public.merchant_documents(document_type);

-- -------------------------------------------------------------
-- 3. RLS for merchant_documents
-- -------------------------------------------------------------
ALTER TABLE public.merchant_documents ENABLE ROW LEVEL SECURITY;

-- 商家只能读取自己的证件记录（通过 merchant_id -> user_id = auth.uid()）
CREATE POLICY "merchant_documents_select_own"
  ON public.merchant_documents
  FOR SELECT
  USING (
    merchant_id IN (
      SELECT id FROM public.merchants WHERE user_id = auth.uid()
    )
  );

-- 商家只能插入自己的证件记录
CREATE POLICY "merchant_documents_insert_own"
  ON public.merchant_documents
  FOR INSERT
  WITH CHECK (
    merchant_id IN (
      SELECT id FROM public.merchants WHERE user_id = auth.uid()
    )
  );

-- 商家只能更新自己的证件记录
CREATE POLICY "merchant_documents_update_own"
  ON public.merchant_documents
  FOR UPDATE
  USING (
    merchant_id IN (
      SELECT id FROM public.merchants WHERE user_id = auth.uid()
    )
  );

-- 商家只能删除自己的证件记录（重新提交时需要替换）
CREATE POLICY "merchant_documents_delete_own"
  ON public.merchant_documents
  FOR DELETE
  USING (
    merchant_id IN (
      SELECT id FROM public.merchants WHERE user_id = auth.uid()
    )
  );

-- -------------------------------------------------------------
-- 4. 补充 merchants 表的 RLS 策略（INSERT 策略，允许新商家创建自己的记录）
--    注意：initial_schema.sql 已有 select 和 all（manage own），
--    但 all 策略中 WITH CHECK 可能不允许 INSERT，这里明确补充
-- -------------------------------------------------------------
DO $$
BEGIN
  -- 检查 merchants_insert_own 策略是否已存在，不存在则创建
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'merchants'
      AND policyname = 'merchants_insert_own'
  ) THEN
    EXECUTE '
      CREATE POLICY "merchants_insert_own"
        ON public.merchants
        FOR INSERT
        WITH CHECK (auth.uid() = user_id)
    ';
  END IF;
END $$;

-- -------------------------------------------------------------
-- 5. Storage bucket: merchant-documents
--    通过 Supabase Dashboard 或 API 创建私有 bucket
--    以下为对应的 Storage RLS 策略（SQL 形式，适用于 storage.objects）
-- -------------------------------------------------------------

-- 注意：Supabase Storage bucket 的创建需要在 Dashboard 完成，
-- 或通过 supabase storage create 命令。
-- 以下策略在 bucket 创建后自动生效（如果通过 migration 部署）。

-- 允许已认证用户上传文件到 merchant-documents bucket
-- （路径格式: {merchant_id}/{document_type}/{filename}）
INSERT INTO storage.buckets (id, name, public)
  VALUES ('merchant-documents', 'merchant-documents', false)
  ON CONFLICT (id) DO NOTHING;

-- Storage RLS: 认证用户可上传到自己的目录
CREATE POLICY "merchant_docs_storage_insert"
  ON storage.objects
  FOR INSERT
  WITH CHECK (
    bucket_id = 'merchant-documents'
    AND auth.role() = 'authenticated'
  );

-- Storage RLS: 认证用户可读取自己目录下的文件
CREATE POLICY "merchant_docs_storage_select"
  ON storage.objects
  FOR SELECT
  USING (
    bucket_id = 'merchant-documents'
    AND auth.role() = 'authenticated'
  );

-- Storage RLS: 认证用户可删除自己的文件（重新上传时）
CREATE POLICY "merchant_docs_storage_delete"
  ON storage.objects
  FOR DELETE
  USING (
    bucket_id = 'merchant-documents'
    AND auth.role() = 'authenticated'
  );
