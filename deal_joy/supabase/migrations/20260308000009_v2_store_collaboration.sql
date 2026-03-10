-- V2.7 门店间协作
-- 订单转移、共享排队、评价聚合

-- 订单转移记录
CREATE TABLE IF NOT EXISTS order_transfers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  from_merchant_id UUID NOT NULL REFERENCES merchants(id),
  to_merchant_id UUID NOT NULL REFERENCES merchants(id),
  reason TEXT DEFAULT '',
  status TEXT NOT NULL DEFAULT 'pending',
    -- pending: 等待接收方确认
    -- accepted: 已接受
    -- rejected: 已拒绝
    -- cancelled: 已取消
  transferred_by UUID REFERENCES auth.users(id),
  responded_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  responded_at TIMESTAMPTZ,
  CONSTRAINT order_transfer_diff_stores CHECK (from_merchant_id != to_merchant_id)
);

-- 共享排队（同品牌门店间共享等位信息）
CREATE TABLE IF NOT EXISTS shared_queue (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  brand_id UUID NOT NULL REFERENCES brands(id) ON DELETE CASCADE,
  merchant_id UUID NOT NULL REFERENCES merchants(id),
  user_id UUID REFERENCES auth.users(id),
  customer_name TEXT DEFAULT '',
  party_size INT NOT NULL DEFAULT 1,
  queue_number INT NOT NULL,
  status TEXT NOT NULL DEFAULT 'waiting',
    -- waiting: 等待中
    -- called: 已叫号
    -- seated: 已就座
    -- cancelled: 已取消
    -- transferred: 已转到其他门店
  estimated_wait_minutes INT DEFAULT 0,
  notes TEXT DEFAULT '',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  called_at TIMESTAMPTZ,
  seated_at TIMESTAMPTZ
);

-- 品牌级评价聚合视图（用 materialized view 定期刷新）
-- 先用普通视图
CREATE OR REPLACE VIEW brand_review_summary AS
SELECT
  m.brand_id,
  COUNT(r.id) AS total_reviews,
  ROUND(AVG(r.rating)::numeric, 2) AS avg_rating,
  COUNT(CASE WHEN r.rating >= 4 THEN 1 END) AS positive_count,
  COUNT(CASE WHEN r.rating <= 2 THEN 1 END) AS negative_count,
  COUNT(DISTINCT r.merchant_id) AS stores_with_reviews
FROM reviews r
JOIN merchants m ON r.merchant_id = m.id
WHERE m.brand_id IS NOT NULL
GROUP BY m.brand_id;

-- 索引
CREATE INDEX IF NOT EXISTS idx_order_transfers_order ON order_transfers(order_id);
CREATE INDEX IF NOT EXISTS idx_order_transfers_from ON order_transfers(from_merchant_id, status);
CREATE INDEX IF NOT EXISTS idx_order_transfers_to ON order_transfers(to_merchant_id, status);
CREATE INDEX IF NOT EXISTS idx_shared_queue_brand ON shared_queue(brand_id, merchant_id, status);
CREATE INDEX IF NOT EXISTS idx_shared_queue_status ON shared_queue(status, created_at);

-- RLS
ALTER TABLE order_transfers ENABLE ROW LEVEL SECURITY;
ALTER TABLE shared_queue ENABLE ROW LEVEL SECURITY;

-- 订单转移：发起方和接收方都能查看
CREATE POLICY "merchant_view_own_transfers" ON order_transfers
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM merchants
      WHERE merchants.id IN (order_transfers.from_merchant_id, order_transfers.to_merchant_id)
        AND merchants.user_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1 FROM merchant_staff
      WHERE merchant_staff.merchant_id IN (order_transfers.from_merchant_id, order_transfers.to_merchant_id)
        AND merchant_staff.user_id = auth.uid()
        AND merchant_staff.is_active = true
    )
  );

CREATE POLICY "merchant_manage_transfers" ON order_transfers
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM merchants
      WHERE merchants.id IN (order_transfers.from_merchant_id, order_transfers.to_merchant_id)
        AND merchants.user_id = auth.uid()
    )
  );

-- 共享排队：品牌管理员 + 门店 owner/staff 可管理
CREATE POLICY "brand_manage_queue" ON shared_queue
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM brand_admins
      WHERE brand_admins.brand_id = shared_queue.brand_id
        AND brand_admins.user_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1 FROM merchants
      WHERE merchants.id = shared_queue.merchant_id
        AND merchants.user_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1 FROM merchant_staff
      WHERE merchant_staff.merchant_id = shared_queue.merchant_id
        AND merchant_staff.user_id = auth.uid()
        AND merchant_staff.is_active = true
    )
  );
