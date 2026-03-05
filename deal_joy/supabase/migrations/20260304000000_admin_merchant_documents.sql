-- =============================================================
-- Admin 可读取全部 merchant_documents（后台审批时查看商家提交的证件）
-- 依赖：is_current_user_admin() 若已存在则被 REPLACE，否则新建
-- =============================================================

CREATE OR REPLACE FUNCTION public.is_current_user_admin()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid() AND role = 'admin'::user_role
  );
$$;

DROP POLICY IF EXISTS "merchant_documents_admin_select" ON public.merchant_documents;
CREATE POLICY "merchant_documents_admin_select"
  ON public.merchant_documents
  FOR SELECT
  USING (public.is_current_user_admin());
