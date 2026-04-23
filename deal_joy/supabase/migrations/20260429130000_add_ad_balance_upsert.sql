-- 更新 add_ad_balance RPC
-- 新增对"充值记录不存在"情况的处理（Stripe Checkout Session 流程中，
-- session.payment_intent 在创建时可能为 null，导致无法预建记录）
-- webhook 在 payment_intent.succeeded 时携带完整 PI ID，此时直接创建并更新余额

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
  v_ad_account_id   uuid;
BEGIN
  -- 查找充值记录并锁定
  SELECT status INTO v_recharge_status
  FROM ad_recharges
  WHERE stripe_payment_intent_id = p_payment_intent_id
  FOR UPDATE;

  IF v_recharge_status IS NULL THEN
    -- 记录不存在（Checkout Session 流程：PI ID 在创建时不可用，未预建记录）
    -- 直接查找广告账户，创建记录并更新余额（原子事务）

    SELECT id INTO v_ad_account_id
    FROM ad_accounts
    WHERE merchant_id = p_merchant_id;

    IF v_ad_account_id IS NULL THEN
      RETURN 'account_not_found';
    END IF;

    INSERT INTO ad_recharges (
      merchant_id, ad_account_id, amount, stripe_payment_intent_id, status
    ) VALUES (
      p_merchant_id, v_ad_account_id, p_amount, p_payment_intent_id, 'succeeded'
    ) ON CONFLICT (stripe_payment_intent_id) DO NOTHING;

    UPDATE ad_accounts SET
      balance         = balance + p_amount,
      total_recharged = total_recharged + p_amount,
      updated_at      = now()
    WHERE merchant_id = p_merchant_id;

    RETURN 'ok';
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
  WHERE merchant_id = p_merchant_id;

  RETURN 'ok';
END;
$$;
