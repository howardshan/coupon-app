-- ============================================================
-- 修复：受赠人打开券详情 403 —— orders 表 RLS 阻断 join
-- 原因：_couponSelect 含 orders!coupons_order_id_fkey(order_number)
--       受赠人不是原始买家，orders_select_own 拒绝访问，整个请求 403
-- 修复：允许 coupons.current_holder_user_id = auth.uid() 的用户读取对应 order
-- ============================================================

CREATE POLICY "gift_recipient_select_orders"
  ON orders FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM coupons c
      WHERE c.order_id = orders.id
        AND c.current_holder_user_id = auth.uid()
    )
  );
