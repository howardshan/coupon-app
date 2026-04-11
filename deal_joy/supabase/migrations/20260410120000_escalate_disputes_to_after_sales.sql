-- =============================================================
-- 争议退款（pending_merchant）在「核销 + 24h」后自动升级为售后单
-- 仅处理 status = pending_merchant（不含 pending_admin）
-- 定时：pg_cron 调 Edge escalate-disputes-to-after-sales（x-cron-secret）
-- =============================================================

-- 1) refund_requests.metadata：记录升级后的 after_sales_request_id 等
ALTER TABLE public.refund_requests
  ADD COLUMN IF NOT EXISTS metadata jsonb NOT NULL DEFAULT '{}'::jsonb;

COMMENT ON COLUMN public.refund_requests.metadata IS
  '扩展字段：自动升级售后时写入 after_sales_request_id、取消原因等';

-- 2) 核心业务函数（SECURITY DEFINER，供 service_role RPC）
CREATE OR REPLACE FUNCTION public.escalate_pending_disputes_to_after_sales(p_limit int DEFAULT 100)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_created int := 0;
  v_cancelled_existing_as int := 0;
  v_cancelled_expired_window int := 0;
  rec record;
  v_reason_detail text;
  v_expires_at timestamptz;
  v_used_at timestamptz;
  v_as_id uuid;
  v_timeline jsonb;
  v_store_id uuid;
  v_merchant_id uuid;
  v_coupon_id uuid;
