-- 修正历史数据：售后 refund_amount 曾被误写为 orders.total_amount（多商家一单时错误）
-- 仅更新「当前金额仍等于整单总价」且「按券对应 order_items 行计算出的金额不同」的待处理 / 平台仲裁中工单

BEGIN;

UPDATE public.after_sales_requests AS r
SET
  refund_amount = v.line_amount,
  updated_at = now()
FROM (
  SELECT
    r2.id,
    o.total_amount AS order_total,
    ROUND(
      (
        COALESCE(oi.unit_price, 0) + COALESCE(oi.service_fee, 0) + COALESCE(oi.tax_amount, 0)
      )::numeric,
      2
    ) AS line_amount
  FROM public.after_sales_requests AS r2
  INNER JOIN public.orders AS o ON o.id = r2.order_id
  INNER JOIN LATERAL (
    SELECT oi0.unit_price, oi0.service_fee, oi0.tax_amount
    FROM public.order_items AS oi0
    WHERE oi0.order_id = r2.order_id
      AND oi0.coupon_id = r2.coupon_id
    LIMIT 1
  ) AS oi ON true
  WHERE r2.status IN ('pending', 'awaiting_platform')
) AS v
WHERE r.id = v.id
  AND r.refund_amount = v.order_total
  AND v.line_amount IS NOT NULL
  AND v.line_amount > 0
  AND v.line_amount <> v.order_total;

COMMIT;
