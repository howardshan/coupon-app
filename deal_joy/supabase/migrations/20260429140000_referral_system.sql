-- =============================================================
-- Referral System：用户推荐功能完整 schema
-- 功能：Admin 配置奖励金额；推荐人分享 link；
--       被推荐人注册后立即获得 store credit；
--       被推荐人首次核销后推荐人获得 store credit
-- =============================================================

-- ── 1. 扩展 users 表 ──────────────────────────────────────────
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS referral_code text UNIQUE,
  ADD COLUMN IF NOT EXISTS referred_by   uuid REFERENCES public.users(id);

CREATE INDEX IF NOT EXISTS idx_users_referral_code ON public.users(referral_code);
CREATE INDEX IF NOT EXISTS idx_users_referred_by   ON public.users(referred_by);

-- ── 2. referral_code 生成函数 ─────────────────────────────────
-- 使用 24 个安全字符（排除 O/0、I/1 避免混淆）
CREATE OR REPLACE FUNCTION public.generate_referral_code()
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  chars  CONSTANT text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  result text := '';
  byte   int;
  i      int;
BEGIN
  FOR attempt IN 1..10 LOOP
    result := '';
    FOR i IN 1..8 LOOP
      byte := get_byte(gen_random_bytes(1), 0) % length(chars) + 1;
      result := result || substr(chars, byte, 1);
    END LOOP;
    IF NOT EXISTS (SELECT 1 FROM public.users WHERE referral_code = result) THEN
      RETURN result;
    END IF;
  END LOOP;
  RAISE EXCEPTION 'Failed to generate unique referral_code after 10 attempts';
END;
$$;

-- ── 3. 更新 handle_new_user 触发器（合并 OAuth email fallback）────
-- 保留 20260421120000_handle_new_user_oauth_email_fallback.sql 的全部逻辑，
-- 新增 referral_code 字段
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  resolved_email text;
BEGIN
  resolved_email := COALESCE(
    NULLIF(BTRIM(COALESCE(new.email::text, '')), ''),
    NULLIF(BTRIM(COALESCE(new.raw_user_meta_data->>'email', '')), ''),
    'oauth-' || replace(new.id::text, '-', '') || '@users.local'
  );

  INSERT INTO public.users (
    id, email, full_name, avatar_url, username,
    registration_source, date_of_birth,
    marketing_opt_in, analytics_opt_in,
    referral_code
  )
  VALUES (
    new.id,
    resolved_email,
    new.raw_user_meta_data->>'full_name',
    new.raw_user_meta_data->>'avatar_url',
    new.raw_user_meta_data->>'username',
    COALESCE(new.raw_app_meta_data->>'provider', 'email'),
    CASE
      WHEN new.raw_user_meta_data->>'date_of_birth' IS NOT NULL
      THEN (new.raw_user_meta_data->>'date_of_birth')::date
      ELSE NULL
    END,
    COALESCE((new.raw_user_meta_data->>'marketing_opt_in')::boolean, false),
    COALESCE((new.raw_user_meta_data->>'analytics_opt_in')::boolean, false),
    public.generate_referral_code()
  );
  RETURN new;
END;
$$;

-- ── 4. 存量用户补全 referral_code ─────────────────────────────
DO $$
DECLARE
  rec record;
BEGIN
  FOR rec IN SELECT id FROM public.users WHERE referral_code IS NULL LOOP
    UPDATE public.users
    SET referral_code = public.generate_referral_code()
    WHERE id = rec.id;
  END LOOP;
END;
$$;

ALTER TABLE public.users
  ALTER COLUMN referral_code SET NOT NULL;

-- ── 5. referral_config 单行配置表 ─────────────────────────────
CREATE TABLE IF NOT EXISTS public.referral_config (
  id           int PRIMARY KEY DEFAULT 1,
  enabled      boolean NOT NULL DEFAULT false,
  bonus_amount numeric(10,2) NOT NULL DEFAULT 5.00,
  updated_at   timestamptz NOT NULL DEFAULT now(),
  updated_by   uuid REFERENCES public.users(id),
  CONSTRAINT referral_config_single_row CHECK (id = 1),
  CONSTRAINT referral_config_bonus_non_negative CHECK (bonus_amount >= 0)
);

