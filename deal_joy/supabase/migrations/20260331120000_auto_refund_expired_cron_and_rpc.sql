-- =============================================================
-- 1) pg_cron：每小时调用 auto-refund-expired，并携带 x-cron-secret
--    修复：仅 anon 调用导致 Edge Function 内 CRON_SECRET 校验 401、永不执行业务逻辑
--
-- 2) get_expired_order_items：返回订单 Stripe 字段与 tax_amount 等，
--    与 auto-refund-expired Edge Function 期望结构一致，避免 RPC 成功时缺字段全走 store credit
--
-- 依赖（与其它 cron 一致）：
--   - vault.decrypted_secrets：supabase_url、cron_secret
--   - Edge Function Secrets：CRON_SECRET 必须与 vault.cron_secret 值相同
-- =============================================================

-- ─────────────────────────────────────────────────────────────
-- Part A：扩展 RPC（改返回列须 DROP 再 CREATE）
-- ─────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS public.get_expired_order_items(int);

CREATE FUNCTION public.get_expired_order_items(
  p_limit int DEFAULT 50
)
RETURNS TABLE (
  id                   uuid,
  order_id             uuid,
  user_id              uuid,
  unit_price           numeric,
  service_fee          numeric,
  tax_amount           numeric,
  coupon_id            uuid,
  expires_at           timestamptz,
  stripe_charge_id     text,
  payment_intent_id    text,
  customer_status      text,
  deal_id              uuid
)
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT
    oi.id,
    oi.order_id,
    o.user_id,
    oi.unit_price,
    oi.service_fee,
    COALESCE(oi.tax_amount, 0) AS tax_amount,
    c.id                      AS coupon_id,
    c.expires_at,
    o.stripe_charge_id,
    o.payment_intent_id,
    oi.customer_status::text,
    oi.deal_id
  FROM public.order_items oi
  JOIN public.coupons c ON c.order_item_id = oi.id
  JOIN public.orders  o ON o.id = oi.order_id
  WHERE oi.customer_status IN ('unused', 'gifted')
    AND c.expires_at < now()
  ORDER BY c.expires_at ASC
  LIMIT p_limit;
$$;

REVOKE ALL ON FUNCTION public.get_expired_order_items(int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_expired_order_items(int) TO service_role;

COMMENT ON FUNCTION public.get_expired_order_items(int) IS
  '供 auto-refund-expired：过期未用/转赠中券；含 Stripe 与税额供原路退款。';

-- ─────────────────────────────────────────────────────────────
-- Part B：每小时整点调用 auto-refund-expired（与函数注释建议一致）
-- ─────────────────────────────────────────────────────────────

SELECT cron.unschedule('auto-refund-expired-hourly')
WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'auto-refund-expired-hourly'
);

SELECT cron.schedule(
  'auto-refund-expired-hourly',
  '0 * * * *',
  $$
  SELECT net.http_post(
    url := (
      SELECT decrypted_secret
      FROM vault.decrypted_secrets
      WHERE name = 'supabase_url'
      LIMIT 1
    ) || '/functions/v1/auto-refund-expired',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (
        SELECT decrypted_secret
        FROM vault.decrypted_secrets
        WHERE name = 'cron_secret'
        LIMIT 1
      )
    ),
    body := '{}'::jsonb
  ) AS request_id;
  $$
);

-- =============================================================
-- 手动清理（若 Dashboard 曾创建「无 x-cron-secret」的重复任务，会导致仍 401）：
--
--   SELECT jobid, jobname, command FROM cron.job
--   WHERE command ILIKE '%auto-refund-expired%';
--
--   SELECT cron.unschedule('<jobname>');
-- =============================================================
