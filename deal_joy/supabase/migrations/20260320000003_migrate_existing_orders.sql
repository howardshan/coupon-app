-- ============================================================
-- 数据迁移: 现有 orders → order_items
--
-- 每个旧 order（1 order = 1 deal = 1 coupon）创建对应的 order_item
-- 注意: 此迁移脚本需要禁用 auto_create_coupon_per_item 触发器
--       因为旧数据已有 coupon，不需要再创建
-- ============================================================

-- 临时禁用触发器（避免迁移时重复创建 coupon）
ALTER TABLE public.order_items DISABLE TRIGGER on_order_item_created;
ALTER TABLE public.order_items DISABLE TRIGGER trg_sync_deal_total_sold_item_insert;

-- Step 1: 补全 orders 新字段
UPDATE public.orders SET
  items_amount      = total_amount,
  service_fee_total = 0  -- 旧订单无 service fee
WHERE items_amount IS NULL;

-- Step 2: 插入 order_items（跳过已迁移的）
INSERT INTO public.order_items (
  order_id, deal_id, coupon_id,
  unit_price, service_fee,
  purchased_merchant_id, applicable_store_ids,
  selected_options,
  redeemed_merchant_id, redeemed_at,
  refunded_at, refund_reason, refund_amount, refund_method,
  customer_status, merchant_status,
  created_at
)
SELECT
  o.id,
  o.deal_id,
  o.coupon_id,
  o.unit_price,
  0,  -- 旧订单无 service fee
  o.purchased_merchant_id,
  o.applicable_store_ids,
  o.selected_options,
  -- 核销信息从 coupons 表获取
  c.redeemed_at_merchant_id,
  c.redeemed_at,
  -- 退款信息
  o.refunded_at,
  o.refund_reason,
  CASE WHEN o.status::text = 'refunded' THEN o.total_amount ELSE NULL END,
  CASE WHEN o.status::text = 'refunded' THEN 'original_payment' ELSE NULL END,
  -- customer_status 映射
  CASE o.status::text
    WHEN 'unused'               THEN 'unused'::customer_item_status
    WHEN 'authorized'           THEN 'unused'::customer_item_status
    WHEN 'used'                 THEN 'used'::customer_item_status
    WHEN 'refunded'             THEN 'refund_success'::customer_item_status
    WHEN 'refund_requested'     THEN 'refund_pending'::customer_item_status
    WHEN 'refund_pending_merchant' THEN 'refund_review'::customer_item_status
    WHEN 'refund_pending_admin' THEN 'refund_review'::customer_item_status
    WHEN 'refund_rejected'      THEN 'refund_reject'::customer_item_status
    WHEN 'refund_failed'        THEN 'refund_reject'::customer_item_status
    WHEN 'expired'              THEN 'refund_success'::customer_item_status
    WHEN 'voided'               THEN 'refund_success'::customer_item_status
    ELSE 'unused'::customer_item_status
  END,
  -- merchant_status 映射
  CASE o.status::text
    WHEN 'used' THEN 'unpaid'::merchant_item_status
    WHEN 'refunded' THEN 'refund_success'::merchant_item_status
    ELSE 'unused'::merchant_item_status
  END,
  o.created_at
FROM public.orders o
JOIN public.deals d ON d.id = o.deal_id
LEFT JOIN public.coupons c ON c.order_id = o.id
WHERE o.deal_id IS NOT NULL  -- 确保是旧格式订单
  AND NOT EXISTS (SELECT 1 FROM public.order_items oi WHERE oi.order_id = o.id);

-- Step 3: 更新 coupons.order_item_id（回填关联）
UPDATE public.coupons c
SET order_item_id = oi.id
FROM public.order_items oi
WHERE oi.coupon_id = c.id
  AND c.order_item_id IS NULL;

-- 重新启用触发器
ALTER TABLE public.order_items ENABLE TRIGGER on_order_item_created;
ALTER TABLE public.order_items ENABLE TRIGGER trg_sync_deal_total_sold_item_insert;
