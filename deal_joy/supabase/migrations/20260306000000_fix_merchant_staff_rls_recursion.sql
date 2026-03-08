-- =============================================================
-- 打破 merchants 与 merchant_staff 的 RLS 循环递归
-- 原因：merchants 的 SELECT 策略会查 merchant_staff，
--      merchant_staff 的策略又查 merchants，导致 infinite recursion。
-- 解决：merchant_staff 策略改为调用 SECURITY DEFINER 函数，不再直接 SELECT merchants。
-- =============================================================

CREATE OR REPLACE FUNCTION public.is_merchant_owner(p_merchant_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.merchants
    WHERE id = p_merchant_id AND user_id = auth.uid()
  );
$$;

DROP POLICY IF EXISTS "merchant_owner_manage_staff" ON public.merchant_staff;
CREATE POLICY "merchant_owner_manage_staff"
  ON public.merchant_staff
  FOR ALL
  USING (public.is_merchant_owner(merchant_id))
  WITH CHECK (public.is_merchant_owner(merchant_id));
