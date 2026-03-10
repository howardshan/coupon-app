-- =============================================================
-- 允许 admin 角色用户读取所有关键表
-- 问题：admin 在 users.role = 'admin'，但 merchants 表的 RLS
--       只允许 owner 和 staff 读取，导致 admin portal 查不到数据
-- =============================================================

-- 辅助函数：判断当前用户是否是 admin
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid() AND role = 'admin'
  );
END;
$$;

-- merchants 表：admin 可读取所有商家
CREATE POLICY "admin_read_all_merchants"
  ON public.merchants
  FOR SELECT
  USING (public.is_admin());

-- deals 表：admin 可读取所有 deals
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'deals' AND policyname = 'admin_read_all_deals'
  ) THEN
    EXECUTE 'CREATE POLICY "admin_read_all_deals" ON public.deals FOR SELECT USING (public.is_admin())';
  END IF;
END $$;

-- orders 表：admin 可读取所有订单
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'orders' AND policyname = 'admin_read_all_orders'
  ) THEN
    EXECUTE 'CREATE POLICY "admin_read_all_orders" ON public.orders FOR SELECT USING (public.is_admin())';
  END IF;
END $$;

-- coupons 表：admin 可读取所有 coupons
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'coupons' AND policyname = 'admin_read_all_coupons'
  ) THEN
    EXECUTE 'CREATE POLICY "admin_read_all_coupons" ON public.coupons FOR SELECT USING (public.is_admin())';
  END IF;
END $$;

-- reviews 表：admin 可读取所有评价
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'reviews' AND policyname = 'admin_read_all_reviews'
  ) THEN
    EXECUTE 'CREATE POLICY "admin_read_all_reviews" ON public.reviews FOR SELECT USING (public.is_admin())';
  END IF;
END $$;

-- users 表：admin 可读取所有用户
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'users' AND policyname = 'admin_read_all_users'
  ) THEN
    EXECUTE 'CREATE POLICY "admin_read_all_users" ON public.users FOR SELECT USING (public.is_admin())';
  END IF;
END $$;

-- brands 表：admin 可读取所有品牌
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'brands' AND policyname = 'admin_read_all_brands'
  ) THEN
    EXECUTE 'CREATE POLICY "admin_read_all_brands" ON public.brands FOR SELECT USING (public.is_admin())';
  END IF;
END $$;

-- merchant_documents 表：admin 可读取所有商家证件
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'merchant_documents' AND policyname = 'admin_read_all_merchant_documents'
  ) THEN
    EXECUTE 'CREATE POLICY "admin_read_all_merchant_documents" ON public.merchant_documents FOR SELECT USING (public.is_admin())';
  END IF;
END $$;

-- merchant_photos 表：admin 可读取所有商家照片
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'merchant_photos' AND policyname = 'admin_read_all_merchant_photos'
  ) THEN
    EXECUTE 'CREATE POLICY "admin_read_all_merchant_photos" ON public.merchant_photos FOR SELECT USING (public.is_admin())';
  END IF;
END $$;

-- merchant_hours 表：admin 可读取所有营业时间
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'merchant_hours' AND policyname = 'admin_read_all_merchant_hours'
  ) THEN
    EXECUTE 'CREATE POLICY "admin_read_all_merchant_hours" ON public.merchant_hours FOR SELECT USING (public.is_admin())';
  END IF;
END $$;

-- merchant_staff 表：admin 可读取所有员工
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'merchant_staff' AND policyname = 'admin_read_all_merchant_staff'
  ) THEN
    EXECUTE 'CREATE POLICY "admin_read_all_merchant_staff" ON public.merchant_staff FOR SELECT USING (public.is_admin())';
  END IF;
END $$;

-- admin 也需要 UPDATE merchants（审核通过/拒绝）
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'merchants' AND policyname = 'admin_update_all_merchants'
  ) THEN
    EXECUTE 'CREATE POLICY "admin_update_all_merchants" ON public.merchants FOR UPDATE USING (public.is_admin())';
  END IF;
END $$;
