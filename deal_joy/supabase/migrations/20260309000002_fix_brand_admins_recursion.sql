-- =============================================================
-- 修复 brand_admins 表 RLS 无限递归
-- 问题: brand_admins_select_same_brand 策略自引用 brand_admins，
--       当 merchants 的策略也查 brand_admins 时触发无限递归
-- 方案: 用 SECURITY DEFINER 函数绕过 RLS 检查
-- =============================================================

-- 1. 创建 SECURITY DEFINER 函数：判断当前用户是否是某品牌的管理员
CREATE OR REPLACE FUNCTION public.is_brand_admin(p_brand_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.brand_admins
    WHERE brand_id = p_brand_id
      AND user_id = auth.uid()
  );
END;
$$;

-- 2. 创建 SECURITY DEFINER 函数：判断当前用户是否是某品牌的 owner
CREATE OR REPLACE FUNCTION public.is_brand_owner(p_brand_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.brand_admins
    WHERE brand_id = p_brand_id
      AND user_id = auth.uid()
      AND role = 'owner'
  );
END;
$$;

-- =============================================================
-- 3. 修复 brand_admins 表的 RLS 策略
-- =============================================================

-- 删除有问题的自引用策略
DROP POLICY IF EXISTS "brand_admins_select_same_brand" ON public.brand_admins;

-- 用 SECURITY DEFINER 函数重建：同品牌管理员可互相看到
CREATE POLICY "brand_admins_select_same_brand"
  ON public.brand_admins
  FOR SELECT
  USING (public.is_brand_admin(brand_id));

-- 删除并重建 insert 策略（也有自引用）
DROP POLICY IF EXISTS "brand_admins_insert_by_owner" ON public.brand_admins;
CREATE POLICY "brand_admins_insert_by_owner"
  ON public.brand_admins
  FOR INSERT
  WITH CHECK (public.is_brand_owner(brand_id));

-- 删除并重建 delete 策略（也有自引用）
DROP POLICY IF EXISTS "brand_admins_delete_by_owner" ON public.brand_admins;
CREATE POLICY "brand_admins_delete_by_owner"
  ON public.brand_admins
  FOR DELETE
  USING (public.is_brand_owner(brand_id));

-- =============================================================
-- 4. 修复 brands 表策略（也引用了 brand_admins）
-- =============================================================
DROP POLICY IF EXISTS "brands_modify_by_admin" ON public.brands;
CREATE POLICY "brands_modify_by_admin"
  ON public.brands
  FOR ALL
  USING (public.is_brand_admin(id))
  WITH CHECK (public.is_brand_admin(id));

-- =============================================================
-- 5. 修复 merchants 表策略（引用 brand_admins 导致递归）
-- =============================================================
DROP POLICY IF EXISTS "merchants_modify" ON public.merchants;
CREATE POLICY "merchants_modify"
  ON public.merchants
  FOR UPDATE
  USING (
    user_id = auth.uid()
    OR (brand_id IS NOT NULL AND public.is_brand_admin(brand_id))
    OR EXISTS (
      SELECT 1 FROM public.merchant_staff
      WHERE merchant_staff.merchant_id = merchants.id
        AND merchant_staff.user_id = auth.uid()
        AND merchant_staff.role = 'manager'
        AND merchant_staff.is_active = true
    )
  );

-- 同样修复 merchants 的 readable 策略（如果有引用 brand_admins 的）
DROP POLICY IF EXISTS "merchants_readable_by_owner_and_full_staff" ON public.merchants;
-- 重建，使用已有的 can_read_merchant 函数（该函数不查 brand_admins，安全）
CREATE POLICY "merchants_readable_by_owner_and_full_staff"
  ON public.merchants
  FOR SELECT
  USING (public.can_read_merchant(id));

-- =============================================================
-- 6. 修复 brand_invitations 策略（引用 brand_admins）
-- =============================================================
DROP POLICY IF EXISTS "brand_invitations_manage" ON public.brand_invitations;
CREATE POLICY "brand_invitations_manage"
  ON public.brand_invitations
  FOR ALL
  USING (public.is_brand_admin(brand_id))
  WITH CHECK (public.is_brand_admin(brand_id));

-- =============================================================
-- 7. 修复 merchant_staff 策略（通过 merchants JOIN brand_admins）
-- =============================================================

