-- =============================================================
-- 结算 RPC 改造：支持多店收入归属（redeemed_at_merchant_id）
-- 移除 RPC 内部的 auth.uid() 校验（Edge Function 已用 service_role 鉴权）
-- =============================================================

-- 1. 重建 get_merchant_earnings_summary
--    收入按 COALESCE(c.redeemed_at_merchant_id, d.merchant_id) 归属
DROP FUNCTION IF EXISTS public.get_merchant_earnings_summary(uuid, date);

CREATE FUNCTION public.get_merchant_earnings_summary(
  p_merchant_id uuid,
  p_month_start date
)
RETURNS TABLE(
  total_revenue      numeric,
  pending_settlement numeric,
  settled_amount     numeric,
  refunded_amount    numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_month_end date;
  v_settlement_cutoff timestamptz;
BEGIN
  v_month_end := (p_month_start + interval '1 month - 1 day')::date;
  v_settlement_cutoff := now() - interval '7 days';

  RETURN QUERY
  SELECT
    -- 本月总收入（非退款，按实际核销门店归属）
    COALESCE(SUM(
      CASE
        WHEN o.status IN ('unused', 'used')
          AND date(o.created_at) BETWEEN p_month_start AND v_month_end
        THEN o.total_amount
        ELSE 0
      END
    ), 0)::numeric AS total_revenue,

    -- 待结算：已核销但不足 7 天
    COALESCE(SUM(
      CASE
        WHEN o.status = 'used'
          AND c.used_at IS NOT NULL
          AND c.used_at > v_settlement_cutoff
          AND NOT EXISTS (
            SELECT 1 FROM public.settlements s
            WHERE s.merchant_id = p_merchant_id
              AND s.status = 'paid'
              AND o.created_at::date BETWEEN s.period_start AND s.period_end
          )
        THEN (o.total_amount * 0.85)
        ELSE 0
      END
    ), 0)::numeric AS pending_settlement,

    -- 已结算
    COALESCE((
      SELECT SUM(s.net_amount)
      FROM public.settlements s
      WHERE s.merchant_id = p_merchant_id
        AND s.status = 'paid'
        AND s.period_start >= p_month_start
        AND s.period_end <= v_month_end
    ), 0)::numeric AS settled_amount,

    -- 退款
    COALESCE(SUM(
      CASE
        WHEN o.status = 'refunded'
          AND date(o.updated_at) BETWEEN p_month_start AND v_month_end
        THEN o.total_amount
        ELSE 0
      END
    ), 0)::numeric AS refunded_amount

  FROM public.orders o
  JOIN public.deals d ON d.id = o.deal_id
  LEFT JOIN public.coupons c ON c.order_id = o.id
  WHERE COALESCE(c.redeemed_at_merchant_id, d.merchant_id) = p_merchant_id;
END;
$$;

-- 2. 重建 get_merchant_transactions
--    按实际核销门店归属查询交易
DROP FUNCTION IF EXISTS public.get_merchant_transactions(uuid, date, date, int, int);

CREATE FUNCTION public.get_merchant_transactions(
  p_merchant_id uuid,
  p_date_from   date    DEFAULT NULL,
  p_date_to     date    DEFAULT NULL,
  p_page        int     DEFAULT 1,
  p_per_page    int     DEFAULT 20
)
RETURNS TABLE(
  order_id     uuid,
  amount       numeric,
  platform_fee numeric,
  net_amount   numeric,
  status       text,
  created_at   timestamptz,
  total_count  bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT
    o.id                                 AS order_id,
    o.total_amount                       AS amount,
    ROUND(o.total_amount * 0.15, 2)      AS platform_fee,
    ROUND(o.total_amount * 0.85, 2)      AS net_amount,
    o.status::text                       AS status,
    o.created_at                         AS created_at,
    COUNT(*) OVER ()                     AS total_count
  FROM public.orders o
  JOIN public.deals d ON d.id = o.deal_id
  LEFT JOIN public.coupons c ON c.order_id = o.id
  WHERE COALESCE(c.redeemed_at_merchant_id, d.merchant_id) = p_merchant_id
    AND (p_date_from IS NULL OR date(o.created_at) >= p_date_from)
    AND (p_date_to   IS NULL OR date(o.created_at) <= p_date_to)
  ORDER BY o.created_at DESC
  LIMIT p_per_page
  OFFSET (p_page - 1) * p_per_page;
END;
$$;

-- 3. 重建 get_merchant_report_data
--    按实际核销门店归属生成报表
DROP FUNCTION IF EXISTS public.get_merchant_report_data(uuid, date, date);

CREATE FUNCTION public.get_merchant_report_data(
  p_merchant_id uuid,
  p_date_from   date,
  p_date_to     date
)
RETURNS TABLE(
  report_date   date,
  order_count   bigint,
  gross_amount  numeric,
  platform_fee  numeric,
  net_amount    numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT
    date(o.created_at)                                   AS report_date,
    COUNT(*)                                             AS order_count,
    COALESCE(SUM(o.total_amount), 0)                     AS gross_amount,
    COALESCE(ROUND(SUM(o.total_amount) * 0.15, 2), 0)   AS platform_fee,
    COALESCE(ROUND(SUM(o.total_amount) * 0.85, 2), 0)   AS net_amount
  FROM public.orders o
  JOIN public.deals d ON d.id = o.deal_id
  LEFT JOIN public.coupons c ON c.order_id = o.id
  WHERE COALESCE(c.redeemed_at_merchant_id, d.merchant_id) = p_merchant_id
    AND o.status NOT IN ('refunded')
    AND date(o.created_at) BETWEEN p_date_from AND p_date_to
  GROUP BY date(o.created_at)
  ORDER BY date(o.created_at) ASC;
END;
$$;

-- 4. 授权
GRANT EXECUTE ON FUNCTION public.get_merchant_earnings_summary(uuid, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_merchant_earnings_summary(uuid, date) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_merchant_transactions(uuid, date, date, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_merchant_transactions(uuid, date, date, int, int) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_merchant_report_data(uuid, date, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_merchant_report_data(uuid, date, date) TO service_role;
