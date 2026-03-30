-- ============================================================
-- Brand Commission（品牌佣金）
--
-- 品牌可以对旗下门店的交易抽取佣金。
-- 公式: net_amount = unit_price - platform_fee - brand_fee - stripe_fee
-- brand_fee = unit_price × brands.commission_rate
-- 品牌佣金基于 unit_price 计算，与平台佣金平级。
-- Stripe 费只从商家扣，品牌佣金是净收入。
-- ============================================================


-- ============================================================
-- 1. brands 表新增字段
-- ============================================================
ALTER TABLE public.brands
  ADD COLUMN IF NOT EXISTS commission_rate DECIMAL(5,4) DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS stripe_account_id TEXT,
  ADD COLUMN IF NOT EXISTS stripe_account_email TEXT,
  ADD COLUMN IF NOT EXISTS stripe_account_status TEXT DEFAULT 'not_connected';

COMMENT ON COLUMN public.brands.commission_rate IS
  '品牌佣金费率（如 0.15 = 15%）。NULL 表示不抽佣。';
COMMENT ON COLUMN public.brands.stripe_account_id IS
  '品牌 Stripe Connect Express 账户 ID。';
COMMENT ON COLUMN public.brands.stripe_account_status IS
  '品牌 Stripe 账户状态：not_connected / pending / connected / restricted。';


-- ============================================================
-- 2. brand_withdrawals 表（品牌提现记录）
-- ============================================================
CREATE TABLE IF NOT EXISTS public.brand_withdrawals (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  brand_id          UUID        NOT NULL REFERENCES public.brands(id) ON DELETE CASCADE,
  amount            NUMERIC(10,2) NOT NULL,
  status            TEXT        NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'cancelled')),
  stripe_payout_id  TEXT,
  stripe_transfer_id TEXT,
  failure_reason    TEXT,
  requested_by      UUID        REFERENCES auth.users(id),
  requested_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at      TIMESTAMPTZ,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_brand_withdrawals_brand
  ON public.brand_withdrawals(brand_id);
CREATE INDEX IF NOT EXISTS idx_brand_withdrawals_status
  ON public.brand_withdrawals(status);


-- ============================================================
-- 3. brand_bank_accounts 表（品牌银行账户）
-- ============================================================
CREATE TABLE IF NOT EXISTS public.brand_bank_accounts (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  brand_id          UUID        NOT NULL REFERENCES public.brands(id) ON DELETE CASCADE,
  stripe_account_id TEXT        NOT NULL,
  bank_name         TEXT,
  last4             TEXT,
  status            TEXT        DEFAULT 'pending'
                    CHECK (status IN ('pending', 'verified', 'disabled')),
  is_default        BOOLEAN     DEFAULT true,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(brand_id, stripe_account_id)
);

CREATE INDEX IF NOT EXISTS idx_brand_bank_accounts_brand
  ON public.brand_bank_accounts(brand_id);


-- ============================================================
-- 4. RLS 策略
-- ============================================================

-- brand_withdrawals: 品牌管理员可读写
ALTER TABLE public.brand_withdrawals ENABLE ROW LEVEL SECURITY;

CREATE POLICY brand_withdrawals_select ON public.brand_withdrawals
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.brand_admins ba
      WHERE ba.brand_id = brand_withdrawals.brand_id
        AND ba.user_id = auth.uid()
    )
  );

CREATE POLICY brand_withdrawals_insert ON public.brand_withdrawals
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.brand_admins ba
      WHERE ba.brand_id = brand_withdrawals.brand_id
        AND ba.user_id = auth.uid()
    )
  );

-- brand_bank_accounts: 品牌管理员可读
ALTER TABLE public.brand_bank_accounts ENABLE ROW LEVEL SECURITY;

CREATE POLICY brand_bank_accounts_select ON public.brand_bank_accounts
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.brand_admins ba
      WHERE ba.brand_id = brand_bank_accounts.brand_id
        AND ba.user_id = auth.uid()
    )
  );


