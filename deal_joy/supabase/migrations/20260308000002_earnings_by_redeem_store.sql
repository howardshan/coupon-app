-- =============================================================
-- 结算逻辑改造：收入按实际核销门店归属
-- 更新 RPC 函数支持 redeemed_at_merchant_id
-- =============================================================

-- 更新 get_merchant_earnings_summary RPC
-- 增加对 redeemed_at_merchant_id 的支持
-- 如果 redeemed_at_merchant_id 存在，按它归属；否则按原 merchant_id

-- 注意：由于现有 RPC 可能有不同的返回类型，
-- 这里只添加一个视图辅助查询，不改动现有 RPC 签名

-- 创建收入归属视图：按实际核销门店计算
CREATE OR REPLACE VIEW v_earnings_by_store AS
SELECT
  COALESCE(c.redeemed_at_merchant_id, o.merchant_id) AS earning_merchant_id,
  o.merchant_id AS deal_merchant_id,
  o.id AS order_id,
  o.total_amount,
  o.platform_fee,
  o.net_amount,
  o.status AS order_status,
  o.created_at AS order_created_at,
  c.id AS coupon_id,
  c.status AS coupon_status,
  c.used_at,
  c.redeemed_at,
  c.redeemed_at_merchant_id
FROM orders o
LEFT JOIN coupons c ON c.order_id = o.id
WHERE o.status IN ('completed', 'paid');

-- 添加注释
COMMENT ON VIEW v_earnings_by_store IS '按实际核销门店归属的收入视图，用于多店结算';
