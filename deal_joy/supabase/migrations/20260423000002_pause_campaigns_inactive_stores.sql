-- ============================================================
-- 自动暂停：目标 store 非 approved 状态时，pause 对应的广告 campaign
-- ============================================================

CREATE OR REPLACE FUNCTION pause_campaigns_for_inactive_stores()
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
    JOIN merchants m ON m.id = ac.target_id
    WHERE ac.target_type = 'store'
      AND ac.status IN ('active', 'exhausted')
      AND m.status != 'approved'
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
      jsonb_build_object('reason', 'store_not_approved')
    );

    v_affected := v_affected + 1;
  END LOOP;

  RETURN v_affected;
END;
$$;

REVOKE EXECUTE ON FUNCTION pause_campaigns_for_inactive_stores() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION pause_campaigns_for_inactive_stores() TO service_role;

-- 每小时 xx:07 执行
SELECT cron.schedule(
  'pause-campaigns-inactive-stores',
  '7 * * * *',
  $$ SELECT pause_campaigns_for_inactive_stores(); $$
);
