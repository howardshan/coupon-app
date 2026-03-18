-- ============================================================
-- Stripe 手续费实际扣除 + 商家费率生效日期过滤
-- 改动：
--   1. get_merchant_transactions 新增 stripe_fee 列，net_amount 减去 stripe_fee
--   2. 商家自定义费率仅在 effective_from~effective_to 内生效，否则回落全局
--   3. 免费期内 platform_fee=0 且 stripe_fee=0（平台承担）
--   4. get_merchant_earnings_summary 的 pending_settlement 也扣除 stripe_fee
--   5. get_merchant_report_data 新增 stripe_fee 列
-- ============================================================

-- ============================================================
-- 1. 重建 get_merchant_transactions
-- ============================================================
DROP FUNCTION IF EXISTS get_merchant_transactions(UUID, DATE, DATE, INT, INT);

CREATE FUNCTION get_merchant_transactions(
  p_merchant_id UUID,
  p_date_from   DATE DEFAULT NULL,
  p_date_to     DATE DEFAULT NULL,
  p_page        INT  DEFAULT 1,
  p_per_page    INT  DEFAULT 20
)
RETURNS TABLE (
  order_id          UUID,
  deal_title        TEXT,
  validity_type     TEXT,
  amount            NUMERIC,
  platform_fee_rate DECIMAL,
  platform_fee      NUMERIC,
  stripe_fee        NUMERIC,
  net_amount        NUMERIC,
  status            TEXT,
  created_at        TIMESTAMPTZ,
  total_count       BIGINT
) AS $$
DECLARE
  -- 全局默认费率
  g_fixed_rate   DECIMAL;
  g_short_rate   DECIMAL;
  g_long_rate    DECIMAL;
  g_stripe_rate  DECIMAL;
  g_stripe_flat  DECIMAL;
  -- 商家专属费率（可能为 NULL）
  m_fixed_rate   DECIMAL;
  m_short_rate   DECIMAL;
  m_long_rate    DECIMAL;
  m_stripe_rate  DECIMAL;
  m_stripe_flat  DECIMAL;
  m_eff_from     DATE;
  m_eff_to       DATE;
  -- 最终使用的费率
  v_fixed_rate   DECIMAL;
  v_short_rate   DECIMAL;
  v_long_rate    DECIMAL;
  v_stripe_rate  DECIMAL;
  v_stripe_flat  DECIMAL;
  -- 免费期
  v_commission_free_until DATE;
  -- 是否使用商家自定义费率
  v_use_merchant_rates BOOLEAN := FALSE;
