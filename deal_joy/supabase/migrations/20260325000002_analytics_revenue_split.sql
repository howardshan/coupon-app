-- ============================================================
-- Analytics: 将 revenue 拆分为 redeem_revenue / pending_revenue / paid_revenue
-- ============================================================

DROP FUNCTION IF EXISTS public.get_merchant_overview(uuid, int);

CREATE FUNCTION public.get_merchant_overview(
  p_merchant_id uuid,
  p_days_range  int default 7
)
RETURNS TABLE(
  views_count       bigint,
  orders_count      bigint,
  redemptions_count bigint,
  revenue           numeric,
  redeem_revenue    numeric,
  pending_revenue   numeric,
  paid_revenue      numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_start_time timestamptz;
BEGIN
  v_start_time := date_trunc('day', now() AT TIME ZONE 'UTC')
                  - ((p_days_range - 1) * interval '1 day');

  RETURN QUERY
  SELECT
    -- 浏览量
    (
      SELECT COUNT(*)
      FROM deal_views dv
      WHERE dv.merchant_id = p_merchant_id
        AND dv.viewed_at >= v_start_time
    )::bigint AS views_count,

    -- 下单量（基于 order_items）
    (
      SELECT COUNT(*)
      FROM order_items oi
      WHERE (
              oi.purchased_merchant_id = p_merchant_id
              OR p_merchant_id = ANY(oi.applicable_store_ids)
            )
        AND oi.created_at >= v_start_time
        AND oi.customer_status NOT IN ('refund_success')
    )::bigint AS orders_count,

    -- 核销量
    (
      SELECT COUNT(*)
      FROM order_items oi
      WHERE (
              oi.purchased_merchant_id = p_merchant_id
              OR p_merchant_id = ANY(oi.applicable_store_ids)
            )
        AND oi.customer_status = 'used'
        AND oi.redeemed_at >= v_start_time
    )::bigint AS redemptions_count,

    -- 总收入（向后兼容）
    COALESCE((
      SELECT SUM(oi.unit_price)
      FROM order_items oi
      WHERE (
              oi.purchased_merchant_id = p_merchant_id
              OR p_merchant_id = ANY(oi.applicable_store_ids)
            )
        AND oi.created_at >= v_start_time
        AND oi.customer_status NOT IN ('refund_success', 'refund_pending')
    ), 0)::numeric AS revenue,

    -- Redeem Revenue：已核销的收入
    COALESCE((
      SELECT SUM(oi.unit_price)
      FROM order_items oi
      WHERE (
              oi.purchased_merchant_id = p_merchant_id
              OR p_merchant_id = ANY(oi.applicable_store_ids)
            )
        AND oi.created_at >= v_start_time
        AND oi.customer_status = 'used'
    ), 0)::numeric AS redeem_revenue,

    -- Pending Revenue：未核销未退款的收入
    COALESCE((
      SELECT SUM(oi.unit_price)
      FROM order_items oi
      WHERE (
              oi.purchased_merchant_id = p_merchant_id
              OR p_merchant_id = ANY(oi.applicable_store_ids)
            )
        AND oi.created_at >= v_start_time
        AND oi.customer_status = 'unused'
    ), 0)::numeric AS pending_revenue,

    -- Paid Revenue：已结算的收入
    COALESCE((
      SELECT SUM(oi.unit_price)
      FROM order_items oi
      WHERE (
              oi.purchased_merchant_id = p_merchant_id
              OR p_merchant_id = ANY(oi.applicable_store_ids)
            )
        AND oi.created_at >= v_start_time
        AND oi.merchant_status = 'paid'
    ), 0)::numeric AS paid_revenue;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_merchant_overview(uuid, int) TO authenticated;
