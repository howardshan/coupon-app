-- ============================================================
-- 统一佣金费率：废弃三档差异化费率，改为单一 commission_rate
--
-- 背景：之前按 validity_type（fixed_date / short_after_purchase /
--       long_after_purchase）收取不同比例，现在统一为一档。
--
-- 变更内容：
--   Step 1: platform_commission_config 新增 commission_rate 字段
--   Step 2: merchants 新增 commission_rate 字段（NULL=用全局默认）
--   Step 3: 重建 get_merchant_transactions RPC
--   Step 4: 重建 get_merchant_earnings_summary RPC
--   Step 5: 重建 get_merchant_report_data RPC
-- ============================================================


-- ============================================================
-- Step 1: 全局配置表新增统一费率字段
-- ============================================================
ALTER TABLE platform_commission_config
  ADD COLUMN IF NOT EXISTS commission_rate DECIMAL(5,4) NOT NULL DEFAULT 0.15;

-- 用现有 fixed_date_rate 的值填充（fixed_date 和 long_after_purchase 都是 15%）
UPDATE platform_commission_config
SET commission_rate = fixed_date_rate
WHERE commission_rate IS DISTINCT FROM fixed_date_rate;

-- 旧三档字段标记 deprecated（保留向后兼容，不删除）
COMMENT ON COLUMN platform_commission_config.fixed_date_rate IS
  '[DEPRECATED] 已被 commission_rate 取代，保留向后兼容。';
COMMENT ON COLUMN platform_commission_config.short_after_purchase_rate IS
  '[DEPRECATED] 已被 commission_rate 取代，保留向后兼容。';
COMMENT ON COLUMN platform_commission_config.long_after_purchase_rate IS
  '[DEPRECATED] 已被 commission_rate 取代，保留向后兼容。';


-- ============================================================
-- Step 2: merchants 表新增统一费率字段（NULL = 使用全局默认）
-- ============================================================
ALTER TABLE public.merchants
  ADD COLUMN IF NOT EXISTS commission_rate DECIMAL(5,4);

-- 用现有 commission_fixed_date_rate 的值填充
UPDATE public.merchants
SET commission_rate = commission_fixed_date_rate
WHERE commission_fixed_date_rate IS NOT NULL
  AND commission_rate IS NULL;

-- 旧三档字段标记 deprecated（保留向后兼容，不删除）
COMMENT ON COLUMN public.merchants.commission_fixed_date_rate IS
  '[DEPRECATED] 已被 commission_rate 取代，保留向后兼容。';
COMMENT ON COLUMN public.merchants.commission_short_rate IS
  '[DEPRECATED] 已被 commission_rate 取代，保留向后兼容。';
COMMENT ON COLUMN public.merchants.commission_long_rate IS
  '[DEPRECATED] 已被 commission_rate 取代，保留向后兼容。';
COMMENT ON COLUMN public.merchants.commission_rate IS
  '商家专属统一佣金费率（NULL = 使用全局 platform_commission_config.commission_rate）。';


-- ============================================================
-- Step 3: 重建 get_merchant_transactions
--
-- 简化：移除三档 CASE WHEN validity_type 逻辑，统一用 v_rate
-- 保留：免费期逻辑、商家专属费率 + 生效期逻辑、Stripe fee 逻辑
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
  order_item_id     UUID,
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
)
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  -- 全局费率
  g_rate        DECIMAL;
  g_stripe_rate DECIMAL;
  g_stripe_flat DECIMAL;
  -- 商家专属费率（NULL 代表未设置）
  m_rate        DECIMAL;
  m_stripe_rate DECIMAL;
  m_stripe_flat DECIMAL;
  m_eff_from    DATE;
  m_eff_to      DATE;
  -- 最终生效费率
  v_rate        DECIMAL;
  v_stripe_rate DECIMAL;
  v_stripe_flat DECIMAL;
  -- 免费期截止日期
  v_commission_free_until DATE;
  v_use_merchant_rates    BOOLEAN := FALSE;
