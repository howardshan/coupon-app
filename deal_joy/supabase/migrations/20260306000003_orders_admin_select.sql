-- =============================================================
-- 允许 admin 查看全部订单（后台 Orders 页）
-- 依赖：is_current_user_admin() 已由 20260304000000 提供
-- =============================================================

CREATE POLICY "orders_admin_select"
  ON public.orders
  FOR SELECT
  USING (public.is_current_user_admin());