INSERT INTO public.referral_config (id, enabled, bonus_amount)
VALUES (1, false, 5.00)
ON CONFLICT (id) DO NOTHING;

ALTER TABLE public.referral_config ENABLE ROW LEVEL SECURITY;

-- 任何人都可以读取配置（Flutter anon/authenticated 均可展示奖励金额）
CREATE POLICY "referral_config_select_all"
  ON public.referral_config FOR SELECT
  USING (true);

-- 只有 service_role 可写（Admin 端通过 service_role client 修改）
CREATE POLICY "referral_config_update_service_role"
  ON public.referral_config FOR UPDATE
  TO service_role
  USING (true)
  WITH CHECK (true);

-- ── 6. referrals 记录表 ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.referrals (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  referrer_id            uuid NOT NULL REFERENCES public.users(id),
  referee_id             uuid NOT NULL UNIQUE, -- 每人只能被推荐一次
  bonus_amount           numeric(10,2) NOT NULL,
  -- pending: 推荐人奖励待触发（referee 尚未核销第一张券）
  -- credited: 推荐人已获得奖励
  -- cancelled: 已取消（Admin 操作）
  status                 text NOT NULL DEFAULT 'pending'
                         CHECK (status IN ('pending', 'credited', 'cancelled')),
  triggered_by_coupon_id uuid REFERENCES public.coupons(id),
  credited_at            timestamptz, -- 推荐人奖励到账时间
  created_at             timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (referee_id) REFERENCES public.users(id)
);

CREATE INDEX IF NOT EXISTS idx_referrals_referrer_id ON public.referrals(referrer_id);
CREATE INDEX IF NOT EXISTS idx_referrals_status      ON public.referrals(status);

ALTER TABLE public.referrals ENABLE ROW LEVEL SECURITY;

-- 用户可查看自己作为推荐人的记录（Referral Screen 展示用）
CREATE POLICY "referrals_select_as_referrer"
  ON public.referrals FOR SELECT
  USING (referrer_id = auth.uid());

-- service_role 全权操作（Admin 端、Edge Function 写入）
CREATE POLICY "referrals_all_service_role"
  ON public.referrals FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- ── 7. 扩展 store_credit_transactions type 约束 ────────────────
ALTER TABLE public.store_credit_transactions
  DROP CONSTRAINT IF EXISTS store_credit_transactions_type_check;

ALTER TABLE public.store_credit_transactions
  ADD CONSTRAINT store_credit_transactions_type_check
  CHECK (type IN (
    'refund_credit',
    'purchase_deduction',
    'admin_adjustment',
    'referral_bonus'  -- 新增：推荐奖励（含推荐人奖励和被推荐人欢迎奖励）
  ));