-- 辅助函数：判断当前用户是否是某商家所属品牌的管理员
CREATE OR REPLACE FUNCTION public.is_merchant_brand_admin(p_merchant_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
  v_brand_id uuid;
BEGIN
  SELECT brand_id INTO v_brand_id FROM public.merchants WHERE id = p_merchant_id;
  IF v_brand_id IS NULL THEN
    RETURN false;
  END IF;
  RETURN EXISTS (
    SELECT 1 FROM public.brand_admins
    WHERE brand_id = v_brand_id
      AND user_id = auth.uid()
  );
END;
$$;

-- merchant_staff SELECT
DROP POLICY IF EXISTS "merchant_staff_select" ON public.merchant_staff;
CREATE POLICY "merchant_staff_select"
  ON public.merchant_staff
  FOR SELECT
  USING (
    merchant_staff.user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.merchants m
      WHERE m.id = merchant_staff.merchant_id
        AND m.user_id = auth.uid()
    )
    OR public.is_merchant_brand_admin(merchant_id)
  );

-- merchant_staff INSERT
DROP POLICY IF EXISTS "merchant_staff_insert" ON public.merchant_staff;
CREATE POLICY "merchant_staff_insert"
  ON public.merchant_staff
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.merchants m
      WHERE m.id = merchant_staff.merchant_id
        AND m.user_id = auth.uid()
    )
    OR public.is_merchant_brand_admin(merchant_id)
  );

-- merchant_staff UPDATE
DROP POLICY IF EXISTS "merchant_staff_update" ON public.merchant_staff;
CREATE POLICY "merchant_staff_update"
  ON public.merchant_staff
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.merchants m
      WHERE m.id = merchant_staff.merchant_id
        AND m.user_id = auth.uid()
    )
    OR public.is_merchant_brand_admin(merchant_id)
  );

-- merchant_staff DELETE
DROP POLICY IF EXISTS "merchant_staff_delete" ON public.merchant_staff;
CREATE POLICY "merchant_staff_delete"
  ON public.merchant_staff
  FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.merchants m
      WHERE m.id = merchant_staff.merchant_id
        AND m.user_id = auth.uid()
    )
    OR public.is_merchant_brand_admin(merchant_id)
  );

-- =============================================================
-- 8. 修复 deals 策略（通过 merchants JOIN brand_admins）
-- =============================================================
DROP POLICY IF EXISTS "deals_select_brand_admin" ON public.deals;
CREATE POLICY "deals_select_brand_admin"
  ON public.deals
  FOR SELECT
  USING (public.is_merchant_brand_admin(merchant_id));

DROP POLICY IF EXISTS "deals_modify_brand_admin" ON public.deals;
CREATE POLICY "deals_modify_brand_admin"
  ON public.deals
  FOR UPDATE
  USING (public.is_merchant_brand_admin(merchant_id));

DROP POLICY IF EXISTS "deals_delete_brand_admin" ON public.deals;
CREATE POLICY "deals_delete_brand_admin"
  ON public.deals
  FOR DELETE
  USING (public.is_merchant_brand_admin(merchant_id));

-- =============================================================
-- 9. 修复 merchant_photos / merchant_hours 策略
-- =============================================================
DROP POLICY IF EXISTS "merchant_photos_brand_admin_read" ON public.merchant_photos;
CREATE POLICY "merchant_photos_brand_admin_read"
  ON public.merchant_photos
  FOR SELECT
  USING (public.is_merchant_brand_admin(merchant_id));

DROP POLICY IF EXISTS "merchant_hours_brand_admin_read" ON public.merchant_hours;
CREATE POLICY "merchant_hours_brand_admin_read"
  ON public.merchant_hours
  FOR SELECT
  USING (public.is_merchant_brand_admin(merchant_id));

-- =============================================================
-- 10. 修复 staff_invitations 策略
-- =============================================================
DROP POLICY IF EXISTS "staff_invitations_manage" ON public.staff_invitations;
CREATE POLICY "staff_invitations_manage"
  ON public.staff_invitations
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.merchants m
      WHERE m.id = staff_invitations.merchant_id
        AND m.user_id = auth.uid()
    )
    OR public.is_merchant_brand_admin(merchant_id)
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.merchants m
      WHERE m.id = staff_invitations.merchant_id
        AND m.user_id = auth.uid()
    )
    OR public.is_merchant_brand_admin(merchant_id)
  );

-- admin 也能读 brand_admins
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'brand_admins' AND policyname = 'admin_read_all_brand_admins'
  ) THEN
    EXECUTE 'CREATE POLICY "admin_read_all_brand_admins" ON public.brand_admins FOR SELECT USING (public.is_admin())';
  END IF;
END $$;
