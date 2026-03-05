-- =============================================================
-- Admin 可更新 deals（上架/下架审核）
-- 依赖：is_current_user_admin() 已由 20260304000000 提供
-- =============================================================

DROP POLICY IF EXISTS "deals_admin_update" ON public.deals;
CREATE POLICY "deals_admin_update"
  ON public.deals
  FOR UPDATE
  USING (public.is_current_user_admin());
