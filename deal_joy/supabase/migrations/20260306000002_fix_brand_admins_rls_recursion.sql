-- =============================================================
-- 打破 brand_admins 表 RLS 策略的自引用递归
-- 原因：brand_admins_select_same_brand / delete_by_owner / insert_by_owner
--       在 USING/WITH CHECK 中 SELECT brand_admins，导致无限递归。
-- 解决：用 SECURITY DEFINER 函数在策略外判断“是否同 brand 成员/owner”，
--       策略内仅调用函数，不再子查询 brand_admins。
-- 前提：表 brand_admins 及其列 brand_id, user_id, role 已存在。
-- =============================================================

-- 1. 当前用户是否在该 brand 下有任意角色（用于 SELECT 同 brand）
CREATE OR REPLACE FUNCTION public.is_brand_member(p_brand_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.brand_admins
    WHERE brand_id = p_brand_id AND user_id = auth.uid()
  );
$$;

-- 2. 当前用户是否是该 brand 的 owner（用于 INSERT/DELETE）
CREATE OR REPLACE FUNCTION public.is_brand_owner(p_brand_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.brand_admins
    WHERE brand_id = p_brand_id AND user_id = auth.uid() AND role = 'owner'
  );
$$;

-- 3. 用函数替代策略里的自引用子查询（保留 brand_admins_select_own 不变）
DROP POLICY IF EXISTS "brand_admins_select_same_brand" ON public.brand_admins;
CREATE POLICY "brand_admins_select_same_brand"
  ON public.brand_admins
  FOR SELECT
  USING (public.is_brand_member(brand_id));

DROP POLICY IF EXISTS "brand_admins_delete_by_owner" ON public.brand_admins;
CREATE POLICY "brand_admins_delete_by_owner"
  ON public.brand_admins
  FOR DELETE
  USING (public.is_brand_owner(brand_id));

DROP POLICY IF EXISTS "brand_admins_insert_by_owner" ON public.brand_admins;
CREATE POLICY "brand_admins_insert_by_owner"
  ON public.brand_admins
  FOR INSERT
  WITH CHECK (public.is_brand_owner(brand_id));