BEGIN
  -- 读取全局统一费率及 Stripe 费率
  SELECT
    commission_rate,
    COALESCE(stripe_processing_rate, 0.03),
    COALESCE(stripe_flat_fee, 0.30)
  INTO g_rate, g_stripe_rate, g_stripe_flat
  FROM platform_commission_config LIMIT 1;

  -- 读取商家专属费率、Stripe 费率、免费期截止日、生效期
  SELECT
    commission_free_until::DATE,
    commission_rate,
    commission_stripe_rate,
    commission_stripe_flat_fee,
    commission_effective_from,
    commission_effective_to
  INTO
    v_commission_free_until,
    m_rate,
    m_stripe_rate,
    m_stripe_flat,
    m_eff_from,
    m_eff_to
  FROM public.merchants WHERE id = p_merchant_id;

  -- 判断商家专属费率是否在生效期内
  IF (m_rate IS NOT NULL OR m_stripe_rate IS NOT NULL OR m_stripe_flat IS NOT NULL) THEN
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

  -- 确定最终使用的费率：商家专属（生效期内）> 全局默认
  IF v_use_merchant_rates THEN
    v_rate        := COALESCE(m_rate,        g_rate);
    v_stripe_rate := COALESCE(m_stripe_rate, g_stripe_rate);
    v_stripe_flat := COALESCE(m_stripe_flat, g_stripe_flat);
  ELSE
    v_rate        := g_rate;
    v_stripe_rate := g_stripe_rate;
    v_stripe_flat := g_stripe_flat;
  END IF;

  RETURN QUERY
  SELECT
    oi.order_id,
    oi.id AS order_item_id,
    d.title::TEXT,
    -- validity_type 保留在结果中（前端可能展示，但不再影响费率）
    COALESCE(d.validity_type, 'fixed_date')::TEXT,
    oi.unit_price,
    -- 平台抽成费率：免费期内为 0，否则统一用 v_rate
    CASE
      WHEN v_commission_free_until IS NOT NULL
           AND oi.created_at::DATE <= v_commission_free_until THEN 0::DECIMAL
      ELSE v_rate
    END AS platform_fee_rate,
    -- 平台抽成金额
    CASE
      WHEN v_commission_free_until IS NOT NULL
           AND oi.created_at::DATE <= v_commission_free_until THEN 0::NUMERIC
      ELSE ROUND(oi.unit_price * v_rate, 2)
    END AS platform_fee,
    -- Stripe 手续费：免费期内为 0
    CASE
      WHEN v_commission_free_until IS NOT NULL
           AND oi.created_at::DATE <= v_commission_free_until THEN 0::NUMERIC
      ELSE ROUND(oi.unit_price * v_stripe_rate + v_stripe_flat, 2)
    END AS stripe_fee,
    -- 商家实收
    CASE
      WHEN v_commission_free_until IS NOT NULL
           AND oi.created_at::DATE <= v_commission_free_until THEN oi.unit_price
      ELSE ROUND(
        oi.unit_price
        - oi.unit_price * v_rate
        - (oi.unit_price * v_stripe_rate + v_stripe_flat),
        2)
    END AS net_amount,
    oi.customer_status::TEXT,
    oi.created_at,
    COUNT(*) OVER ()
  FROM public.order_items oi
  JOIN public.deals d ON d.id = oi.deal_id
  WHERE COALESCE(oi.redeemed_merchant_id, d.merchant_id) = p_merchant_id
    AND oi.customer_status::TEXT NOT IN ('refund_success', 'refund_pending')
    AND (p_date_from IS NULL OR oi.created_at::DATE >= p_date_from)
    AND (p_date_to   IS NULL OR oi.created_at::DATE <= p_date_to)
  ORDER BY oi.created_at DESC
  OFFSET (p_page - 1) * p_per_page LIMIT p_per_page;
END;
$$;

GRANT EXECUTE ON FUNCTION get_merchant_transactions(UUID, DATE, DATE, INT, INT)
  TO authenticated, service_role;


