-- =============================================================
-- 账户删除：占位用户 + merchants.user_id 可空 + 批量 FK 重指派 RPC
-- 与 docs/plans/appendix-account-delete-fk.md 一致
-- =============================================================

-- 占位 UUID（与附录一致，勿随意变更）
CREATE OR REPLACE FUNCTION public.account_deleted_placeholder_id()
RETURNS uuid
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT 'a0000001-0000-4000-8000-000000000001'::uuid;
$$;

-- -----------------------------------------------------------------
-- 1) 系统占位账号：仅用于 FK 匿名化，不可用于真实登录
-- -----------------------------------------------------------------
DO $$
DECLARE
  v_instance uuid;
  v_id uuid := public.account_deleted_placeholder_id();
BEGIN
  SELECT instance_id INTO v_instance FROM auth.users LIMIT 1;
  IF v_instance IS NULL THEN
    v_instance := '00000000-0000-0000-0000-000000000000'::uuid;
  END IF;

  INSERT INTO auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at,
    confirmation_token,
    recovery_token
  )
  VALUES (
    v_instance,
    v_id,
    'authenticated',
    'authenticated',
    'internal-deleted-user@dealjoy.invalid',
    crypt('nologin-' || gen_random_uuid()::text, gen_salt('bf')),
    now(),
    '{"provider":"internal","providers":["internal"]}'::jsonb,
    '{"full_name":"Deleted user"}'::jsonb,
    now(),
    now(),
    '',
    ''
  )
  ON CONFLICT (id) DO NOTHING;
END $$;

-- 确保 public.users 存在（若触发器未跑）
INSERT INTO public.users (id, email, full_name, role)
SELECT public.account_deleted_placeholder_id(),
       'internal-deleted-user@dealjoy.invalid',
       'Deleted user',
       'user'::public.user_role
WHERE NOT EXISTS (
  SELECT 1 FROM public.users u WHERE u.id = public.account_deleted_placeholder_id()
);

-- -----------------------------------------------------------------
-- 2) 闭店后允许店主与门店解绑（ON DELETE SET NULL）
-- -----------------------------------------------------------------
ALTER TABLE public.merchants
  ALTER COLUMN user_id DROP NOT NULL;

DO $$
DECLARE
  cname text;
BEGIN
  SELECT tc.constraint_name INTO cname
  FROM information_schema.table_constraints tc
  JOIN information_schema.key_column_usage kcu
    ON tc.constraint_schema = kcu.constraint_schema
   AND tc.constraint_name = kcu.constraint_name
  WHERE tc.table_schema = 'public'
    AND tc.table_name = 'merchants'
    AND tc.constraint_type = 'FOREIGN KEY'
    AND kcu.column_name = 'user_id'
  LIMIT 1;

  IF cname IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.merchants DROP CONSTRAINT %I', cname);
  END IF;
END $$;

ALTER TABLE public.merchants
  ADD CONSTRAINT merchants_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;

-- -----------------------------------------------------------------
-- 3) 整账号删除：将业务表中的 p_from 合并到占位用户（service_role 调用）
-- -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.account_delete_reassign_all(p_from uuid, p_to uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_from IS NULL OR p_to IS NULL OR p_from = p_to THEN
    RAISE EXCEPTION 'invalid account_delete_reassign_all args';
  END IF;

  -- 订单 / 券 / 评价 / 支付
  UPDATE public.orders SET user_id = p_to WHERE user_id = p_from;
  UPDATE public.coupons SET user_id = p_to WHERE user_id = p_from;
  UPDATE public.coupons SET current_holder_user_id = p_to WHERE current_holder_user_id = p_from;
  UPDATE public.coupons SET gifted_from_user_id = NULL WHERE gifted_from_user_id = p_from;

  UPDATE public.reviews SET user_id = p_to WHERE user_id = p_from;
  UPDATE public.reviews SET reviewer_user_id = p_to WHERE reviewer_user_id = p_from;

  UPDATE public.payments SET user_id = p_to WHERE user_id = p_from;

  -- 退款申请
  UPDATE public.refund_requests SET user_id = p_to WHERE user_id = p_from;
  UPDATE public.refund_requests SET merchant_decided_by = p_to WHERE merchant_decided_by = p_from;
  UPDATE public.refund_requests SET admin_decided_by = p_to WHERE admin_decided_by = p_from;

  -- 礼品记录
  UPDATE public.coupon_gifts SET gifter_user_id = p_to WHERE gifter_user_id = p_from;
  UPDATE public.coupon_gifts SET recipient_user_id = p_to WHERE recipient_user_id = p_from;

  -- 购物车 / 积分（整账号删除时清空该用户余额与流水）
  DELETE FROM public.store_credit_transactions WHERE user_id = p_from;
  DELETE FROM public.store_credits WHERE user_id = p_from;
  DELETE FROM public.cart_items WHERE user_id = p_from;

  -- 推荐：解除指向被删用户的边
  UPDATE public.users SET referred_by = NULL WHERE referred_by = p_from;

  -- 聊天：消息发送者占位；成员行直接移除（保留会话与历史）
  UPDATE public.messages SET sender_id = p_to WHERE sender_id = p_from;
  DELETE FROM public.conversation_members WHERE user_id = p_from;
  UPDATE public.conversations SET created_by = p_to WHERE created_by = p_from;
  UPDATE public.conversations SET assigned_to = p_to WHERE assigned_to = p_from;

  -- 好友：删除边（比伪造占位对更简单，且符合「解除关系」）
  DELETE FROM public.friend_requests WHERE sender_id = p_from OR receiver_id = p_from;
  DELETE FROM public.friendships WHERE user_id = p_from OR friend_id = p_from;

  -- 通知与推送 token（可删）
  DELETE FROM public.notifications WHERE user_id = p_from;
  DELETE FROM public.user_fcm_tokens WHERE user_id = p_from;

  -- 支持工单（若存在）
  UPDATE public.support_claims SET user_id = p_to WHERE user_id = p_from;
  UPDATE public.support_claims SET created_by = p_to WHERE created_by = p_from;
  UPDATE public.support_claims SET resolved_by = p_to WHERE resolved_by = p_from;

  UPDATE public.support_callbacks SET user_id = p_to WHERE user_id = p_from;

  -- 营销 / 运营审计（可空列已在迁移里处理，此处覆盖常见表）
  UPDATE public.ad_campaign_logs SET actor_user_id = p_to WHERE actor_user_id = p_from;

  -- 广告事件（用户维度可空）
  UPDATE public.ad_events SET user_id = p_to WHERE user_id = p_from;

  -- 登录追踪
  DELETE FROM public.login_history WHERE user_id = p_from;

  -- 收藏（附录：硬删）
  DELETE FROM public.saved_deals WHERE user_id = p_from;
END $$;

REVOKE ALL ON FUNCTION public.account_delete_reassign_all(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.account_delete_reassign_all(uuid, uuid) TO service_role;

COMMENT ON FUNCTION public.account_delete_reassign_all IS '整账号删除前：将被删用户 ID 批量重指派/清理；须由 Edge service_role 调用';
