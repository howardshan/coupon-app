-- ============================================================
-- 自动暂停：目标 deal 已过期或下架时，pause 对应的广告 campaign
-- ============================================================

-- ============================================================
-- Step 1: 函数 — 扫描并 pause 失效 deal 的 campaign
-- ============================================================
CREATE OR REPLACE FUNCTION pause_campaigns_for_expired_deals()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_campaign record;
  v_affected int := 0;
BEGIN
  FOR v_campaign IN
    SELECT ac.id, ac.merchant_id
    FROM ad_campaigns ac
    JOIN deals d ON d.id = ac.target_id
    WHERE ac.target_type = 'deal'
      AND ac.status IN ('active', 'exhausted')
      AND (
        d.is_active = false
        OR (d.expires_at IS NOT NULL AND d.expires_at < now())
      )
  LOOP
    UPDATE ad_campaigns
    SET status = 'paused', updated_at = now()
    WHERE id = v_campaign.id;

    INSERT INTO ad_campaign_logs (campaign_id, merchant_id, actor_type, event_type, detail)
    VALUES (
      v_campaign.id,
      v_campaign.merchant_id,
      'system',
      'paused',
      jsonb_build_object('reason', 'deal_expired_or_inactive')
    );

    v_affected := v_affected + 1;
  END LOOP;

  RETURN v_affected;
END;
$$;

REVOKE EXECUTE ON FUNCTION pause_campaigns_for_expired_deals() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION pause_campaigns_for_expired_deals() TO service_role;

-- ============================================================
-- Step 2: pg_cron — 每小时整点执行一次
-- ============================================================
SELECT cron.schedule(
  'pause-campaigns-expired-deals',
  '5 * * * *',
  $$ SELECT pause_campaigns_for_expired_deals(); $$
);