-- ============================================================
-- Step 4: 重建 get_merchant_earnings_summary
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
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  g_rate        DECIMAL;
  g_stripe_rate DECIMAL;
  g_stripe_flat DECIMAL;
  m_rate        DECIMAL;
  m_stripe_rate DECIMAL;
  m_stripe_flat DECIMAL;
  m_eff_from    DATE;
  m_eff_to      DATE;
  v_rate        DECIMAL;
  v_stripe_rate DECIMAL;
  v_stripe_flat DECIMAL;
  v_commission_free_until DATE;
  v_use_merchant_rates    BOOLEAN := FALSE;
BEGIN
  -- 读取全局统一费率
  SELECT
    commission_rate,
    COALESCE(stripe_processing_rate, 0.03),
    COALESCE(stripe_flat_fee, 0.30)
  INTO g_rate, g_stripe_rate, g_stripe_flat
  FROM platform_commission_config LIMIT 1;

  -- 读取商家专属费率及免费期
  SELECT
    commission_free_until::DATE,
    commission_rate,
    commission_stripe_rate,
    commission_stripe_flat_fee,
    commission_effective_from,
    commission_effective_to
  INTO
    v_commission_free_until,
    m_rate,
    m_stripe_rate,
    m_stripe_flat,
    m_eff_from,
    m_eff_to
  FROM public.merchants WHERE id = p_merchant_id;

  -- 判断商家专属费率生效期
  IF (m_rate IS NOT NULL OR m_stripe_rate IS NOT NULL OR m_stripe_flat IS NOT NULL) THEN
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

  -- 确定最终费率
  IF v_use_merchant_rates THEN
    v_rate        := COALESCE(m_rate,        g_rate);
    v_stripe_rate := COALESCE(m_stripe_rate, g_stripe_rate);
    v_stripe_flat := COALESCE(m_stripe_flat, g_stripe_flat);
  ELSE
    v_rate        := g_rate;
    v_stripe_rate := g_stripe_rate;
    v_stripe_flat := g_stripe_flat;
  END IF;

  RETURN QUERY SELECT
    -- total_revenue：当月非退款 order_items 总金额
    COALESCE((
      SELECT SUM(oi.unit_price)
      FROM public.order_items oi
      JOIN public.deals d ON d.id = oi.deal_id
      WHERE COALESCE(oi.redeemed_merchant_id, d.merchant_id) = p_merchant_id
        AND oi.customer_status::TEXT NOT IN ('refund_success', 'refund_pending')
        AND oi.created_at::DATE >= p_month_start
        AND oi.created_at::DATE < (p_month_start + INTERVAL '1 month')::DATE
    ), 0),
    -- pending_settlement：已核销不足7天，扣除平台抽成+Stripe后的实收
    COALESCE((
      SELECT SUM(
        CASE
          WHEN v_commission_free_until IS NOT NULL
               AND oi.created_at::DATE <= v_commission_free_until THEN oi.unit_price
          ELSE oi.unit_price
             - oi.unit_price * v_rate
             - (oi.unit_price * v_stripe_rate + v_stripe_flat)
        END
      )
      FROM public.order_items oi
      JOIN public.deals d ON d.id = oi.deal_id
      WHERE COALESCE(oi.redeemed_merchant_id, d.merchant_id) = p_merchant_id
        AND oi.customer_status::TEXT = 'used'
        AND oi.redeemed_at > NOW() - INTERVAL '7 days'
    ), 0),
    -- settled_amount：已支付的结算单合计
    COALESCE((
      SELECT SUM(s.net_amount)
      FROM public.settlements s
      WHERE s.merchant_id = p_merchant_id
        AND s.status = 'paid'
        AND s.period_start >= p_month_start
        AND s.period_start < (p_month_start + INTERVAL '1 month')::DATE
    ), 0),
    -- refunded_amount：当月退款总额
    COALESCE((
      SELECT SUM(oi.unit_price)
      FROM public.order_items oi
      JOIN public.deals d ON d.id = oi.deal_id
      WHERE COALESCE(oi.redeemed_merchant_id, d.merchant_id) = p_merchant_id
        AND oi.customer_status::TEXT = 'refund_success'
        AND oi.created_at::DATE >= p_month_start
        AND oi.created_at::DATE < (p_month_start + INTERVAL '1 month')::DATE
    ), 0);