-- ============================================================
-- 5. 重建 get_merchant_transactions — 增加 brand_fee
-- ============================================================
DROP FUNCTION IF EXISTS public.get_merchant_transactions(UUID, DATE, DATE, INT, INT);

CREATE FUNCTION public.get_merchant_transactions(
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
  brand_fee_rate    DECIMAL,
  brand_fee         NUMERIC,
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
  -- 商家专属费率
  m_rate        DECIMAL;
  m_stripe_rate DECIMAL;
  m_stripe_flat DECIMAL;
  m_eff_from    DATE;
  m_eff_to      DATE;
  -- 最终生效费率
  v_rate        DECIMAL;
  v_stripe_rate DECIMAL;
  v_stripe_flat DECIMAL;
  -- 免费期
  v_commission_free_until DATE;
  v_use_merchant_rates    BOOLEAN := FALSE;
  -- 品牌佣金费率
  v_brand_rate  DECIMAL := 0;
BEGIN
  -- 读取全局费率
  SELECT
    commission_rate,
    COALESCE(stripe_processing_rate, 0.03),
    COALESCE(stripe_flat_fee, 0.30)
  INTO g_rate, g_stripe_rate, g_stripe_flat
  FROM platform_commission_config LIMIT 1;

  -- 读取商家专属费率及免费期
  SELECT
    commission_free_until::DATE,
    m.commission_rate,
    m.commission_stripe_rate,
    m.commission_stripe_flat_fee,
    m.commission_effective_from,
    m.commission_effective_to
  INTO
    v_commission_free_until,
    m_rate, m_stripe_rate, m_stripe_flat,
    m_eff_from, m_eff_to
  FROM public.merchants m WHERE m.id = p_merchant_id;

  -- 读取品牌佣金费率
  SELECT COALESCE(b.commission_rate, 0)
  INTO v_brand_rate
  FROM public.merchants m
  LEFT JOIN public.brands b ON b.id = m.brand_id
  WHERE m.id = p_merchant_id;

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
    oi.order_id,
    oi.id AS order_item_id,
    d.title::TEXT,
    COALESCE(d.validity_type, 'fixed_date')::TEXT,
    oi.unit_price,
    -- 平台抽成费率
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
    -- 品牌佣金费率
    v_brand_rate AS brand_fee_rate,
    -- 品牌佣金金额
    ROUND(oi.unit_price * v_brand_rate, 2) AS brand_fee,
    -- Stripe 手续费
    CASE
      WHEN v_commission_free_until IS NOT NULL
           AND oi.created_at::DATE <= v_commission_free_until THEN 0::NUMERIC
      ELSE ROUND(oi.unit_price * v_stripe_rate + v_stripe_flat, 2)
    END AS stripe_fee,
    -- 商家实收（扣除平台费、品牌费、Stripe费）
    CASE
      WHEN v_commission_free_until IS NOT NULL
           AND oi.created_at::DATE <= v_commission_free_until
        THEN ROUND(oi.unit_price - oi.unit_price * v_brand_rate, 2)
      ELSE ROUND(
        oi.unit_price
        - oi.unit_price * v_rate
        - oi.unit_price * v_brand_rate
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

GRANT EXECUTE ON FUNCTION public.get_merchant_transactions(UUID, DATE, DATE, INT, INT)
  TO authenticated, service_role;


-- ============================================================
-- 6. 重建 get_merchant_earnings_summary — 增加 brand_fee 扣除
-- ============================================================
DROP FUNCTION IF EXISTS public.get_merchant_earnings_summary(UUID, DATE);

CREATE FUNCTION public.get_merchant_earnings_summary(
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
  v_brand_rate  DECIMAL := 0;
BEGIN
  -- 读取全局费率
  SELECT
    commission_rate,
    COALESCE(stripe_processing_rate, 0.03),
    COALESCE(stripe_flat_fee, 0.30)
  INTO g_rate, g_stripe_rate, g_stripe_flat
  FROM platform_commission_config LIMIT 1;

  -- 读取商家专属费率及免费期
  SELECT
    commission_free_until::DATE,
    m.commission_rate,
    m.commission_stripe_rate,
    m.commission_stripe_flat_fee,
    m.commission_effective_from,
    m.commission_effective_to
  INTO
    v_commission_free_until,
    m_rate, m_stripe_rate, m_stripe_flat,
    m_eff_from, m_eff_to
  FROM public.merchants m WHERE m.id = p_merchant_id;

  -- 读取品牌佣金费率
  SELECT COALESCE(b.commission_rate, 0)
  INTO v_brand_rate
  FROM public.merchants m
  LEFT JOIN public.brands b ON b.id = m.brand_id
  WHERE m.id = p_merchant_id;

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
    -- pending_settlement：已核销不足7天，扣除平台抽成+品牌佣金+Stripe后的实收
    COALESCE((
      SELECT SUM(
        CASE
          WHEN v_commission_free_until IS NOT NULL
               AND oi.created_at::DATE <= v_commission_free_until
            THEN oi.unit_price - oi.unit_price * v_brand_rate
          ELSE oi.unit_price
             - oi.unit_price * v_rate
             - oi.unit_price * v_brand_rate
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

GRANT EXECUTE ON FUNCTION public.get_merchant_earnings_summary(UUID, DATE)
  TO authenticated, service_role;


-- ============================================================
-- 7. 重建 get_merchant_report_data — 增加 brand_fee
-- ============================================================
DROP FUNCTION IF EXISTS public.get_merchant_report_data(UUID, DATE, DATE);

CREATE FUNCTION public.get_merchant_report_data(
  p_merchant_id UUID,
  p_date_from   DATE,
  p_date_to     DATE
)
RETURNS TABLE (
  report_date  DATE,
  order_count  BIGINT,
  gross_amount NUMERIC,
  platform_fee NUMERIC,
  brand_fee    NUMERIC,
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
  v_brand_rate  DECIMAL := 0;
BEGIN
  -- 读取全局费率
  SELECT
    commission_rate,
    COALESCE(stripe_processing_rate, 0.03),
    COALESCE(stripe_flat_fee, 0.30)
  INTO g_rate, g_stripe_rate, g_stripe_flat
  FROM platform_commission_config LIMIT 1;

  -- 读取商家专属费率及免费期
  SELECT
    commission_free_until::DATE,
    m.commission_rate,
    m.commission_stripe_rate,
    m.commission_stripe_flat_fee,
    m.commission_effective_from,
    m.commission_effective_to
  INTO
    v_commission_free_until,
    m_rate, m_stripe_rate, m_stripe_flat,
    m_eff_from, m_eff_to
  FROM public.merchants m WHERE m.id = p_merchant_id;

  -- 读取品牌佣金费率
  SELECT COALESCE(b.commission_rate, 0)
  INTO v_brand_rate
  FROM public.merchants m
  LEFT JOIN public.brands b ON b.id = m.brand_id
  WHERE m.id = p_merchant_id;

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
    -- 平台抽成
    COALESCE(ROUND(SUM(
      CASE
        WHEN v_commission_free_until IS NOT NULL
             AND oi.created_at::DATE <= v_commission_free_until THEN 0
        ELSE oi.unit_price * v_rate
      END
    ), 2), 0) AS platform_fee,
    -- 品牌佣金
    COALESCE(ROUND(SUM(oi.unit_price * v_brand_rate), 2), 0) AS brand_fee,
    -- Stripe 手续费
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
             AND oi.created_at::DATE <= v_commission_free_until
          THEN oi.unit_price - oi.unit_price * v_brand_rate
        ELSE oi.unit_price
          - oi.unit_price * v_rate
          - oi.unit_price * v_brand_rate
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

GRANT EXECUTE ON FUNCTION public.get_merchant_report_data(UUID, DATE, DATE)
  TO authenticated, service_role;


-- ============================================================
-- 8. 新增 get_brand_earnings_summary — 品牌维度收入概览
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_brand_earnings_summary(
  p_brand_id    UUID,
  p_month_start DATE
)
RETURNS TABLE (
  total_brand_revenue NUMERIC,
  pending_settlement  NUMERIC,
  settled_amount      NUMERIC,
  refunded_amount     NUMERIC
)
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_brand_rate DECIMAL := 0;
BEGIN
  -- 读取品牌佣金费率
  SELECT COALESCE(b.commission_rate, 0)
  INTO v_brand_rate
  FROM public.brands b
  WHERE b.id = p_brand_id;

  RETURN QUERY SELECT
    -- 品牌本月佣金总收入（已核销、非退款的 order_items 中，品牌佣金部分）
    COALESCE((
      SELECT ROUND(SUM(oi.unit_price * v_brand_rate), 2)
      FROM public.order_items oi
      JOIN public.deals d ON d.id = oi.deal_id
      JOIN public.merchants m ON m.id = COALESCE(oi.redeemed_merchant_id, d.merchant_id)
      WHERE m.brand_id = p_brand_id
        AND oi.customer_status::TEXT NOT IN ('refund_success', 'refund_pending')
        AND oi.created_at::DATE >= p_month_start
        AND oi.created_at::DATE < (p_month_start + INTERVAL '1 month')::DATE
    ), 0),
    -- 待结算：已核销不足7天的品牌佣金
    COALESCE((
      SELECT ROUND(SUM(oi.unit_price * v_brand_rate), 2)
      FROM public.order_items oi
      JOIN public.deals d ON d.id = oi.deal_id
      JOIN public.merchants m ON m.id = COALESCE(oi.redeemed_merchant_id, d.merchant_id)
      WHERE m.brand_id = p_brand_id
        AND oi.customer_status::TEXT = 'used'
        AND oi.redeemed_at > NOW() - INTERVAL '7 days'
    ), 0),
    -- 已结算（品牌提现已完成的金额）
    COALESCE((
      SELECT SUM(bw.amount)
      FROM public.brand_withdrawals bw
      WHERE bw.brand_id = p_brand_id
        AND bw.status = 'completed'
        AND bw.completed_at >= p_month_start
        AND bw.completed_at < (p_month_start + INTERVAL '1 month')::TIMESTAMPTZ
    ), 0),
    -- 退款影响（品牌佣金需退回的部分）
    COALESCE((
      SELECT ROUND(SUM(oi.unit_price * v_brand_rate), 2)
      FROM public.order_items oi
      JOIN public.deals d ON d.id = oi.deal_id
      JOIN public.merchants m ON m.id = COALESCE(oi.redeemed_merchant_id, d.merchant_id)
      WHERE m.brand_id = p_brand_id
        AND oi.customer_status::TEXT = 'refund_success'
        AND oi.created_at::DATE >= p_month_start
        AND oi.created_at::DATE < (p_month_start + INTERVAL '1 month')::DATE
    ), 0);
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_brand_earnings_summary(UUID, DATE)
  TO authenticated, service_role;


-- ============================================================
-- 9. 新增 get_brand_transactions — 品牌维度交易明细
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_brand_transactions(
  p_brand_id  UUID,
  p_date_from DATE DEFAULT NULL,
  p_date_to   DATE DEFAULT NULL,
  p_page      INT  DEFAULT 1,
  p_per_page  INT  DEFAULT 20
)
RETURNS TABLE (
  order_id       UUID,
  order_item_id  UUID,
  deal_title     TEXT,
  store_name     TEXT,
  amount         NUMERIC,
  brand_fee_rate DECIMAL,
  brand_fee      NUMERIC,
  status         TEXT,
  created_at     TIMESTAMPTZ,
  total_count    BIGINT
)
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_brand_rate DECIMAL := 0;
BEGIN
  SELECT COALESCE(b.commission_rate, 0)
  INTO v_brand_rate
  FROM public.brands b
  WHERE b.id = p_brand_id;

  RETURN QUERY
  SELECT
    oi.order_id,
    oi.id AS order_item_id,
    d.title::TEXT,
    m.name::TEXT AS store_name,
    oi.unit_price AS amount,
    v_brand_rate AS brand_fee_rate,
    ROUND(oi.unit_price * v_brand_rate, 2) AS brand_fee,
    oi.customer_status::TEXT AS status,
    oi.created_at,
    COUNT(*) OVER () AS total_count
  FROM public.order_items oi
  JOIN public.deals d ON d.id = oi.deal_id
  JOIN public.merchants m ON m.id = COALESCE(oi.redeemed_merchant_id, d.merchant_id)
  WHERE m.brand_id = p_brand_id
    AND oi.customer_status::TEXT NOT IN ('refund_success', 'refund_pending')
    AND (p_date_from IS NULL OR oi.created_at::DATE >= p_date_from)
    AND (p_date_to   IS NULL OR oi.created_at::DATE <= p_date_to)
  ORDER BY oi.created_at DESC
  OFFSET (p_page - 1) * p_per_page LIMIT p_per_page;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_brand_transactions(UUID, DATE, DATE, INT, INT)
  TO authenticated, service_role;


-- ============================================================
-- 10. 新增 get_brand_balance — 品牌可提现余额
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_brand_balance(
  p_brand_id UUID
)
RETURNS TABLE (
  available_balance  NUMERIC,
  pending_settlement NUMERIC,
  total_withdrawn    NUMERIC
)
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_brand_rate       DECIMAL := 0;
  v_total_earned     NUMERIC := 0;
  v_pending          NUMERIC := 0;
  v_withdrawn        NUMERIC := 0;
  v_refund_deduction NUMERIC := 0;
BEGIN
  -- 读取品牌佣金费率
  SELECT COALESCE(b.commission_rate, 0)
  INTO v_brand_rate
  FROM public.brands b
  WHERE b.id = p_brand_id;

  -- 已结算的品牌佣金总额（核销 > 7 天）
  SELECT COALESCE(ROUND(SUM(oi.unit_price * v_brand_rate), 2), 0)
  INTO v_total_earned
  FROM public.order_items oi
  JOIN public.deals d ON d.id = oi.deal_id
  JOIN public.merchants m ON m.id = COALESCE(oi.redeemed_merchant_id, d.merchant_id)
  WHERE m.brand_id = p_brand_id
    AND oi.customer_status::TEXT = 'used'
    AND oi.redeemed_at IS NOT NULL
    AND oi.redeemed_at <= NOW() - INTERVAL '7 days';

  -- 待结算（核销不足7天）
  SELECT COALESCE(ROUND(SUM(oi.unit_price * v_brand_rate), 2), 0)
  INTO v_pending
  FROM public.order_items oi
  JOIN public.deals d ON d.id = oi.deal_id
  JOIN public.merchants m ON m.id = COALESCE(oi.redeemed_merchant_id, d.merchant_id)
  WHERE m.brand_id = p_brand_id
    AND oi.customer_status::TEXT = 'used'
    AND oi.redeemed_at IS NOT NULL
    AND oi.redeemed_at > NOW() - INTERVAL '7 days';

  -- 退款扣除
  SELECT COALESCE(ROUND(SUM(oi.unit_price * v_brand_rate), 2), 0)
  INTO v_refund_deduction
  FROM public.order_items oi
  JOIN public.deals d ON d.id = oi.deal_id
  JOIN public.merchants m ON m.id = COALESCE(oi.redeemed_merchant_id, d.merchant_id)
  WHERE m.brand_id = p_brand_id
    AND oi.customer_status::TEXT = 'refund_success';

  -- 已提现总额
  SELECT COALESCE(SUM(bw.amount), 0)
  INTO v_withdrawn
  FROM public.brand_withdrawals bw
  WHERE bw.brand_id = p_brand_id
    AND bw.status IN ('completed', 'processing', 'pending');

  RETURN QUERY SELECT
    GREATEST(v_total_earned - v_refund_deduction - v_withdrawn, 0) AS available_balance,
    v_pending AS pending_settlement,
    v_withdrawn AS total_withdrawn;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_brand_balance(UUID)
  TO authenticated, service_role;
