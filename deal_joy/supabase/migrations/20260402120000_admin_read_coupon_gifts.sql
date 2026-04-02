-- Admin 后台订单详情嵌套查询 order_items → coupon_gifts 时需通过 RLS
-- 否则仅 gifter/recipient 可见，admin 读不到赠礼记录，时间线无法展示

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'coupon_gifts'
      AND policyname = 'admin_read_all_coupon_gifts'
  ) THEN
    CREATE POLICY "admin_read_all_coupon_gifts"
      ON public.coupon_gifts
      FOR SELECT
      USING (public.is_admin());
  END IF;
END $$;
