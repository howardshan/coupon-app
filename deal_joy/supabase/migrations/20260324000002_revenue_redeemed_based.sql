-- ============================================================
-- Revenue 逻辑全面改为「核销后才统计」
--
-- 变更：所有 revenue 相关统计从 o.created_at（下单时间）
-- 改为 oi.redeemed_at（核销时间），只有券被核销后才计入收入。
--
-- 影响函数：
--   1. get_merchant_daily_stats    — today_revenue
--   2. get_merchant_weekly_trend   — daily_revenue
--   3. get_brand_daily_stats       — today_revenue（升级至 V3 order_items）
--   4. get_brand_weekly_trend      — daily_revenue（升级至 V3 order_items）
--   5. get_brand_store_rankings    — total_revenue（升级至 V3 order_items）
--   6. get_merchant_earnings_summary — total_revenue
--   7. get_merchant_transactions   — 改为基于 order_items
--   8. get_merchant_report_data    — 改为基于 order_items
-- ============================================================


-- =============================================================
-- 1. get_merchant_daily_stats — today_revenue 改为核销收入
-- =============================================================
DROP FUNCTION IF EXISTS public.get_merchant_daily_stats(uuid);

CREATE FUNCTION public.get_merchant_daily_stats(p_merchant_id uuid)
RETURNS TABLE(
  today_orders      bigint,
  today_redemptions bigint,
  today_revenue     numeric,
  pending_coupons   bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    -- 今日订单数：基于下单时间（不变）
    (
      SELECT COUNT(*)
      FROM order_items oi
      JOIN orders o ON o.id = oi.order_id
      WHERE (
              oi.purchased_merchant_id = p_merchant_id
              OR p_merchant_id = ANY(oi.applicable_store_ids)
            )
        AND o.created_at >= CURRENT_DATE
        AND o.created_at <  CURRENT_DATE + INTERVAL '1 day'
        AND oi.customer_status NOT IN ('refund_success')
    )::bigint AS today_orders,

    -- 今日核销数（不变）
    (
      SELECT COUNT(*)
      FROM coupons c
      WHERE (c.merchant_id = p_merchant_id OR c.purchased_merchant_id = p_merchant_id)
        AND c.used_at >= CURRENT_DATE
        AND c.used_at <  CURRENT_DATE + INTERVAL '1 day'
    )::bigint AS today_redemptions,

    -- 今日核销收入：仅统计今日核销的券的 unit_price
    (
      SELECT COALESCE(SUM(oi.unit_price), 0)
      FROM order_items oi
      WHERE oi.redeemed_at IS NOT NULL
        AND oi.redeemed_at >= CURRENT_DATE
        AND oi.redeemed_at <  CURRENT_DATE + INTERVAL '1 day'
        AND oi.customer_status NOT IN ('refund_success', 'refund_pending')
        AND COALESCE(oi.redeemed_merchant_id, oi.purchased_merchant_id) = p_merchant_id
    ) AS today_revenue,

    -- 待核销券数（不变）
    (
      SELECT COUNT(*)
      FROM coupons c
      WHERE (c.merchant_id = p_merchant_id OR c.purchased_merchant_id = p_merchant_id)
        AND c.status = 'unused'
        AND c.expires_at > NOW()
    )::bigint AS pending_coupons;
END;
$$;


-- =============================================================
-- 2. get_merchant_weekly_trend — daily_revenue 改为核销收入
-- =============================================================
DROP FUNCTION IF EXISTS public.get_merchant_weekly_trend(uuid);

CREATE FUNCTION public.get_merchant_weekly_trend(p_merchant_id uuid)
RETURNS TABLE(
  trend_date    date,
  daily_orders  bigint,
  daily_revenue numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    gs.day::date AS trend_date,

    -- 每日订单数：基于下单时间（不变）
    (
      SELECT COALESCE(COUNT(*), 0)
      FROM order_items oi
      JOIN orders o ON o.id = oi.order_id
      WHERE (
              oi.purchased_merchant_id = p_merchant_id
              OR p_merchant_id = ANY(oi.applicable_store_ids)
            )
        AND o.created_at >= gs.day
        AND o.created_at <  gs.day + INTERVAL '1 day'
        AND oi.customer_status NOT IN ('refund_success')
    )::bigint AS daily_orders,

    -- 每日核销收入：基于 redeemed_at
    (
      SELECT COALESCE(SUM(oi.unit_price), 0)
      FROM order_items oi
      WHERE oi.redeemed_at IS NOT NULL
        AND oi.redeemed_at >= gs.day
        AND oi.redeemed_at <  gs.day + INTERVAL '1 day'
        AND oi.customer_status NOT IN ('refund_success', 'refund_pending')
        AND COALESCE(oi.redeemed_merchant_id, oi.purchased_merchant_id) = p_merchant_id
    ) AS daily_revenue

  FROM generate_series(
    CURRENT_DATE - INTERVAL '6 days',
    CURRENT_DATE,
    INTERVAL '1 day'
  ) AS gs(day)
  ORDER BY gs.day DESC;
END;
$$;


-- =============================================================
-- 3. get_brand_daily_stats — 升级至 V3 order_items + 核销收入
-- =============================================================
DROP FUNCTION IF EXISTS public.get_brand_daily_stats(uuid);

CREATE FUNCTION public.get_brand_daily_stats(p_brand_id uuid)
RETURNS TABLE(
  total_stores       int,
  online_stores      int,
  today_orders       bigint,
  today_redemptions  bigint,
  today_revenue      decimal,
  pending_coupons    bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_merchant_ids uuid[];
BEGIN
  -- 获取品牌下所有已审核门店 ID
  SELECT ARRAY_AGG(m.id) INTO v_merchant_ids
  FROM merchants m
  WHERE m.brand_id = p_brand_id AND m.status = 'approved';

  IF v_merchant_ids IS NULL THEN
    RETURN QUERY SELECT 0::int, 0::int, 0::bigint, 0::bigint, 0::decimal, 0::bigint;
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    (SELECT COUNT(*)::int FROM merchants WHERE brand_id = p_brand_id AND status = 'approved'),
    (SELECT COUNT(*)::int FROM merchants WHERE brand_id = p_brand_id AND status = 'approved' AND is_online = true),

    -- 今日订单数：基于 order_items + 下单时间
    (
      SELECT COUNT(*)::bigint
      FROM order_items oi
      JOIN orders o ON o.id = oi.order_id
      WHERE (
              oi.purchased_merchant_id = ANY(v_merchant_ids)
              OR oi.applicable_store_ids && v_merchant_ids
            )
        AND o.created_at >= CURRENT_DATE
        AND o.created_at <  CURRENT_DATE + INTERVAL '1 day'
        AND oi.customer_status NOT IN ('refund_success')
    ),

    -- 今日核销数
    (
      SELECT COUNT(*)::bigint
      FROM coupons c
      WHERE (c.merchant_id = ANY(v_merchant_ids) OR c.purchased_merchant_id = ANY(v_merchant_ids))
        AND c.status = 'used'
        AND c.used_at >= CURRENT_DATE
        AND c.used_at <  CURRENT_DATE + INTERVAL '1 day'
    ),

    -- 今日核销收入：基于 redeemed_at
    (
      SELECT COALESCE(SUM(oi.unit_price), 0)::decimal
      FROM order_items oi
      WHERE oi.redeemed_at IS NOT NULL
        AND oi.redeemed_at >= CURRENT_DATE
        AND oi.redeemed_at <  CURRENT_DATE + INTERVAL '1 day'
        AND oi.customer_status NOT IN ('refund_success', 'refund_pending')
        AND COALESCE(oi.redeemed_merchant_id, oi.purchased_merchant_id) = ANY(v_merchant_ids)
    ),

    -- 待核销券数
    (
      SELECT COUNT(*)::bigint
      FROM coupons c
      WHERE (c.merchant_id = ANY(v_merchant_ids) OR c.purchased_merchant_id = ANY(v_merchant_ids))
        AND c.status = 'unused'
        AND c.expires_at > NOW()
    );
END;
$$;


-- =============================================================
-- 4. get_brand_weekly_trend — 升级至 V3 + 核销收入
-- =============================================================
DROP FUNCTION IF EXISTS public.get_brand_weekly_trend(uuid);

CREATE FUNCTION public.get_brand_weekly_trend(p_brand_id uuid)
RETURNS TABLE(
  trend_date    date,
  daily_orders  bigint,
  daily_revenue decimal
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_merchant_ids uuid[];
BEGIN
  SELECT ARRAY_AGG(m.id) INTO v_merchant_ids
  FROM merchants m
  WHERE m.brand_id = p_brand_id AND m.status = 'approved';

  IF v_merchant_ids IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    gs.day::date AS trend_date,

    -- 每日订单数
    (
      SELECT COALESCE(COUNT(*), 0)
      FROM order_items oi
      JOIN orders o ON o.id = oi.order_id
      WHERE (
              oi.purchased_merchant_id = ANY(v_merchant_ids)
              OR oi.applicable_store_ids && v_merchant_ids
            )
        AND o.created_at >= gs.day
        AND o.created_at <  gs.day + INTERVAL '1 day'
        AND oi.customer_status NOT IN ('refund_success')
    )::bigint AS daily_orders,

    -- 每日核销收入
    (
      SELECT COALESCE(SUM(oi.unit_price), 0)
      FROM order_items oi
      WHERE oi.redeemed_at IS NOT NULL
        AND oi.redeemed_at >= gs.day
        AND oi.redeemed_at <  gs.day + INTERVAL '1 day'
        AND oi.customer_status NOT IN ('refund_success', 'refund_pending')
        AND COALESCE(oi.redeemed_merchant_id, oi.purchased_merchant_id) = ANY(v_merchant_ids)
    )::decimal AS daily_revenue

  FROM generate_series(
    CURRENT_DATE - INTERVAL '6 days',
    CURRENT_DATE,
    INTERVAL '1 day'
  ) AS gs(day)
  ORDER BY gs.day ASC;
END;
$$;


-- =============================================================
-- 5. get_brand_store_rankings — 升级至 V3 + 核销收入
-- =============================================================
DROP FUNCTION IF EXISTS public.get_brand_store_rankings(uuid, text, int);

CREATE FUNCTION public.get_brand_store_rankings(
  p_brand_id uuid,
  p_sort_by  text DEFAULT 'revenue',
  p_days     int DEFAULT 30
)
RETURNS TABLE(
  store_id       uuid,
  store_name     text,
  store_address  text,
  is_online      bool,
  total_orders   bigint,
  total_revenue  decimal,
  total_redeemed bigint,
  avg_rating     decimal,
  review_count   bigint,
  refund_rate    decimal
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    m.id AS store_id,
    m.name AS store_name,
    m.address AS store_address,
    m.is_online,
    -- 订单数：基于 order_items
    COALESCE(os.cnt, 0)::bigint AS total_orders,
    -- 核销收入：基于 redeemed_at
    COALESCE(os.rev, 0)::decimal AS total_revenue,
    COALESCE(cs.redeemed, 0)::bigint AS total_redeemed,
    COALESCE(m.rating, 0)::decimal AS avg_rating,
    COALESCE(rs.rcnt, 0)::bigint AS review_count,
    CASE
      WHEN COALESCE(os.cnt, 0) > 0
      THEN (COALESCE(rf.refund_cnt, 0)::decimal / os.cnt * 100)
      ELSE 0
    END AS refund_rate
  FROM merchants m
  LEFT JOIN LATERAL (
    SELECT
      COUNT(oi.id) AS cnt,
      SUM(oi.unit_price) FILTER (
        WHERE oi.redeemed_at IS NOT NULL
          AND oi.customer_status NOT IN ('refund_success', 'refund_pending')
      ) AS rev
    FROM order_items oi
    WHERE COALESCE(oi.redeemed_merchant_id, oi.purchased_merchant_id) = m.id
      AND oi.created_at >= CURRENT_DATE - (p_days || ' days')::interval
  ) os ON true
  LEFT JOIN LATERAL (
    SELECT COUNT(c.id) AS redeemed
    FROM coupons c
    WHERE (c.merchant_id = m.id OR c.purchased_merchant_id = m.id)
      AND c.status = 'used'
      AND c.used_at >= CURRENT_DATE - (p_days || ' days')::interval
  ) cs ON true
  LEFT JOIN LATERAL (
    SELECT COUNT(r.id) AS rcnt
    FROM reviews r
    WHERE r.merchant_id = m.id
  ) rs ON true
  LEFT JOIN LATERAL (
    SELECT COUNT(oi2.id) AS refund_cnt
    FROM order_items oi2
    WHERE COALESCE(oi2.redeemed_merchant_id, oi2.purchased_merchant_id) = m.id
      AND oi2.customer_status = 'refund_success'
      AND oi2.created_at >= CURRENT_DATE - (p_days || ' days')::interval
  ) rf ON true
  WHERE m.brand_id = p_brand_id AND m.status = 'approved'
  ORDER BY
    CASE p_sort_by
      WHEN 'revenue' THEN COALESCE(os.rev, 0)
      WHEN 'orders' THEN COALESCE(os.cnt, 0)::decimal
      WHEN 'rating' THEN COALESCE(m.rating, 0)
      ELSE COALESCE(os.rev, 0)
    END DESC;
END;
$$;


-- =============================================================
-- 6. get_merchant_earnings_summary — 改为基于 order_items + 核销收入
-- =============================================================
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
SET search_path = public
AS $$
DECLARE
  v_month_end date;
  v_settlement_cutoff timestamptz;
BEGIN
  v_month_end := (p_month_start + INTERVAL '1 month - 1 day')::date;
  v_settlement_cutoff := now() - INTERVAL '7 days';

  RETURN QUERY
  SELECT
    -- 本月核销收入（已核销且非退款）
    COALESCE((
      SELECT SUM(oi.unit_price)
      FROM order_items oi
      WHERE oi.redeemed_at IS NOT NULL
        AND date(oi.redeemed_at) BETWEEN p_month_start AND v_month_end
        AND oi.customer_status NOT IN ('refund_success', 'refund_pending')
        AND COALESCE(oi.redeemed_merchant_id, oi.purchased_merchant_id) = p_merchant_id
    ), 0)::numeric AS total_revenue,

    -- 待结算：已核销但核销时间不足 7 天
    COALESCE((
      SELECT SUM(oi.unit_price * 0.85)
      FROM order_items oi
      WHERE oi.redeemed_at IS NOT NULL
        AND oi.redeemed_at > v_settlement_cutoff
        AND date(oi.redeemed_at) BETWEEN p_month_start AND v_month_end
        AND oi.customer_status = 'used'
        AND COALESCE(oi.redeemed_merchant_id, oi.purchased_merchant_id) = p_merchant_id
    ), 0)::numeric AS pending_settlement,

    -- 已结算
    COALESCE((
      SELECT SUM(s.net_amount)
      FROM settlements s
      WHERE s.merchant_id = p_merchant_id
        AND s.status = 'paid'
        AND s.period_start >= p_month_start
        AND s.period_end <= v_month_end
    ), 0)::numeric AS settled_amount,

    -- 退款金额
    COALESCE((
      SELECT SUM(oi.unit_price)
      FROM order_items oi
      WHERE oi.customer_status = 'refund_success'
        AND oi.refunded_at IS NOT NULL
        AND date(oi.refunded_at) BETWEEN p_month_start AND v_month_end
        AND COALESCE(oi.redeemed_merchant_id, oi.purchased_merchant_id) = p_merchant_id
    ), 0)::numeric AS refunded_amount;
END;
$$;


-- =============================================================
-- 7. get_merchant_transactions — 改为基于 order_items
-- =============================================================
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
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    oi.order_id                            AS order_id,
    oi.unit_price                          AS amount,
    ROUND(oi.unit_price * 0.15, 2)         AS platform_fee,
    ROUND(oi.unit_price * 0.85, 2)         AS net_amount,
    oi.customer_status::text               AS status,
    oi.redeemed_at                         AS created_at,
    COUNT(*) OVER ()                       AS total_count
  FROM order_items oi
  WHERE oi.redeemed_at IS NOT NULL
    AND COALESCE(oi.redeemed_merchant_id, oi.purchased_merchant_id) = p_merchant_id
    AND oi.customer_status NOT IN ('refund_success')
    AND (p_date_from IS NULL OR date(oi.redeemed_at) >= p_date_from)
    AND (p_date_to   IS NULL OR date(oi.redeemed_at) <= p_date_to)
  ORDER BY oi.redeemed_at DESC
  LIMIT p_per_page
  OFFSET (p_page - 1) * p_per_page;
END;
$$;


-- =============================================================
-- 8. get_merchant_report_data — 改为基于 order_items 核销日期
-- =============================================================
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
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    date(oi.redeemed_at)                                    AS report_date,
    COUNT(*)                                                AS order_count,
    COALESCE(SUM(oi.unit_price), 0)                         AS gross_amount,
    COALESCE(ROUND(SUM(oi.unit_price) * 0.15, 2), 0)        AS platform_fee,
    COALESCE(ROUND(SUM(oi.unit_price) * 0.85, 2), 0)        AS net_amount
  FROM order_items oi
  WHERE oi.redeemed_at IS NOT NULL
    AND COALESCE(oi.redeemed_merchant_id, oi.purchased_merchant_id) = p_merchant_id
    AND oi.customer_status NOT IN ('refund_success')
    AND date(oi.redeemed_at) BETWEEN p_date_from AND p_date_to
  GROUP BY date(oi.redeemed_at)
  ORDER BY date(oi.redeemed_at) ASC;
END;
$$;


-- =============================================================
-- 9. 权限授予
-- =============================================================
GRANT EXECUTE ON FUNCTION public.get_merchant_daily_stats(uuid)  TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_merchant_weekly_trend(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_brand_daily_stats(uuid)     TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_brand_weekly_trend(uuid)    TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_brand_store_rankings(uuid, text, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_merchant_earnings_summary(uuid, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_merchant_transactions(uuid, date, date, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_merchant_report_data(uuid, date, date) TO authenticated;
