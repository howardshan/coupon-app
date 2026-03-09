-- =============================================================
-- 商家订单列表：返回 coupon_expires_at 供前端计算展示状态（Expired / Pending Refund）
-- =============================================================

-- 修改返回类型（新增 coupon_expires_at）必须先 DROP 再 CREATE
DROP FUNCTION IF EXISTS public.get_merchant_orders(uuid, text, date, date, uuid, integer, integer);

CREATE OR REPLACE FUNCTION public.get_merchant_orders(
  p_merchant_id  UUID,
  p_status       TEXT    DEFAULT NULL,
  p_date_from    DATE    DEFAULT NULL,
  p_date_to      DATE    DEFAULT NULL,
  p_deal_id      UUID    DEFAULT NULL,
  p_page         INT     DEFAULT 1,
  p_per_page     INT     DEFAULT 20
)
RETURNS TABLE(
  id                    UUID,
  order_number          TEXT,
  deal_id               UUID,
  deal_title            TEXT,
  deal_original_price   NUMERIC,
  deal_discount_price   NUMERIC,
  user_display_name     TEXT,
  quantity              INT,
  unit_price            NUMERIC,
  total_amount          NUMERIC,
  status                TEXT,
  payment_intent_id     TEXT,
  stripe_charge_id      TEXT,
  refund_reason         TEXT,
  coupon_code           TEXT,
  coupon_status         TEXT,
  coupon_expires_at     TIMESTAMPTZ,
  coupon_redeemed_at    TIMESTAMPTZ,
  created_at            TIMESTAMPTZ,
  refund_requested_at   TIMESTAMPTZ,
  refunded_at           TIMESTAMPTZ,
  total_count           BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_offset INT;
  v_limit  INT;
BEGIN
  v_limit  := LEAST(GREATEST(COALESCE(p_per_page, 20), 1), 100);
  v_offset := (GREATEST(COALESCE(p_page, 1), 1) - 1) * v_limit;

  RETURN QUERY
  WITH filtered AS (
    SELECT
      o.id,
      o.order_number,
      o.deal_id,
      d.title                                                            AS deal_title,
      d.original_price                                                   AS deal_original_price,
      d.discount_price                                                   AS deal_discount_price,
      SPLIT_PART(COALESCE(u.full_name, 'Customer'), ' ', 1)             AS user_display_name,
      o.quantity,
      o.unit_price,
      o.total_amount,
      o.status::TEXT,
      o.payment_intent_id,
      o.stripe_charge_id,
      o.refund_reason,
      c.qr_code                                                          AS coupon_code,
      c.status::TEXT                                                     AS coupon_status,
      c.expires_at                                                       AS coupon_expires_at,
      c.redeemed_at                                                      AS coupon_redeemed_at,
      o.created_at,
      o.refund_requested_at,
      o.refunded_at
    FROM public.orders o
    JOIN public.deals d ON d.id = o.deal_id
    JOIN public.users u ON u.id = o.user_id
    LEFT JOIN public.coupons c ON c.order_id = o.id
    WHERE d.merchant_id = p_merchant_id
      AND (p_status IS NULL OR o.status::TEXT = p_status)
      AND (p_date_from IS NULL OR o.created_at::DATE >= p_date_from)
      AND (p_date_to   IS NULL OR o.created_at::DATE <= p_date_to)
      AND (p_deal_id IS NULL OR o.deal_id = p_deal_id)
    ORDER BY o.created_at DESC
  ),
  counted AS (
    SELECT COUNT(*) AS total_count FROM filtered
  )
  SELECT
    f.id,
    f.order_number,
    f.deal_id,
    f.deal_title,
    f.deal_original_price,
    f.deal_discount_price,
    f.user_display_name,
    f.quantity,
    f.unit_price,
    f.total_amount,
    f.status,
    f.payment_intent_id,
    f.stripe_charge_id,
    f.refund_reason,
    f.coupon_code,
    f.coupon_status,
    f.coupon_expires_at,
    f.coupon_redeemed_at,
    f.created_at,
    f.refund_requested_at,
    f.refunded_at,
    c.total_count
  FROM filtered f
  CROSS JOIN counted c
  LIMIT v_limit
  OFFSET v_offset;
END;
$$;

-- 重建后恢复执行权限（与原 migration 一致）
GRANT EXECUTE ON FUNCTION public.get_merchant_orders(uuid, text, date, date, uuid, integer, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_merchant_orders(uuid, text, date, date, uuid, integer, integer) TO authenticated;