-- ── 8. apply_referral_code RPC（authenticated 用户调用）─────────
-- 被推荐人通过 deep link 注册后调用，完成绑定 + 立即发放欢迎奖励
CREATE OR REPLACE FUNCTION public.apply_referral_code(p_code text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id    uuid := auth.uid();
  v_referrer_id  uuid;
  v_has_used     boolean;
  v_enabled      boolean;
  v_bonus        numeric(10,2);
BEGIN
  IF v_caller_id IS NULL THEN
    RETURN 'unauthorized';
  END IF;

  -- 检查调用者是否已绑定过
  IF EXISTS (
    SELECT 1 FROM public.users
    WHERE id = v_caller_id AND referred_by IS NOT NULL
  ) THEN
    RETURN 'already_applied';
  END IF;

  -- 检查功能是否开启
  SELECT enabled, bonus_amount
  INTO v_enabled, v_bonus
  FROM public.referral_config
  WHERE id = 1;

  IF NOT COALESCE(v_enabled, false) THEN
    RETURN 'disabled';
  END IF;

  -- 检查调用者是否已有核销记录（必须在首次核销前绑定）
  SELECT EXISTS (
    SELECT 1 FROM public.order_items oi
    JOIN public.orders o ON o.id = oi.order_id
    WHERE o.user_id = v_caller_id
      AND oi.customer_status = 'used'
  ) INTO v_has_used;

  IF v_has_used THEN
    RETURN 'redemption_exists';
  END IF;

  -- 查找推荐人（code 不区分大小写）
  SELECT id INTO v_referrer_id
  FROM public.users
  WHERE referral_code = upper(trim(p_code))
    AND role IN ('user', 'merchant'); -- admin 的 code 不能被使用

  IF v_referrer_id IS NULL THEN
    RETURN 'code_not_found';
  END IF;

  IF v_referrer_id = v_caller_id THEN
    RETURN 'self_referral';
  END IF;

  -- 绑定推荐关系
  UPDATE public.users
  SET referred_by = v_referrer_id
  WHERE id = v_caller_id;

  -- 插入 referrals 记录（status='pending'，等待推荐人奖励触发）
  INSERT INTO public.referrals (
    referrer_id, referee_id, bonus_amount, status
  )
  VALUES (
    v_referrer_id, v_caller_id, v_bonus, 'pending'
  )
  ON CONFLICT (referee_id) DO NOTHING;

  -- 立即发放被推荐人的欢迎奖励（referee 立即获得 store credit）
  PERFORM public.admin_adjust_store_credit(
    v_caller_id,
    v_bonus,
    'Referral welcome bonus — invited by a friend'
  );

  -- 返回 'ok:<金额>'，客户端解析展示弹窗金额
  RETURN 'ok:' || v_bonus::text;
END;
$$;

REVOKE ALL ON FUNCTION public.apply_referral_code(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.apply_referral_code(text) TO authenticated;

COMMENT ON FUNCTION public.apply_referral_code(text) IS
  '被推荐人通过 deep link 注册后调用。绑定 referred_by + 立即给被推荐人发 store credit。'
  '返回 ok:<amount> 或 disabled/already_applied/redemption_exists/code_not_found/self_referral/unauthorized';

-- ── 9. process_referral_bonus RPC（service_role 调用）─────────
-- 被推荐人首次核销后由 merchant-scan Edge Function 调用
-- 给推荐人发放奖励，并将 referrals.status 更新为 credited
CREATE OR REPLACE FUNCTION public.process_referral_bonus(
  p_referee_id uuid,
  p_coupon_id  uuid
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_referrer_id  uuid;
  v_bonus        numeric(10,2);
  v_enabled      boolean;
  v_referral_id  uuid;
BEGIN
  -- 检查功能开关
  SELECT enabled, bonus_amount
  INTO v_enabled, v_bonus
  FROM public.referral_config
  WHERE id = 1;

  IF NOT COALESCE(v_enabled, false) THEN
    RETURN 'disabled';
  END IF;

  -- 查找推荐人
  SELECT referred_by INTO v_referrer_id
  FROM public.users
  WHERE id = p_referee_id;

  IF v_referrer_id IS NULL THEN
    RETURN 'no_referrer';
  END IF;

  -- 幂等检查：referee_id UNIQUE 保证 ON CONFLICT DO NOTHING 原子性
  -- 查找 pending 状态的 referral 记录并锁定（防并发重复发放）
  SELECT id INTO v_referral_id
  FROM public.referrals
  WHERE referee_id = p_referee_id
    AND status = 'pending'
  FOR UPDATE SKIP LOCKED;

  IF v_referral_id IS NULL THEN
    -- 记录不存在或已处理
    RETURN 'already_processed';
  END IF;

  -- 更新 referrals 状态为已发放
  UPDATE public.referrals
  SET status = 'credited',
      credited_at = now(),
      triggered_by_coupon_id = p_coupon_id
  WHERE id = v_referral_id;

  -- 查取实际记录的 bonus_amount（创建时快照的金额，而非当前配置）
  SELECT bonus_amount INTO v_bonus
  FROM public.referrals
  WHERE id = v_referral_id;

  -- 发放推荐人奖励
  PERFORM public.admin_adjust_store_credit(
    v_referrer_id,
    v_bonus,
    'Referral bonus — friend redeemed their first voucher'
  );

  RETURN 'ok';
END;
$$;

REVOKE ALL ON FUNCTION public.process_referral_bonus(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.process_referral_bonus(uuid, uuid) TO service_role;

COMMENT ON FUNCTION public.process_referral_bonus(uuid, uuid) IS
  '被推荐人首次核销后由 merchant-scan 调用。给推荐人发放 store credit。'
  'FOR UPDATE SKIP LOCKED 保证并发安全，防止重复发放。'
  '返回 ok / disabled / no_referrer / already_processed';
