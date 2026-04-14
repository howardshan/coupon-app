-- 重建 get_merchant_daily_stats
-- today_revenue 改为商家实际到账金额（net_amount）：
--   net = unit_price - platform_fee - brand_fee - stripe_fee
-- 公式与 get_merchant_transactions / get_merchant_earnings_summary 保持一致
-- 兼容商家专属费率、免费期、品牌佣金

DROP FUNCTION IF EXISTS public.get_merchant_daily_stats(uuid);

CREATE FUNCTION public.get_merchant_daily_stats(p_merchant_id uuid)
RETURNS TABLE (
  today_orders      bigint,
  today_redemptions bigint,
  today_revenue     numeric,
  pending_coupons   bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  g_rate        decimal;
  g_stripe_rate decimal;
  g_stripe_flat decimal;
  m_rate        decimal;
  m_stripe_rate decimal;
  m_stripe_flat decimal;
  m_eff_from    date;
  m_eff_to      date;
  v_rate        decimal;
  v_stripe_rate decimal;
  v_stripe_flat decimal;
  v_commission_free_until date;
  v_use_merchant_rates    boolean := false;
  v_brand_rate  decimal := 0;
BEGIN
  -- 全局费率
  SELECT
    commission_rate,
    COALESCE(stripe_processing_rate, 0.03),
    COALESCE(stripe_flat_fee, 0.30)
  INTO g_rate, g_stripe_rate, g_stripe_flat
  FROM platform_commission_config
  LIMIT 1;

  -- 商家专属费率 + 免费期
  SELECT
    commission_free_until::date,
    m.commission_rate,
    m.commission_stripe_rate,
    m.commission_stripe_flat_fee,
    m.commission_effective_from,
    m.commission_effective_to
  INTO
    v_commission_free_until,
    m_rate, m_stripe_rate, m_stripe_flat,
    m_eff_from, m_eff_to
  FROM public.merchants m
  WHERE m.id = p_merchant_id;

  -- 品牌佣金费率
  SELECT COALESCE(b.commission_rate, 0)
  INTO v_brand_rate
  FROM public.merchants m
  LEFT JOIN public.brands b ON b.id = m.brand_id
  WHERE m.id = p_merchant_id;

  -- 判断商家专属费率生效期
  IF (m_rate IS NOT NULL OR m_stripe_rate IS NOT NULL OR m_stripe_flat IS NOT NULL) THEN
    IF (m_eff_from IS NULL AND m_eff_to IS NULL) THEN
      v_use_merchant_rates := true;
    ELSIF (m_eff_from IS NOT NULL AND m_eff_to IS NOT NULL) THEN
      v_use_merchant_rates := (CURRENT_DATE >= m_eff_from AND CURRENT_DATE <= m_eff_to);
    ELSIF (m_eff_from IS NOT NULL) THEN
      v_use_merchant_rates := (CURRENT_DATE >= m_eff_from);
    ELSIF (m_eff_to IS NOT NULL) THEN
      v_use_merchant_rates := (CURRENT_DATE <= m_eff_to);
    END IF;
  END IF;

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
    -- today_orders：今日新下单的 order_items 数
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

    -- today_redemptions：今日核销的券数（沿用 coupons.redeemed_at）
    (
      SELECT COUNT(*)
      FROM coupons c
      LEFT JOIN order_items oi ON oi.id = c.order_item_id
      WHERE c.status = 'used'
        AND c.redeemed_at IS NOT NULL
        AND c.redeemed_at >= CURRENT_DATE
        AND c.redeemed_at <  CURRENT_DATE + INTERVAL '1 day'
        AND (
          (oi.id IS NULL AND (c.merchant_id = p_merchant_id OR c.purchased_merchant_id = p_merchant_id))
          OR (
            oi.id IS NOT NULL
            AND (
              oi.purchased_merchant_id = p_merchant_id
              OR p_merchant_id = ANY (oi.applicable_store_ids)
            )
          )
        )
    )::bigint AS today_redemptions,

    -- today_revenue：今日核销的 order_items 的净金额合计
    --   net = unit_price - platform_fee - brand_fee - stripe_fee
    --   免费期内只扣 brand_fee
    (
      SELECT COALESCE(SUM(
        CASE
          WHEN v_commission_free_until IS NOT NULL
               AND oi.created_at::date <= v_commission_free_until
            THEN oi.unit_price - oi.unit_price * v_brand_rate
          ELSE oi.unit_price
             - oi.unit_price * v_rate
             - oi.unit_price * v_brand_rate
             - (oi.unit_price * v_stripe_rate + v_stripe_flat)
        END
      ), 0)
      FROM order_items oi
      WHERE oi.customer_status = 'used'
        AND oi.redeemed_at IS NOT NULL
        AND oi.redeemed_at >= CURRENT_DATE
        AND oi.redeemed_at <  CURRENT_DATE + INTERVAL '1 day'
        AND (
          oi.redeemed_merchant_id = p_merchant_id
          OR (
            oi.redeemed_merchant_id IS NULL
            AND (
              oi.purchased_merchant_id = p_merchant_id
              OR p_merchant_id = ANY(oi.applicable_store_ids)
            )
          )
        )
    ) AS today_revenue,

    -- pending_coupons
    (
      SELECT COUNT(*)
      FROM order_items oi
      WHERE (
              oi.purchased_merchant_id = p_merchant_id
              OR p_merchant_id = ANY(oi.applicable_store_ids)
            )
        AND oi.customer_status = 'unused'
    )::bigint AS pending_coupons;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.get_merchant_daily_stats(uuid)
  TO authenticated, service_role;