BEGIN
  -- 读取全局默认费率（含 Stripe）
  SELECT
    fixed_date_rate, short_after_purchase_rate, long_after_purchase_rate,
    COALESCE(stripe_processing_rate, 0.03), COALESCE(stripe_flat_fee, 0.30)
  INTO g_fixed_rate, g_short_rate, g_long_rate, g_stripe_rate, g_stripe_flat
  FROM platform_commission_config LIMIT 1;

  -- 读取商家专属费率 + 免费期 + 生效日期
  SELECT
    commission_free_until::DATE,
    commission_fixed_date_rate, commission_short_rate, commission_long_rate,
    commission_stripe_rate, commission_stripe_flat_fee,
    commission_effective_from, commission_effective_to
  INTO
    v_commission_free_until,
    m_fixed_rate, m_short_rate, m_long_rate,
    m_stripe_rate, m_stripe_flat,
    m_eff_from, m_eff_to
  FROM public.merchants WHERE id = p_merchant_id;

  -- 判断商家自定义费率是否在生效期内（today）
  -- 任一自定义费率不为 NULL 才判断生效期
  IF (m_fixed_rate IS NOT NULL OR m_short_rate IS NOT NULL OR m_long_rate IS NOT NULL
      OR m_stripe_rate IS NOT NULL OR m_stripe_flat IS NOT NULL) THEN
    -- 如果设了生效期，检查当前日期是否在范围内
    IF (m_eff_from IS NULL AND m_eff_to IS NULL) THEN
      -- 没设生效期 → 永久生效
      v_use_merchant_rates := TRUE;
    ELSIF (m_eff_from IS NOT NULL AND m_eff_to IS NOT NULL) THEN
      v_use_merchant_rates := (CURRENT_DATE >= m_eff_from AND CURRENT_DATE <= m_eff_to);
    ELSIF (m_eff_from IS NOT NULL) THEN
      v_use_merchant_rates := (CURRENT_DATE >= m_eff_from);
    ELSIF (m_eff_to IS NOT NULL) THEN
      v_use_merchant_rates := (CURRENT_DATE <= m_eff_to);
    END IF;
  END IF;

  -- 最终费率：商家生效期内用商家专属，否则用全局
  IF v_use_merchant_rates THEN
    v_fixed_rate  := COALESCE(m_fixed_rate,  g_fixed_rate);
    v_short_rate  := COALESCE(m_short_rate,  g_short_rate);
    v_long_rate   := COALESCE(m_long_rate,   g_long_rate);
    v_stripe_rate := COALESCE(m_stripe_rate, g_stripe_rate);
    v_stripe_flat := COALESCE(m_stripe_flat, g_stripe_flat);
  ELSE
    v_fixed_rate  := g_fixed_rate;
    v_short_rate  := g_short_rate;
    v_long_rate   := g_long_rate;
    v_stripe_rate := g_stripe_rate;
    v_stripe_flat := g_stripe_flat;
  END IF;

  RETURN QUERY
  SELECT
    o.id,
    d.title::TEXT,
    COALESCE(d.validity_type, 'fixed_date')::TEXT,
    o.total_amount,
    -- 平台抽成费率
    CASE
      WHEN v_commission_free_until IS NOT NULL
           AND o.created_at::DATE <= v_commission_free_until THEN 0::DECIMAL
      WHEN COALESCE(d.validity_type, 'fixed_date') = 'short_after_purchase' THEN v_short_rate
      WHEN COALESCE(d.validity_type, 'fixed_date') = 'long_after_purchase'  THEN v_long_rate
      ELSE v_fixed_rate
    END AS platform_fee_rate,
    -- 平台抽成金额
    ROUND(o.total_amount * CASE
      WHEN v_commission_free_until IS NOT NULL
           AND o.created_at::DATE <= v_commission_free_until THEN 0
      WHEN COALESCE(d.validity_type, 'fixed_date') = 'short_after_purchase' THEN v_short_rate
      WHEN COALESCE(d.validity_type, 'fixed_date') = 'long_after_purchase'  THEN v_long_rate
      ELSE v_fixed_rate
    END, 2) AS platform_fee,
    -- Stripe 手续费（免费期内为 0，平台承担）
    CASE
      WHEN v_commission_free_until IS NOT NULL
           AND o.created_at::DATE <= v_commission_free_until THEN 0::NUMERIC
      ELSE ROUND(o.total_amount * v_stripe_rate + v_stripe_flat, 2)
    END AS stripe_fee,
    -- 商家实收 = 总额 - 平台抽成 - Stripe 手续费
    CASE
      WHEN v_commission_free_until IS NOT NULL
           AND o.created_at::DATE <= v_commission_free_until THEN o.total_amount
      ELSE ROUND(o.total_amount
        - o.total_amount * CASE
            WHEN COALESCE(d.validity_type, 'fixed_date') = 'short_after_purchase' THEN v_short_rate
            WHEN COALESCE(d.validity_type, 'fixed_date') = 'long_after_purchase'  THEN v_long_rate
            ELSE v_fixed_rate
          END
        - (o.total_amount * v_stripe_rate + v_stripe_flat)
      , 2)
    END AS net_amount,
    o.status::TEXT,
    o.created_at,
    COUNT(*) OVER ()
  FROM public.orders o
  JOIN public.deals d ON d.id = o.deal_id
  LEFT JOIN public.coupons c ON c.order_id = o.id
  WHERE COALESCE(c.redeemed_at_merchant_id, d.merchant_id) = p_merchant_id
    AND o.status NOT IN ('refunded', 'refund_failed')
    AND (p_date_from IS NULL OR o.created_at::DATE >= p_date_from)
    AND (p_date_to   IS NULL OR o.created_at::DATE <= p_date_to)
  ORDER BY o.created_at DESC
  OFFSET (p_page - 1) * p_per_page LIMIT p_per_page;
END;
$$ LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION get_merchant_transactions(UUID, DATE, DATE, INT, INT)
  TO authenticated, service_role;


