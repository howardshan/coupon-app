-- =============================================================
-- 优惠券赠送与核销功能
-- 功能：
--   1. coupons 表新增 gifted_from 列（记录来源券 ID）
--   2. coupons 表新增 verified_by 列（记录核销商家用户 ID）
--   3. gift_coupon() 函数：原子赠送操作
-- =============================================================

-- -------------------------------------------------------------
-- 1. 新增 gifted_from 列
--    可空 uuid，引用 coupons(id)，记录本券从哪张原券赠出
-- -------------------------------------------------------------
ALTER TABLE public.coupons
  ADD COLUMN IF NOT EXISTS gifted_from uuid
    REFERENCES public.coupons(id)
    ON DELETE SET NULL;

-- 为 gifted_from 建立索引，方便按来源券查询赠送记录
CREATE INDEX IF NOT EXISTS idx_coupons_gifted_from
  ON public.coupons(gifted_from);

-- -------------------------------------------------------------
-- 2. 新增 verified_by 列
--    可空 uuid，记录扫码核销该券的商家用户 ID（auth.users.id）
--    不设外键约束，避免商家账户被删除时级联影响核销记录
-- -------------------------------------------------------------
ALTER TABLE public.coupons
  ADD COLUMN IF NOT EXISTS verified_by uuid;

-- -------------------------------------------------------------
-- 3. RLS 说明
--    赠送后新券的 user_id 已被设为受赠人 ID，
--    现有 "coupons_select_own" 策略（auth.uid() = user_id）
--    已自动覆盖受赠人查询自己优惠券的场景，无需新增策略。
-- -------------------------------------------------------------

-- -------------------------------------------------------------
-- 4. gift_coupon() 函数
--    参数:
--      p_coupon_id        uuid  -- 要赠送的原券 ID
--      p_recipient_user_id uuid  -- 受赠人的 user ID
--    返回:
--      uuid  -- 新生成的优惠券 ID
--    说明:
--      - 校验原券存在、状态为 unused、未过期、尚未被赠出
--      - 原子执行：生成受赠人新券，原券状态改为 refunded
--      - SECURITY DEFINER：绕过 RLS 直接操作表，
--        由函数内部逻辑保证权限安全
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.gift_coupon(
  p_coupon_id         uuid,
  p_recipient_user_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_coupon        public.coupons%ROWTYPE;
  v_new_coupon_id uuid;
BEGIN
  -- 加行锁，防止并发重复赠送
  SELECT * INTO v_coupon
    FROM public.coupons
   WHERE id = p_coupon_id
     FOR UPDATE;

  -- 校验：优惠券是否存在
  IF NOT FOUND THEN
    RAISE EXCEPTION 'coupon_not_found: coupon % does not exist', p_coupon_id;
  END IF;

  -- 校验：状态必须为 unused
  IF v_coupon.status <> 'unused' THEN
    RAISE EXCEPTION 'coupon_invalid_status: coupon status is %, must be unused', v_coupon.status;
  END IF;

  -- 校验：优惠券未过期
  IF v_coupon.expires_at <= now() THEN
    RAISE EXCEPTION 'coupon_expired: coupon % expired at %', p_coupon_id, v_coupon.expires_at;
  END IF;

  -- 校验：原券本身不是赠出券（防止链式赠送 / 二次赠送同一张原券）
  --   gifted_from IS NOT NULL 说明本券已经是别人赠给当前用户的，
  --   不允许再次转赠，避免无限链路。
  IF v_coupon.gifted_from IS NOT NULL THEN
    RAISE EXCEPTION 'coupon_already_gifted: this coupon was itself a gift and cannot be re-gifted';
  END IF;

  -- 校验：受赠人不能是券的当前持有人自己
  IF v_coupon.user_id = p_recipient_user_id THEN
    RAISE EXCEPTION 'coupon_self_gift: cannot gift a coupon to yourself';
  END IF;

  -- 原子操作 A：为受赠人创建新优惠券
  --   继承原券的 deal_id / merchant_id / expires_at，
  --   order_id 复用原券的 order_id（保留订单关联），
  --   生成新 qr_code，gifted_from 指向原券 ID
  INSERT INTO public.coupons (
    order_id,
    user_id,
    deal_id,
    merchant_id,
    qr_code,
    status,
    expires_at,
    gifted_from
  )
  VALUES (
    v_coupon.order_id,
    p_recipient_user_id,
    v_coupon.deal_id,
    v_coupon.merchant_id,
    encode(gen_random_bytes(32), 'hex'),  -- 生成新的 64 位十六进制 QR token
    'unused',
    v_coupon.expires_at,
    p_coupon_id  -- 记录来源原券
  )
  RETURNING id INTO v_new_coupon_id;

  -- 原子操作 B：将原券状态标记为 refunded，使其失效
  UPDATE public.coupons
     SET status = 'refunded'
   WHERE id = p_coupon_id;

  -- 返回新券 ID，供调用方使用
  RETURN v_new_coupon_id;
END;
$$;

-- 限制函数执行权限：仅 authenticated 用户可调用
REVOKE ALL ON FUNCTION public.gift_coupon(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gift_coupon(uuid, uuid) TO authenticated;