BEGIN
  IF p_limit IS NULL OR p_limit < 1 THEN
    p_limit := 100;
  END IF;
  IF p_limit > 500 THEN
    p_limit := 500;
  END IF;

  FOR rec IN
    SELECT
      rr.id AS rr_id,
      rr.order_id,
      rr.order_item_id,
      rr.user_id,
      rr.refund_amount,
      COALESCE(NULLIF(btrim(COALESCE(rr.reason, rr.user_reason, '')), ''), 'Dispute reason not recorded') AS base_reason,
      oi.redeemed_at,
      c.id AS coupon_id,
      c.merchant_id AS coupon_merchant_id,
      c.redeemed_at_merchant_id,
      COALESCE(c.used_at, oi.redeemed_at) AS coupon_used_at
    FROM public.refund_requests rr
    INNER JOIN public.order_items oi ON oi.id = rr.order_item_id
    INNER JOIN LATERAL (
      SELECT c0.*
      FROM public.coupons c0
      WHERE (oi.coupon_id IS NOT NULL AND c0.id = oi.coupon_id)
         OR (c0.order_item_id = oi.id)
      ORDER BY
        CASE WHEN oi.coupon_id IS NOT NULL AND c0.id = oi.coupon_id THEN 0 ELSE 1 END,
        c0.created_at NULLS LAST
      LIMIT 1
    ) c ON true
    WHERE rr.status = 'pending_merchant'
      AND rr.order_item_id IS NOT NULL
      AND oi.redeemed_at IS NOT NULL
      AND oi.redeemed_at + interval '24 hours' <= now()
    ORDER BY rr.created_at ASC
    LIMIT p_limit
  LOOP
    v_coupon_id := rec.coupon_id;
    IF v_coupon_id IS NULL THEN
      CONTINUE;
    END IF;

    -- 幂等：已从本争议生成过售后
    IF EXISTS (
      SELECT 1 FROM public.after_sales_requests asr
      WHERE asr.metadata->>'source_refund_request_id' = rec.rr_id::text
    ) THEN
      CONTINUE;
    END IF;

    -- 已有活跃售后：只取消争议，合并为一条主诉求线
    IF EXISTS (
      SELECT 1 FROM public.after_sales_requests asr
      WHERE asr.coupon_id = v_coupon_id
        AND asr.status NOT IN ('refunded', 'closed', 'platform_rejected')
    ) THEN
      UPDATE public.refund_requests
      SET
        status = 'cancelled',
        updated_at = now(),
        metadata = COALESCE(metadata, '{}'::jsonb) || jsonb_build_object(
          'cancel_reason', 'superseded_by_existing_after_sales',
          'cancelled_at', to_jsonb(now())
        )
      WHERE id = rec.rr_id AND status = 'pending_merchant';
      v_cancelled_existing_as := v_cancelled_existing_as + 1;
      CONTINUE;
    END IF;

    v_used_at := rec.coupon_used_at;
    v_expires_at := v_used_at + interval '7 days';

    -- 已超过 7 天售后窗：不再建售后，关闭争议
    IF v_expires_at < now() THEN
      UPDATE public.refund_requests
      SET
        status = 'cancelled',
        updated_at = now(),
        metadata = COALESCE(metadata, '{}'::jsonb) || jsonb_build_object(
          'cancel_reason', 'after_sales_window_expired',
          'cancelled_at', to_jsonb(now())
        )
      WHERE id = rec.rr_id AND status = 'pending_merchant';
      v_cancelled_expired_window := v_cancelled_expired_window + 1;
      CONTINUE;
    END IF;

    v_merchant_id := rec.coupon_merchant_id;
    v_store_id := COALESCE(rec.redeemed_at_merchant_id, rec.coupon_merchant_id);
    IF v_merchant_id IS NULL OR v_store_id IS NULL THEN
      CONTINUE;
    END IF;

    v_reason_detail := rec.base_reason;
    IF length(v_reason_detail) < 20 THEN
      v_reason_detail := rpad(v_reason_detail, 20, '.') || ' (auto-escalated)';
    END IF;
    IF length(v_reason_detail) > 500 THEN
      v_reason_detail := left(v_reason_detail, 500);
    END IF;

    v_timeline := jsonb_build_array(
      jsonb_build_object(
        'at', to_jsonb(now()),
        'status', 'pending',
        'actor', 'system',
        'note', 'auto_escalated_from_dispute',
        'meta', jsonb_build_object(
          'source_refund_request_id', rec.rr_id::text
        )
      )
    );

    INSERT INTO public.after_sales_requests (
      order_id,
      coupon_id,
      user_id,
      merchant_id,
      store_id,
      status,
      reason_code,
      reason_detail,
      refund_amount,
      user_attachments,
      expires_at,
      timeline,
      metadata
    ) VALUES (
      rec.order_id,
      v_coupon_id,
      rec.user_id,
      v_merchant_id,
      v_store_id,
      'pending',
      'other'::public.after_sale_reason,
      v_reason_detail,
      rec.refund_amount,
      '{}'::text[],
      v_expires_at,
      v_timeline,
      jsonb_build_object(
        'source', 'auto_escalate_dispute',
        'source_refund_request_id', rec.rr_id::text
      )
    )
    RETURNING id INTO v_as_id;

    UPDATE public.refund_requests
    SET
      status = 'cancelled',
      updated_at = now(),
      metadata = COALESCE(metadata, '{}'::jsonb) || jsonb_build_object(
        'after_sales_request_id', v_as_id,
        'escalated_at', to_jsonb(now())
      )
    WHERE id = rec.rr_id AND status = 'pending_merchant';

    v_created := v_created + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'created_after_sales', v_created,
    'cancelled_existing_after_sales', v_cancelled_existing_as,
    'cancelled_after_sales_window_expired', v_cancelled_expired_window
  );
END;
$$;

REVOKE ALL ON FUNCTION public.escalate_pending_disputes_to_after_sales(int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.escalate_pending_disputes_to_after_sales(int) TO service_role;

COMMENT ON FUNCTION public.escalate_pending_disputes_to_after_sales(int) IS
  'Cron：将 pending_merchant 且核销满 24h 的争议升级为 after_sales_requests，并取消原 refund_requests';

-- 3) pg_cron：每小时第 20 分触发（与 auto-refund 整点错开）
SELECT cron.unschedule('escalate-disputes-to-after-sales-hourly')
WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'escalate-disputes-to-after-sales-hourly'
);

SELECT cron.schedule(
  'escalate-disputes-to-after-sales-hourly',
  '20 * * * *',
  $$
  SELECT net.http_post(
    url := (
      SELECT decrypted_secret
      FROM vault.decrypted_secrets
      WHERE name = 'supabase_url'
      LIMIT 1
    ) || '/functions/v1/escalate-disputes-to-after-sales',
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
