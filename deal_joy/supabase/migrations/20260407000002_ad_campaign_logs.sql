-- ============================================================
-- Promotions 重构：Campaign 操作日志 + Splash 开关联动
-- ============================================================

-- ============================================================
-- Step 1: ad_campaigns 新增 auto_paused_by 字段（R2）
-- 用于区分"Admin 手动暂停"和"splash 开关自动暂停"
-- ============================================================
ALTER TABLE ad_campaigns ADD COLUMN IF NOT EXISTS auto_paused_by text;

-- ============================================================
-- Step 2: 创建 ad_campaign_logs 表
-- 记录 campaign 操作事件（不含高频 impression/skip）
-- ============================================================
CREATE TABLE IF NOT EXISTS ad_campaign_logs (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id   uuid REFERENCES ad_campaigns(id) ON DELETE CASCADE,  -- R18: 允许 NULL（充值等账户级事件）
  merchant_id   uuid NOT NULL REFERENCES merchants(id),
  actor_type    text NOT NULL CHECK (actor_type IN ('merchant','admin','system')),
  actor_user_id uuid REFERENCES users(id),
  event_type    text NOT NULL CHECK (event_type IN (
    'created','updated','paused','resumed','deleted',
    'admin_paused','admin_resumed',
    'exhausted','budget_recharged',
    'click_charged',
    'splash_auto_paused','splash_auto_resumed'
  )),
  detail        jsonb,
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_campaign_logs_campaign
  ON ad_campaign_logs(campaign_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_campaign_logs_merchant
  ON ad_campaign_logs(merchant_id, created_at DESC);

-- RLS：与现有广告系统 RLS 模式一致，含 merchant_staff（R1）
ALTER TABLE ad_campaign_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "merchant_view_own_logs" ON ad_campaign_logs
  FOR SELECT USING (merchant_id IN (
    SELECT id FROM merchants WHERE user_id = auth.uid()
    UNION
    SELECT merchant_id FROM merchant_staff WHERE user_id = auth.uid()
  ));

CREATE POLICY "service_role_full_access_logs" ON ad_campaign_logs
  FOR ALL USING (auth.role() = 'service_role');

-- ============================================================
-- Step 3: 修改 charge_ad_account 返回 jsonb（R3）
-- 含 status + balance_after，record-ad-event 原子获取余额
-- 同时在 exhausted 时写日志（R20/R22/R23）
-- ============================================================
DROP FUNCTION IF EXISTS charge_ad_account(uuid, uuid, numeric, text, uuid);

CREATE OR REPLACE FUNCTION charge_ad_account(
  p_campaign_id  uuid,
  p_merchant_id  uuid,
  p_cost         numeric,
  p_event_type   text,
  p_user_id      uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_balance      numeric;
  v_today_spend  numeric;
  v_daily_budget numeric;
  v_status       text := 'ok';
BEGIN
  -- 锁顺序 1/2：先锁 ad_accounts
  SELECT balance INTO v_balance
  FROM ad_accounts
  WHERE merchant_id = p_merchant_id
  FOR UPDATE;

  IF v_balance IS NULL THEN
    RETURN jsonb_build_object('status', 'insufficient_balance', 'balance_after', 0);
  END IF;

  IF v_balance < p_cost THEN
    RETURN jsonb_build_object('status', 'insufficient_balance', 'balance_after', v_balance);
  END IF;

  -- 锁顺序 2/2：再锁 ad_campaigns
  SELECT today_spend, daily_budget INTO v_today_spend, v_daily_budget
  FROM ad_campaigns
  WHERE id = p_campaign_id
  FOR UPDATE;

  IF v_today_spend + p_cost > v_daily_budget THEN
    UPDATE ad_campaigns SET status = 'exhausted', updated_at = now()
    WHERE id = p_campaign_id;

    -- R20/R22: exhausted 日志在同事务内写入，避免并发竞争
    -- R23: today_spend 含当笔费用
    INSERT INTO ad_campaign_logs (campaign_id, merchant_id, actor_type, event_type, detail)
    VALUES (p_campaign_id, p_merchant_id, 'system', 'exhausted',
      jsonb_build_object('today_spend', v_today_spend + p_cost, 'daily_budget', v_daily_budget));

    RETURN jsonb_build_object('status', 'daily_budget_exceeded', 'balance_after', v_balance);
  END IF;

  -- 扣余额
  UPDATE ad_accounts SET
    balance      = balance - p_cost,
    total_spent  = total_spent + p_cost,
    updated_at   = now()
  WHERE merchant_id = p_merchant_id;

  -- 更新 campaign 统计
  UPDATE ad_campaigns SET
    today_spend       = today_spend + p_cost,
    total_spend       = total_spend + p_cost,
    today_impressions = today_impressions + CASE WHEN p_event_type = 'impression' THEN 1 ELSE 0 END,
    today_clicks      = today_clicks      + CASE WHEN p_event_type = 'click'      THEN 1 ELSE 0 END,
    total_impressions = total_impressions + CASE WHEN p_event_type = 'impression' THEN 1 ELSE 0 END,
    total_clicks      = total_clicks      + CASE WHEN p_event_type = 'click'      THEN 1 ELSE 0 END,
    updated_at        = now()
  WHERE id = p_campaign_id;

  -- 写事件日志
  INSERT INTO ad_events (campaign_id, merchant_id, event_type, cost, user_id)
  VALUES (p_campaign_id, p_merchant_id, p_event_type, p_cost, p_user_id);

  v_balance := v_balance - p_cost;

  -- 低余额预警
  IF v_balance < v_daily_budget THEN
    v_status := 'ok_low_balance';
  END IF;

  RETURN jsonb_build_object('status', v_status, 'balance_after', v_balance);
END;
$$;

-- ============================================================
-- Step 4: 修改 add_ad_balance 写入充值日志 + 自动恢复 exhausted（R18/R25）
-- ============================================================
DROP FUNCTION IF EXISTS add_ad_balance(uuid, numeric, text);

CREATE OR REPLACE FUNCTION add_ad_balance(
  p_merchant_id       uuid,
  p_amount            numeric,
  p_payment_intent_id text
)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  v_recharge_status text;
  v_new_balance     numeric;
BEGIN
  -- 查找充值记录并锁定
  SELECT status INTO v_recharge_status
  FROM ad_recharges
  WHERE stripe_payment_intent_id = p_payment_intent_id
  FOR UPDATE;

  IF v_recharge_status IS NULL THEN
    RETURN 'not_found';
  END IF;

  -- 幂等：已处理过直接返回
  IF v_recharge_status = 'succeeded' THEN
    RETURN 'already_processed';
  END IF;

  -- 更新充值记录状态
  UPDATE ad_recharges
  SET status = 'succeeded'
  WHERE stripe_payment_intent_id = p_payment_intent_id;

  -- 增加广告账户余额
  UPDATE ad_accounts SET
    balance         = balance + p_amount,
    total_recharged = total_recharged + p_amount,
    updated_at      = now()
  WHERE merchant_id = p_merchant_id
  RETURNING balance INTO v_new_balance;

  -- R18: 充值日志（账户级事件，campaign_id = NULL）
  INSERT INTO ad_campaign_logs (campaign_id, merchant_id, actor_type, event_type, detail)
  VALUES (NULL, p_merchant_id, 'system', 'budget_recharged',
    jsonb_build_object('amount', p_amount, 'balance_after', v_new_balance));

  -- R25: 充值后自动恢复 exhausted campaigns
  -- 先写日志再更新状态（UPDATE 后就查不到 exhausted 了）
  INSERT INTO ad_campaign_logs (campaign_id, merchant_id, actor_type, event_type, detail)
  SELECT id, merchant_id, 'system', 'resumed',
    jsonb_build_object('reason', 'budget_recharged')
  FROM ad_campaigns
  WHERE merchant_id = p_merchant_id AND status = 'exhausted';

  UPDATE ad_campaigns SET status = 'active', updated_at = now()
  WHERE merchant_id = p_merchant_id AND status = 'exhausted';

  RETURN 'ok';
END;
$$;

-- ============================================================
-- Step 5: toggle_splash_placement RPC（R15 原子性）
-- 一个事务内完成：改配置 + 批量暂停/恢复 + 写日志
-- ============================================================
CREATE OR REPLACE FUNCTION toggle_splash_placement(
  p_enabled       boolean,
  p_admin_user_id uuid
)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_affected int := 0;
  v_campaign record;
BEGIN
  -- Step 1: 更新配置表
  UPDATE ad_placement_config SET is_enabled = p_enabled WHERE placement = 'splash';

  IF p_enabled = false THEN
    -- Step 2a: 批量暂停 active splash campaigns
    FOR v_campaign IN
      SELECT id, merchant_id FROM ad_campaigns
      WHERE placement = 'splash' AND status = 'active'
    LOOP
      UPDATE ad_campaigns
      SET status = 'admin_paused', auto_paused_by = 'splash_disabled', updated_at = now()
      WHERE id = v_campaign.id;

      INSERT INTO ad_campaign_logs (campaign_id, merchant_id, actor_type, actor_user_id, event_type, detail)
      VALUES (v_campaign.id, v_campaign.merchant_id, 'admin', p_admin_user_id, 'splash_auto_paused', '{}');

      v_affected := v_affected + 1;
    END LOOP;
  ELSE
    -- Step 2b: 批量恢复自动暂停的 campaigns（不恢复手动 admin_paused 的）
    FOR v_campaign IN
      SELECT id, merchant_id FROM ad_campaigns
      WHERE placement = 'splash' AND status = 'admin_paused' AND auto_paused_by = 'splash_disabled'
    LOOP
      UPDATE ad_campaigns
      SET status = 'active', auto_paused_by = NULL, updated_at = now()
      WHERE id = v_campaign.id;

      INSERT INTO ad_campaign_logs (campaign_id, merchant_id, actor_type, actor_user_id, event_type, detail)
      VALUES (v_campaign.id, v_campaign.merchant_id, 'admin', p_admin_user_id, 'splash_auto_resumed', '{}');

      v_affected := v_affected + 1;
    END LOOP;
  END IF;

  RETURN v_affected;
END;
$$;

-- R19: 仅 service_role 可调用
REVOKE EXECUTE ON FUNCTION toggle_splash_placement(boolean, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION toggle_splash_placement(boolean, uuid) TO service_role;
