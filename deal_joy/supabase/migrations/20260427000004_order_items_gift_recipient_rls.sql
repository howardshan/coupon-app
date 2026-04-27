-- ============================================================
-- 修复：受赠人无法读取 order_items 导致券不出现在 To Use Tab
-- 原因：order_items RLS 只允许 orders.user_id = auth.uid()（原始买家）
--       受赠人的 auth.uid() 不是买家，JOIN 返回 NULL，被 oi.id IS NOT NULL 排除
-- 修复：允许 coupons.current_holder_user_id = auth.uid() 的用户读取对应 order_item
-- ============================================================

CREATE POLICY "gift_recipient_select_order_items"
  ON order_items FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM coupons c
      WHERE c.order_item_id = order_items.id
        AND c.current_holder_user_id = auth.uid()
    )
  );