-- ============================================================
-- 2. 重建 get_merchant_earnings_summary（扣除 Stripe fee）
-- ============================================================
DROP FUNCTION IF EXISTS get_merchant_earnings_summary(UUID, DATE);

CREATE FUNCTION get_merchant_earnings_summary(
  p_merchant_id UUID,
  p_month_start DATE
)
RETURNS TABLE (
  total_revenue      NUMERIC,
  pending_settlement NUMERIC,
  settled_amount     NUMERIC,
  refunded_amount    NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  g_fixed_rate   DECIMAL;
  g_short_rate   DECIMAL;
  g_long_rate    DECIMAL;
  g_stripe_rate  DECIMAL;
  g_stripe_flat  DECIMAL;
  m_fixed_rate   DECIMAL;
  m_short_rate   DECIMAL;
  m_long_rate    DECIMAL;
  m_stripe_rate  DECIMAL;
  m_stripe_flat  DECIMAL;
  m_eff_from     DATE;
  m_eff_to       DATE;
  v_fixed_rate   DECIMAL;
  v_short_rate   DECIMAL;
  v_long_rate    DECIMAL;
  v_stripe_rate  DECIMAL;
  v_stripe_flat  DECIMAL;
  v_commission_free_until DATE;
  v_use_merchant_rates BOOLEAN := FALSE;
BEGIN
  -- 读取全局费率
  SELECT
    fixed_date_rate, short_after_purchase_rate, long_after_purchase_rate,
    COALESCE(stripe_processing_rate, 0.03), COALESCE(stripe_flat_fee, 0.30)
  INTO g_fixed_rate, g_short_rate, g_long_rate, g_stripe_rate, g_stripe_flat
  FROM platform_commission_config LIMIT 1;

  -- 读取商家专属
  SELECT
    commission_free_until::DATE,
    commission_fixed_date_rate, commission_short_rate, commission_long_rate,
    commission_stripe_rate, commission_stripe_flat_fee,
    commission_effective_from, commission_effective_to
  INTO
    v_commission_free_until,
    m_fixed_rate, m_short_rate, m_long_rate,
    m_stripe_rate, m_stripe_flat,
    m_eff_from, m_eff_to
  FROM public.merchants WHERE id = p_merchant_id;

  -- 判断生效期
  IF (m_fixed_rate IS NOT NULL OR m_short_rate IS NOT NULL OR m_long_rate IS NOT NULL
      OR m_stripe_rate IS NOT NULL OR m_stripe_flat IS NOT NULL) THEN
    IF (m_eff_from IS NULL AND m_eff_to IS NULL) THEN
      v_use_merchant_rates := TRUE;
    ELSIF (m_eff_from IS NOT NULL AND m_eff_to IS NOT NULL) THEN
      v_use_merchant_rates := (CURRENT_DATE >= m_eff_from AND CURRENT_DATE <= m_eff_to);
    ELSIF (m_eff_from IS NOT NULL) THEN
      v_use_merchant_rates := (CURRENT_DATE >= m_eff_from);
    ELSIF (m_eff_to IS NOT NULL) THEN
      v_use_merchant_rates := (CURRENT_DATE <= m_eff_to);
    END IF;
  END IF;

  IF v_use_merchant_rates THEN
    v_fixed_rate  := COALESCE(m_fixed_rate,  g_fixed_rate);
    v_short_rate  := COALESCE(m_short_rate,  g_short_rate);
    v_long_rate   := COALESCE(m_long_rate,   g_long_rate);
    v_stripe_rate := COALESCE(m_stripe_rate, g_stripe_rate);
    v_stripe_flat := COALESCE(m_stripe_flat, g_stripe_flat);
  ELSE
    v_fixed_rate  := g_fixed_rate;
    v_short_rate  := g_short_rate;
    v_long_rate   := g_long_rate;
    v_stripe_rate := g_stripe_rate;
    v_stripe_flat := g_stripe_flat;
  END IF;

  RETURN QUERY SELECT
    -- total_revenue：当月非退款订单总金额
    COALESCE((
      SELECT SUM(o.total_amount)
      FROM public.orders o
      JOIN public.coupons c ON c.order_id = o.id
      JOIN public.deals d ON d.id = o.deal_id
      WHERE COALESCE(c.redeemed_at_merchant_id, d.merchant_id) = p_merchant_id
        AND o.status NOT IN ('refunded','refund_failed')
        AND o.created_at::DATE >= p_month_start
        AND o.created_at::DATE < (p_month_start + INTERVAL '1 month')::DATE
    ), 0),
    -- pending_settlement：已核销不足7天，扣除平台抽成+Stripe后的实收
    COALESCE((
      SELECT SUM(
        CASE
          WHEN v_commission_free_until IS NOT NULL
               AND o.created_at::DATE <= v_commission_free_until THEN o.total_amount
          ELSE o.total_amount
            - o.total_amount * CASE
                WHEN COALESCE(d.validity_type,'fixed_date') = 'short_after_purchase' THEN v_short_rate
                WHEN COALESCE(d.validity_type,'fixed_date') = 'long_after_purchase'  THEN v_long_rate
                ELSE v_fixed_rate
              END
            - (o.total_amount * v_stripe_rate + v_stripe_flat)
        END
      )
      FROM public.orders o
      JOIN public.coupons c ON c.order_id = o.id
      JOIN public.deals d ON d.id = o.deal_id
      WHERE COALESCE(c.redeemed_at_merchant_id, d.merchant_id) = p_merchant_id
        AND c.status = 'used'
        AND c.used_at > NOW() - INTERVAL '7 days'
    ), 0),
    -- settled_amount
    COALESCE((
      SELECT SUM(s.net_amount)
      FROM public.settlements s
      WHERE s.merchant_id = p_merchant_id
        AND s.status = 'paid'
        AND s.period_start >= p_month_start
        AND s.period_start < (p_month_start + INTERVAL '1 month')::DATE
    ), 0),
    -- refunded_amount
    COALESCE((
      SELECT SUM(o.total_amount)
      FROM public.orders o
      JOIN public.coupons c ON c.order_id = o.id
      JOIN public.deals d ON d.id = o.deal_id
      WHERE COALESCE(c.redeemed_at_merchant_id, d.merchant_id) = p_merchant_id
        AND o.status = 'refunded'
        AND o.created_at::DATE >= p_month_start
        AND o.created_at::DATE < (p_month_start + INTERVAL '1 month')::DATE
    ), 0);
END;
$$;

GRANT EXECUTE ON FUNCTION get_merchant_earnings_summary(UUID, DATE)
  TO authenticated, service_role;


-- ============================================================
-- 3. 重建 get_merchant_report_data（新增 stripe_fee 列）
-- ============================================================
DROP FUNCTION IF EXISTS get_merchant_report_data(UUID, DATE, DATE);

CREATE FUNCTION get_merchant_report_data(
  p_merchant_id UUID,
  p_date_from   DATE,
  p_date_to     DATE
)
RETURNS TABLE (
  report_date  DATE,
  order_count  BIGINT,
  gross_amount NUMERIC,
  platform_fee NUMERIC,
  stripe_fee   NUMERIC,
  net_amount   NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  g_fixed_rate   DECIMAL;
  g_short_rate   DECIMAL;
  g_long_rate    DECIMAL;
  g_stripe_rate  DECIMAL;
  g_stripe_flat  DECIMAL;
  m_fixed_rate   DECIMAL;
  m_short_rate   DECIMAL;
  m_long_rate    DECIMAL;
  m_stripe_rate  DECIMAL;
  m_stripe_flat  DECIMAL;
  m_eff_from     DATE;
  m_eff_to       DATE;
  v_fixed_rate   DECIMAL;
  v_short_rate   DECIMAL;
  v_long_rate    DECIMAL;
  v_stripe_rate  DECIMAL;
  v_stripe_flat  DECIMAL;
  v_commission_free_until DATE;
  v_use_merchant_rates BOOLEAN := FALSE;
BEGIN
  SELECT
    fixed_date_rate, short_after_purchase_rate, long_after_purchase_rate,
    COALESCE(stripe_processing_rate, 0.03), COALESCE(stripe_flat_fee, 0.30)
  INTO g_fixed_rate, g_short_rate, g_long_rate, g_stripe_rate, g_stripe_flat
  FROM platform_commission_config LIMIT 1;

  SELECT
    commission_free_until::DATE,
    commission_fixed_date_rate, commission_short_rate, commission_long_rate,
    commission_stripe_rate, commission_stripe_flat_fee,
    commission_effective_from, commission_effective_to
  INTO
    v_commission_free_until,
    m_fixed_rate, m_short_rate, m_long_rate,
    m_stripe_rate, m_stripe_flat,
    m_eff_from, m_eff_to
  FROM public.merchants WHERE id = p_merchant_id;

  IF (m_fixed_rate IS NOT NULL OR m_short_rate IS NOT NULL OR m_long_rate IS NOT NULL
      OR m_stripe_rate IS NOT NULL OR m_stripe_flat IS NOT NULL) THEN
    IF (m_eff_from IS NULL AND m_eff_to IS NULL) THEN
      v_use_merchant_rates := TRUE;
    ELSIF (m_eff_from IS NOT NULL AND m_eff_to IS NOT NULL) THEN
      v_use_merchant_rates := (CURRENT_DATE >= m_eff_from AND CURRENT_DATE <= m_eff_to);
    ELSIF (m_eff_from IS NOT NULL) THEN
      v_use_merchant_rates := (CURRENT_DATE >= m_eff_from);
    ELSIF (m_eff_to IS NOT NULL) THEN
      v_use_merchant_rates := (CURRENT_DATE <= m_eff_to);
    END IF;
  END IF;

  IF v_use_merchant_rates THEN
    v_fixed_rate  := COALESCE(m_fixed_rate,  g_fixed_rate);
    v_short_rate  := COALESCE(m_short_rate,  g_short_rate);
    v_long_rate   := COALESCE(m_long_rate,   g_long_rate);
    v_stripe_rate := COALESCE(m_stripe_rate, g_stripe_rate);
    v_stripe_flat := COALESCE(m_stripe_flat, g_stripe_flat);
  ELSE
    v_fixed_rate  := g_fixed_rate;
    v_short_rate  := g_short_rate;
    v_long_rate   := g_long_rate;
    v_stripe_rate := g_stripe_rate;
    v_stripe_flat := g_stripe_flat;
  END IF;

  RETURN QUERY
  SELECT
    DATE(o.created_at) AS report_date,
    COUNT(*) AS order_count,
    COALESCE(SUM(o.total_amount), 0) AS gross_amount,
    -- 平台抽成
    COALESCE(ROUND(SUM(
      CASE
        WHEN v_commission_free_until IS NOT NULL
             AND o.created_at::DATE <= v_commission_free_until THEN 0
        ELSE o.total_amount * CASE
          WHEN COALESCE(d.validity_type,'fixed_date') = 'short_after_purchase' THEN v_short_rate
          WHEN COALESCE(d.validity_type,'fixed_date') = 'long_after_purchase'  THEN v_long_rate
          ELSE v_fixed_rate
        END
      END
    ), 2), 0) AS platform_fee,
    -- Stripe 手续费
    COALESCE(ROUND(SUM(
      CASE
        WHEN v_commission_free_until IS NOT NULL
             AND o.created_at::DATE <= v_commission_free_until THEN 0
        ELSE o.total_amount * v_stripe_rate + v_stripe_flat
      END
    ), 2), 0) AS stripe_fee,
    -- 商家实收
    COALESCE(ROUND(SUM(
      CASE
        WHEN v_commission_free_until IS NOT NULL
             AND o.created_at::DATE <= v_commission_free_until THEN o.total_amount
        ELSE o.total_amount
          - o.total_amount * CASE
              WHEN COALESCE(d.validity_type,'fixed_date') = 'short_after_purchase' THEN v_short_rate
              WHEN COALESCE(d.validity_type,'fixed_date') = 'long_after_purchase'  THEN v_long_rate
              ELSE v_fixed_rate
            END
          - (o.total_amount * v_stripe_rate + v_stripe_flat)
      END
    ), 2), 0) AS net_amount
  FROM public.orders o
  JOIN public.deals d ON d.id = o.deal_id
  LEFT JOIN public.coupons c ON c.order_id = o.id
  WHERE COALESCE(c.redeemed_at_merchant_id, d.merchant_id) = p_merchant_id
    AND o.status NOT IN ('refunded')
    AND DATE(o.created_at) BETWEEN p_date_from AND p_date_to
  GROUP BY DATE(o.created_at)
  ORDER BY DATE(o.created_at) ASC;
END;
$$;

GRANT EXECUTE ON FUNCTION get_merchant_report_data(UUID, DATE, DATE)
  TO authenticated, service_role;
