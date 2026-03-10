-- =============================================================
-- 从根本上解决 merchant_staff RLS 无限递归
-- 原因：staff_select / staff_manage 策略内 EXISTS (SELECT FROM merchant_staff)
--       导致评估策略时再次查 merchant_staff，形成自引用递归。
-- 解决：用 security_invoker = false 的视图暴露「谁是哪家店 manager」，
--       策略内只查该视图，视图内部以 owner 身份读 merchant_staff 不触发 RLS。
-- 依赖：is_merchant_owner(uuid) 已存在（20260306000000）。
-- =============================================================

-- 1. 创建「门店 manager 列表」视图，以 postgres 身份执行、不触发 RLS
CREATE OR REPLACE VIEW public.merchant_staff_managers
WITH (security_invoker = false)
AS
  SELECT merchant_id, user_id
  FROM public.merchant_staff
  WHERE role = 'manager' AND is_active = true;

COMMENT ON VIEW public.merchant_staff_managers IS 'RLS 策略用：当前各门店的 manager 列表，避免策略内直接查 merchant_staff 导致无限递归';

-- 2. 删除会自引用的策略
DROP POLICY IF EXISTS "staff_select" ON public.merchant_staff;
DROP POLICY IF EXISTS "staff_manage" ON public.merchant_staff;

-- 3. 重写 staff_select：用 is_merchant_owner + 视图 + brand_admins，不再直接查 merchant_staff/merchants
CREATE POLICY "staff_select" ON public.merchant_staff
  FOR SELECT USING (
    user_id = auth.uid()
    OR public.is_merchant_owner(merchant_id)
    OR EXISTS (
      SELECT 1 FROM public.merchant_staff_managers m
      WHERE m.merchant_id = merchant_staff.merchant_id AND m.user_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1 FROM public.merchants m
      JOIN public.brand_admins ba ON ba.brand_id = m.brand_id
      WHERE m.id = merchant_staff.merchant_id AND ba.user_id = auth.uid()
    )
  );

-- 4. 重写 staff_manage：同上
CREATE POLICY "staff_manage" ON public.merchant_staff
  FOR ALL
  USING (
    public.is_merchant_owner(merchant_id)
    OR EXISTS (
      SELECT 1 FROM public.merchant_staff_managers m
      WHERE m.merchant_id = merchant_staff.merchant_id AND m.user_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1 FROM public.merchants m
      JOIN public.brand_admins ba ON ba.brand_id = m.brand_id
      WHERE m.id = merchant_staff.merchant_id AND ba.user_id = auth.uid()
    )
  )
  WITH CHECK (
    public.is_merchant_owner(merchant_id)
    OR EXISTS (
      SELECT 1 FROM public.merchant_staff_managers m
      WHERE m.merchant_id = merchant_staff.merchant_id AND m.user_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1 FROM public.merchants m
      JOIN public.brand_admins ba ON ba.brand_id = m.brand_id
      WHERE m.id = merchant_staff.merchant_id AND ba.user_id = auth.uid()
    )
  );
