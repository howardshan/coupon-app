-- =============================================================
-- Migration: 6.订单管理 — 商家端订单查询支撑
-- 创建时间: 2026-03-03
-- 说明:
--   1. orders 表补充展示用 order_number 字段
--   2. 创建商家专用订单视图 merchant_order_view
--   3. 创建分页查询函数 get_merchant_orders
--   4. 补充 RLS：商家只能查看自己 deals 的订单
--   5. 补充索引：deal_id + created_at 复合索引
-- =============================================================

-- -------------------------------------------------------------
-- 1. orders 表：新增 order_number 展示字段
--    格式：DJ-XXXXXXXX（8位大写hex，基于 id 前8字符）
--    用于 UI 展示，人类可读订单号
-- -------------------------------------------------------------
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS order_number TEXT
  GENERATED ALWAYS AS ('DJ-' || UPPER(SUBSTRING(id::text, 1, 8))) STORED;

-- order_number 唯一索引（用于按订单号搜索）
CREATE UNIQUE INDEX IF NOT EXISTS idx_orders_order_number
  ON public.orders(order_number);

-- -------------------------------------------------------------
-- 2. 复合索引：商家订单列表主查询（按 deal_id + created_at 倒序）
-- -------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_orders_deal_id_created_at
  ON public.orders(deal_id, created_at DESC);

-- -------------------------------------------------------------
-- 3. RLS：商家可查看自己 deals 的订单
--    逻辑：order.deal_id → deals.merchant_id → merchants.user_id = auth.uid()
-- -------------------------------------------------------------
DO $$
BEGIN
  -- 检查策略是否已存在，避免重复创建报错
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'orders'
      AND policyname = 'orders_merchant_select'
  ) THEN
    CREATE POLICY "orders_merchant_select"
      ON public.orders
      FOR SELECT
      USING (
        deal_id IN (
          SELECT d.id
          FROM public.deals d
          WHERE d.merchant_id IN (
            SELECT m.id
            FROM public.merchants m
            WHERE m.user_id = auth.uid()
          )
        )
      );
  END IF;
END $$;

-- -------------------------------------------------------------
-- 4. 商家专用订单视图 merchant_order_view
--    关联 deals / users / coupons，提供商家订单列表所需所有字段
--    注意：user name 脱敏，只保留 first name
-- -------------------------------------------------------------
CREATE OR REPLACE VIEW public.merchant_order_view AS
SELECT
  o.id,
  o.order_number,
  o.deal_id,
  o.user_id,
  o.quantity,
  o.unit_price,
  o.total_amount,
  o.status,
  o.payment_intent_id,
  o.stripe_charge_id,
  o.refund_reason,
  o.created_at,
  o.updated_at,
  o.refund_requested_at,
  o.refunded_at,
  -- deal 信息
  d.title                AS deal_title,
  d.merchant_id,
  d.original_price       AS deal_original_price,
  d.discount_price       AS deal_discount_price,
  -- 用户名脱敏：只取 first name（空格前部分）
  SPLIT_PART(COALESCE(u.full_name, 'Customer'), ' ', 1) AS user_display_name,
  -- coupon 信息（LEFT JOIN，未核销时为 NULL）
  c.id                   AS coupon_id,
  c.qr_code              AS coupon_code,
  c.status               AS coupon_status,
  c.used_at              AS coupon_used_at,
  c.redeemed_at          AS coupon_redeemed_at,
  c.expires_at           AS coupon_expires_at
FROM public.orders o
JOIN public.deals d ON d.id = o.deal_id
JOIN public.users u ON u.id = o.user_id
LEFT JOIN public.coupons c ON c.order_id = o.id;

-- 给视图赋予安全屏障，防止 RLS 被绕过
ALTER VIEW public.merchant_order_view OWNER TO postgres;

-- -------------------------------------------------------------
-- 5. 函数 get_merchant_orders
--    供 Edge Function 调用（使用 service_role），返回分页订单列表
--    参数:
--      p_merchant_id   UUID   — 商家 ID（必填）
--      p_status        TEXT   — 状态筛选（可选，NULL=全部）
--      p_date_from     DATE   — 开始日期（可选）
--      p_date_to       DATE   — 结束日期（可选）
--      p_deal_id       UUID   — 指定 deal（可选）
--      p_page          INT    — 页码（从1开始，默认1）
--      p_per_page      INT    — 每页条数（默认20，最大100）
-- -------------------------------------------------------------
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
  -- 参数边界校验
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
      c.redeemed_at                                                      AS coupon_redeemed_at,
      o.created_at,
      o.refund_requested_at,
      o.refunded_at
    FROM public.orders o
    JOIN public.deals d ON d.id = o.deal_id
    JOIN public.users u ON u.id = o.user_id
    LEFT JOIN public.coupons c ON c.order_id = o.id
    WHERE d.merchant_id = p_merchant_id
      -- 状态筛选（NULL 表示不筛选）
      AND (p_status IS NULL OR o.status::TEXT = p_status)
      -- 日期范围筛选（DATE 比较，忽略时间部分）
      AND (p_date_from IS NULL OR o.created_at::DATE >= p_date_from)
      AND (p_date_to   IS NULL OR o.created_at::DATE <= p_date_to)
      -- 指定 deal 筛选
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

-- 赋予 service_role 执行权限（Edge Function 使用 service_role 调用）
GRANT EXECUTE ON FUNCTION public.get_merchant_orders TO service_role;
-- 赋予 authenticated 用户执行权限（直接从客户端调用时使用）
GRANT EXECUTE ON FUNCTION public.get_merchant_orders TO authenticated;

-- -------------------------------------------------------------
-- 6. payments 表：补充商家可读策略
--    商家需要查看自己 deals 的订单支付记录（用于订单详情展示）
-- -------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'payments'
      AND policyname = 'payments_merchant_select'
  ) THEN
    CREATE POLICY "payments_merchant_select"
      ON public.payments
      FOR SELECT
      USING (
        order_id IN (
          SELECT o.id
          FROM public.orders o
          JOIN public.deals d ON d.id = o.deal_id
          WHERE d.merchant_id IN (
            SELECT m.id FROM public.merchants m WHERE m.user_id = auth.uid()
          )
        )
      );
  END IF;
END $$;
