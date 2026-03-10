-- ============================================================
-- V2.1 品牌总览 Dashboard — RPC 函数
-- 为品牌管理员提供跨门店汇总数据
-- ============================================================

-- 1. 品牌级今日汇总统计
CREATE OR REPLACE FUNCTION get_brand_daily_stats(p_brand_id UUID)
RETURNS TABLE(
  total_stores       INT,
  online_stores      INT,
  today_orders       BIGINT,
  today_redemptions  BIGINT,
  today_revenue      DECIMAL,
  pending_coupons    BIGINT
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    COUNT(m.id)::INT AS total_stores,
    COUNT(m.id) FILTER (WHERE m.is_online = true)::INT AS online_stores,
    COALESCE(SUM(sub.today_orders), 0)::BIGINT,
    COALESCE(SUM(sub.today_redemptions), 0)::BIGINT,
    COALESCE(SUM(sub.today_revenue), 0)::DECIMAL,
    COALESCE(SUM(sub.pending_coupons), 0)::BIGINT
  FROM merchants m
  LEFT JOIN LATERAL (
    SELECT
      COUNT(o.id) FILTER (WHERE o.created_at::DATE = CURRENT_DATE) AS today_orders,
      0::BIGINT AS today_redemptions,
      COALESCE(SUM(o.total_amount) FILTER (WHERE o.created_at::DATE = CURRENT_DATE AND o.status = 'completed'), 0) AS today_revenue,
      0::BIGINT AS pending_coupons
    FROM orders o
    WHERE o.merchant_id = m.id
  ) sub ON true
  LEFT JOIN LATERAL (
    SELECT
      COUNT(c.id) FILTER (WHERE c.used_at::DATE = CURRENT_DATE AND c.status = 'used') AS redemptions,
      COUNT(c.id) FILTER (WHERE c.status = 'unused') AS pending
    FROM coupons c
    WHERE c.merchant_id = m.id
  ) coup ON true
  WHERE m.brand_id = p_brand_id
    AND m.status = 'approved';

  -- 简化版：直接聚合
  -- 上面的 LATERAL JOIN 在大数据量下可能较慢，
  -- 用简单子查询替代
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 用简化版替换
DROP FUNCTION IF EXISTS get_brand_daily_stats(UUID);

CREATE OR REPLACE FUNCTION get_brand_daily_stats(p_brand_id UUID)
RETURNS TABLE(
  total_stores       INT,
  online_stores      INT,
  today_orders       BIGINT,
  today_redemptions  BIGINT,
  today_revenue      DECIMAL,
  pending_coupons    BIGINT
) AS $$
DECLARE
  v_merchant_ids UUID[];
BEGIN
  -- 获取品牌下所有已审核门店 ID
  SELECT ARRAY_AGG(m.id) INTO v_merchant_ids
  FROM merchants m
  WHERE m.brand_id = p_brand_id AND m.status = 'approved';

  IF v_merchant_ids IS NULL THEN
    RETURN QUERY SELECT 0::INT, 0::INT, 0::BIGINT, 0::BIGINT, 0::DECIMAL, 0::BIGINT;
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    (SELECT COUNT(*)::INT FROM merchants WHERE brand_id = p_brand_id AND status = 'approved'),
    (SELECT COUNT(*)::INT FROM merchants WHERE brand_id = p_brand_id AND status = 'approved' AND is_online = true),
    (SELECT COUNT(*)::BIGINT FROM orders WHERE merchant_id = ANY(v_merchant_ids) AND created_at::DATE = CURRENT_DATE),
    (SELECT COUNT(*)::BIGINT FROM coupons WHERE merchant_id = ANY(v_merchant_ids) AND status = 'used' AND used_at::DATE = CURRENT_DATE),
    (SELECT COALESCE(SUM(total_amount), 0)::DECIMAL FROM orders WHERE merchant_id = ANY(v_merchant_ids) AND status = 'completed' AND created_at::DATE = CURRENT_DATE),
    (SELECT COUNT(*)::BIGINT FROM coupons WHERE merchant_id = ANY(v_merchant_ids) AND status = 'unused');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_brand_daily_stats TO authenticated;

-- 2. 品牌级 7 天趋势（合并所有门店）
CREATE OR REPLACE FUNCTION get_brand_weekly_trend(p_brand_id UUID)
RETURNS TABLE(
  trend_date    DATE,
  daily_orders  BIGINT,
  daily_revenue DECIMAL
) AS $$
DECLARE
  v_merchant_ids UUID[];
BEGIN
  SELECT ARRAY_AGG(m.id) INTO v_merchant_ids
  FROM merchants m
  WHERE m.brand_id = p_brand_id AND m.status = 'approved';

  IF v_merchant_ids IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    d.dt::DATE AS trend_date,
    COALESCE(COUNT(o.id), 0)::BIGINT AS daily_orders,
    COALESCE(SUM(o.total_amount) FILTER (WHERE o.status = 'completed'), 0)::DECIMAL AS daily_revenue
  FROM generate_series(CURRENT_DATE - INTERVAL '6 days', CURRENT_DATE, '1 day') AS d(dt)
  LEFT JOIN orders o ON o.merchant_id = ANY(v_merchant_ids) AND o.created_at::DATE = d.dt::DATE
  GROUP BY d.dt
  ORDER BY d.dt ASC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_brand_weekly_trend TO authenticated;

-- 3. 门店对比排行
CREATE OR REPLACE FUNCTION get_brand_store_rankings(
  p_brand_id UUID,
  p_sort_by  TEXT DEFAULT 'revenue',  -- 'revenue' | 'orders' | 'rating'
  p_days     INT DEFAULT 30
)
RETURNS TABLE(
  store_id       UUID,
  store_name     TEXT,
  store_address  TEXT,
  is_online      BOOL,
  total_orders   BIGINT,
  total_revenue  DECIMAL,
  total_redeemed BIGINT,
  avg_rating     DECIMAL,
  review_count   BIGINT,
  refund_rate    DECIMAL
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    m.id AS store_id,
    m.name AS store_name,
    m.address AS store_address,
    m.is_online,
    COALESCE(os.cnt, 0)::BIGINT AS total_orders,
    COALESCE(os.rev, 0)::DECIMAL AS total_revenue,
    COALESCE(cs.redeemed, 0)::BIGINT AS total_redeemed,
    COALESCE(m.rating, 0)::DECIMAL AS avg_rating,
    COALESCE(rs.rcnt, 0)::BIGINT AS review_count,
    CASE
      WHEN COALESCE(os.cnt, 0) > 0
      THEN (COALESCE(rf.refund_cnt, 0)::DECIMAL / os.cnt * 100)
      ELSE 0
    END AS refund_rate
  FROM merchants m
  LEFT JOIN LATERAL (
    SELECT COUNT(o.id) AS cnt, SUM(o.total_amount) FILTER (WHERE o.status = 'completed') AS rev
    FROM orders o
    WHERE o.merchant_id = m.id AND o.created_at >= CURRENT_DATE - (p_days || ' days')::INTERVAL
  ) os ON true
  LEFT JOIN LATERAL (
    SELECT COUNT(c.id) AS redeemed
    FROM coupons c
    WHERE c.merchant_id = m.id AND c.status = 'used' AND c.used_at >= CURRENT_DATE - (p_days || ' days')::INTERVAL
  ) cs ON true
  LEFT JOIN LATERAL (
    SELECT COUNT(r.id) AS rcnt
    FROM reviews r
    WHERE r.merchant_id = m.id
  ) rs ON true
  LEFT JOIN LATERAL (
    SELECT COUNT(o2.id) AS refund_cnt
    FROM orders o2
    WHERE o2.merchant_id = m.id AND o2.status = 'refunded' AND o2.created_at >= CURRENT_DATE - (p_days || ' days')::INTERVAL
  ) rf ON true
  WHERE m.brand_id = p_brand_id AND m.status = 'approved'
  ORDER BY
    CASE p_sort_by
      WHEN 'revenue' THEN COALESCE(os.rev, 0)
      WHEN 'orders' THEN COALESCE(os.cnt, 0)::DECIMAL
      WHEN 'rating' THEN COALESCE(m.rating, 0)
      ELSE COALESCE(os.rev, 0)
    END DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_brand_store_rankings TO authenticated;

-- 4. 门店健康度检查
CREATE OR REPLACE FUNCTION get_brand_store_health(p_brand_id UUID)
RETURNS TABLE(
  store_id      UUID,
  store_name    TEXT,
  alert_type    TEXT,   -- 'high_refund' | 'low_rating' | 'no_orders' | 'offline'
  alert_message TEXT,
  alert_value   DECIMAL
) AS $$
BEGIN
  -- 退款率过高（>15%）
  RETURN QUERY
  SELECT m.id, m.name, 'high_refund'::TEXT,
    ('Refund rate ' || ROUND(refund_pct, 1) || '% in last 7 days')::TEXT,
    refund_pct
  FROM merchants m
  JOIN LATERAL (
    SELECT
      COUNT(*) FILTER (WHERE o.status = 'refunded')::DECIMAL /
      NULLIF(COUNT(*), 0) * 100 AS refund_pct
    FROM orders o
    WHERE o.merchant_id = m.id AND o.created_at >= CURRENT_DATE - INTERVAL '7 days'
  ) stats ON true
  WHERE m.brand_id = p_brand_id AND m.status = 'approved' AND stats.refund_pct > 15;

  -- 评分下降（低于 3.5）
  RETURN QUERY
  SELECT m.id, m.name, 'low_rating'::TEXT,
    ('Rating dropped to ' || ROUND(COALESCE(m.rating, 0), 1))::TEXT,
    COALESCE(m.rating, 0)::DECIMAL
  FROM merchants m
  WHERE m.brand_id = p_brand_id AND m.status = 'approved' AND COALESCE(m.rating, 0) < 3.5 AND COALESCE(m.rating, 0) > 0;

  -- 7天无订单
  RETURN QUERY
  SELECT m.id, m.name, 'no_orders'::TEXT,
    'No orders in last 7 days'::TEXT,
    0::DECIMAL
  FROM merchants m
  WHERE m.brand_id = p_brand_id AND m.status = 'approved'
    AND NOT EXISTS (
      SELECT 1 FROM orders o WHERE o.merchant_id = m.id AND o.created_at >= CURRENT_DATE - INTERVAL '7 days'
    );

  -- 离线状态
  RETURN QUERY
  SELECT m.id, m.name, 'offline'::TEXT,
    'Store is currently offline'::TEXT,
    0::DECIMAL
  FROM merchants m
  WHERE m.brand_id = p_brand_id AND m.status = 'approved' AND m.is_online = false;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_brand_store_health TO authenticated;
