-- 修复历史脏数据：同单部分退时 webhook 整单分支误将未退行的 coupons 标为 refunded，
-- 与 order_items.customer_status = unused 不一致，导致 My Coupons Unused 少显示。
-- 仅恢复「行仍为 unused」且券误为 refunded 的行。

UPDATE public.coupons c
SET
  status = 'unused',
  updated_at = now()
FROM public.order_items oi
WHERE c.order_item_id = oi.id
  AND c.status = 'refunded'
  AND oi.customer_status = 'unused';
