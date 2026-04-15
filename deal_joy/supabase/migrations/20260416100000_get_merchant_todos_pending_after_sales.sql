-- Dashboard 待办：增加待商家处理的 after-sales（status = pending）
-- 与 pending_refunds（order_items.refund_review，对应核销后 24h 内争议退款）区分开

BEGIN;

DROP FUNCTION IF EXISTS public.get_merchant_todos(uuid);

CREATE FUNCTION public.get_merchant_todos(p_merchant_id uuid)
RETURNS TABLE(
  pending_reviews      bigint,
  pending_refunds      bigint,
  influencer_requests  bigint,
  pending_after_sales  bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    (
      SELECT COUNT(*)
      FROM reviews r
      JOIN deals d ON d.id = r.deal_id
      WHERE d.merchant_id = p_merchant_id
    )::bigint AS pending_reviews,

    (
      SELECT COUNT(*)
      FROM order_items oi
      WHERE (
              oi.purchased_merchant_id = p_merchant_id
              OR p_merchant_id = ANY(oi.applicable_store_ids)
            )
        AND oi.customer_status = 'refund_review'
    )::bigint AS pending_refunds,

    0::bigint AS influencer_requests,

    (
      SELECT COUNT(*)
      FROM after_sales_requests r
      WHERE r.merchant_id = p_merchant_id
        AND r.status = 'pending'::public.after_sale_status
    )::bigint AS pending_after_sales;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_merchant_todos(uuid) TO authenticated;

COMMIT;