END;
$$;

GRANT EXECUTE ON FUNCTION get_merchant_earnings_summary(UUID, DATE)
  TO authenticated, service_role;


-- ============================================================
-- Step 5: 重建 get_merchant_report_data
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
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  g_rate        DECIMAL;
  g_stripe_rate DECIMAL;
  g_stripe_flat DECIMAL;
  m_rate        DECIMAL;
  m_stripe_rate DECIMAL;
  m_stripe_flat DECIMAL;
  m_eff_from    DATE;
  m_eff_to      DATE;
  v_rate        DECIMAL;
  v_stripe_rate DECIMAL;
  v_stripe_flat DECIMAL;
  v_commission_free_until DATE;
  v_use_merchant_rates    BOOLEAN := FALSE;
BEGIN
  -- 读取全局统一费率
  SELECT
    commission_rate,
    COALESCE(stripe_processing_rate, 0.03),
    COALESCE(stripe_flat_fee, 0.30)
  INTO g_rate, g_stripe_rate, g_stripe_flat
  FROM platform_commission_config LIMIT 1;

  -- 读取商家专属费率及免费期
  SELECT
    commission_free_until::DATE,
    commission_rate,
    commission_stripe_rate,
    commission_stripe_flat_fee,
    commission_effective_from,
    commission_effective_to
  INTO
    v_commission_free_until,
    m_rate,
    m_stripe_rate,
    m_stripe_flat,
    m_eff_from,
    m_eff_to
  FROM public.merchants WHERE id = p_merchant_id;

  -- 判断商家专属费率生效期
  IF (m_rate IS NOT NULL OR m_stripe_rate IS NOT NULL OR m_stripe_flat IS NOT NULL) THEN
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

  -- 确定最终费率
  IF v_use_merchant_rates THEN
    v_rate        := COALESCE(m_rate,        g_rate);
    v_stripe_rate := COALESCE(m_stripe_rate, g_stripe_rate);
    v_stripe_flat := COALESCE(m_stripe_flat, g_stripe_flat);
  ELSE
    v_rate        := g_rate;
    v_stripe_rate := g_stripe_rate;
    v_stripe_flat := g_stripe_flat;
  END IF;

  RETURN QUERY
  SELECT
    DATE(oi.created_at) AS report_date,
    COUNT(*) AS order_count,
    COALESCE(SUM(oi.unit_price), 0) AS gross_amount,
    -- 平台抽成（免费期内为 0）
    COALESCE(ROUND(SUM(
      CASE
        WHEN v_commission_free_until IS NOT NULL
             AND oi.created_at::DATE <= v_commission_free_until THEN 0
        ELSE oi.unit_price * v_rate
      END
    ), 2), 0) AS platform_fee,
    -- Stripe 手续费（免费期内为 0）
    COALESCE(ROUND(SUM(
      CASE
        WHEN v_commission_free_until IS NOT NULL
             AND oi.created_at::DATE <= v_commission_free_until THEN 0
        ELSE oi.unit_price * v_stripe_rate + v_stripe_flat
      END
    ), 2), 0) AS stripe_fee,
    -- 商家实收
    COALESCE(ROUND(SUM(
      CASE
        WHEN v_commission_free_until IS NOT NULL
             AND oi.created_at::DATE <= v_commission_free_until THEN oi.unit_price
        ELSE oi.unit_price
          - oi.unit_price * v_rate
          - (oi.unit_price * v_stripe_rate + v_stripe_flat)
      END
    ), 2), 0) AS net_amount
  FROM public.order_items oi
  JOIN public.deals d ON d.id = oi.deal_id
  WHERE COALESCE(oi.redeemed_merchant_id, d.merchant_id) = p_merchant_id
    AND oi.customer_status::TEXT NOT IN ('refund_success')
    AND DATE(oi.created_at) BETWEEN p_date_from AND p_date_to
  GROUP BY DATE(oi.created_at)
  ORDER BY DATE(oi.created_at) ASC;
END;
$$;

GRANT EXECUTE ON FUNCTION get_merchant_report_data(UUID, DATE, DATE)
  TO authenticated, service_role;
