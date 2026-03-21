-- 用户 Profile 扩展：添加 bio 字段 + avatars Storage bucket

-- 1. 添加 bio 字段
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS bio TEXT;

-- 2. 创建 avatars 公开 bucket
INSERT INTO storage.buckets (id, name, public)
VALUES ('avatars', 'avatars', true)
ON CONFLICT (id) DO NOTHING;

-- 3. Storage RLS：任何人可读头像
CREATE POLICY "avatars_public_read"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'avatars');

-- 4. Storage RLS：登录用户只能上传自己的头像（路径 avatars/{userId}/...）
CREATE POLICY "avatars_owner_insert"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'avatars'
    AND auth.role() = 'authenticated'
    AND (storage.foldername(name))[1] = auth.uid()::TEXT
  );

-- 5. Storage RLS：登录用户只能更新自己的头像
CREATE POLICY "avatars_owner_update"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'avatars'
    AND auth.role() = 'authenticated'
    AND (storage.foldername(name))[1] = auth.uid()::TEXT
  );

-- 6. Storage RLS：登录用户只能删除自己的头像
CREATE POLICY "avatars_owner_delete"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'avatars'
    AND auth.role() = 'authenticated'
    AND (storage.foldername(name))[1] = auth.uid()::TEXT
  );
