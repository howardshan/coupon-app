-- =============================================================
-- 从 merchants 侧打破与 merchant_staff 的 RLS 循环递归
-- 原因：merchants 的 SELECT 策略内联了子查询 merchant_staff，
--       评估 deals 的 UPDATE 时会读 merchants，进而触发对 merchant_staff 的查询与递归。
-- 解决：用 SECURITY DEFINER 函数在策略外做“是否可读该 merchant”判断，
--       函数内查 merchants + merchant_staff 不触发 RLS，策略仅调用函数。
-- =============================================================

CREATE OR REPLACE FUNCTION public.can_read_merchant(p_merchant_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
BEGIN
  -- 商家主账号：merchants.user_id = 当前用户
  IF EXISTS (
    SELECT 1 FROM public.merchants
    WHERE id = p_merchant_id AND user_id = auth.uid()
  ) THEN
    RETURN true;
  END IF;
  -- full_access 员工：在 merchant_staff 中有对应记录
  IF EXISTS (
    SELECT 1 FROM public.merchant_staff
    WHERE merchant_id = p_merchant_id
      AND staff_user_id = auth.uid()
      AND role = 'full_access'
  ) THEN
    RETURN true;
  END IF;
  RETURN false;
END;
$$;

DROP POLICY IF EXISTS "merchants_readable_by_owner_and_full_staff" ON public.merchants;
CREATE POLICY "merchants_readable_by_owner_and_full_staff"
  ON public.merchants
  FOR SELECT
  USING (public.can_read_merchant(id));
