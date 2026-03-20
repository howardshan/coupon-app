-- =============================================================
-- Migration: qr_code_16_numeric
-- 把新生成的 coupons.qr_code 改为 16 位纯数字（不含分隔符）
--
-- 设计：
-- - coupons.qr_code: ^\d{16}$（unique）
-- - 显示/输入层再做 4-4-4-4 的 '-' 分隔
-- - 旧券 qr_code 保持不变（无需批量改历史数据）
--
-- 影响范围：
-- - public.auto_create_coupon()：新订单触发生成券
-- - public.gift_coupon()：赠券触发生成新券
-- =============================================================

-- 生成 16 位数字 QR token（避免与现有 qr_code 冲突）
CREATE OR REPLACE FUNCTION public.generate_qr_code_16_numeric()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_qr text;
BEGIN
  LOOP
    -- 0 .. 9999999999999999，共 10^16 种组合
    v_qr := lpad((floor(random() * 10000000000000000)::bigint)::text, 16, '0');

    -- coupons.qr_code 有 unique 约束：这里做存在性检查保证不冲突
    IF NOT EXISTS (SELECT 1 FROM public.coupons WHERE qr_code = v_qr) THEN
      RETURN v_qr;
    END IF;
  END LOOP;
END;
$$;

-- 更新：orders -> coupons 的自动生成逻辑
CREATE OR REPLACE FUNCTION public.auto_create_coupon()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  new_coupon_id UUID;
  deal_row RECORD;
BEGIN
  -- 获取 deal 的 merchant_id 和 expires_at
  SELECT merchant_id, expires_at INTO deal_row
  FROM public.deals WHERE id = NEW.deal_id;

  -- 生成 coupon（purchased_merchant_id 优先取 order 传入，否则用 deal 的 merchant_id）
  INSERT INTO public.coupons (order_id, user_id, deal_id, merchant_id, purchased_merchant_id, qr_code, expires_at)
  VALUES (
    NEW.id,
    NEW.user_id,
    NEW.deal_id,
    deal_row.merchant_id,
    COALESCE(NEW.purchased_merchant_id, deal_row.merchant_id),
    public.generate_qr_code_16_numeric(),
    deal_row.expires_at
  )
  RETURNING id INTO new_coupon_id;

  -- 回填 orders.coupon_id
  UPDATE public.orders SET coupon_id = new_coupon_id WHERE id = NEW.id;

  RETURN NEW;
END;
$$;

-- 更新：赠券生成逻辑
CREATE OR REPLACE FUNCTION public.gift_coupon(
  p_coupon_id         uuid,
  p_recipient_user_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_coupon public.coupons%ROWTYPE;
  v_new_coupon_id uuid;
BEGIN
  -- 加行锁，防止并发重复赠送
  SELECT * INTO v_coupon
    FROM public.coupons
   WHERE id = p_coupon_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'coupon_not_found: coupon % does not exist', p_coupon_id;
  END IF;

  IF v_coupon.status <> 'unused' THEN
    RAISE EXCEPTION 'coupon_invalid_status: coupon status is %, must be unused', v_coupon.status;
  END IF;

  IF v_coupon.expires_at <= now() THEN
    RAISE EXCEPTION 'coupon_expired: coupon % expired at %', p_coupon_id, v_coupon.expires_at;
  END IF;

  IF v_coupon.gifted_from IS NOT NULL THEN
    RAISE EXCEPTION 'coupon_already_gifted: this coupon was itself a gift and cannot be re-gifted';
  END IF;

  IF v_coupon.user_id = p_recipient_user_id THEN
    RAISE EXCEPTION 'coupon_self_gift: cannot gift a coupon to yourself';
  END IF;

  -- 原子操作 A：为受赠人创建新优惠券
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
    public.generate_qr_code_16_numeric(),
    'unused',
    v_coupon.expires_at,
    p_coupon_id
  )
  RETURNING id INTO v_new_coupon_id;

  -- 原子操作 B：将原券状态标记为 refunded，使其失效
  UPDATE public.coupons
     SET status = 'refunded'
   WHERE id = p_coupon_id;

  RETURN v_new_coupon_id;
END;
$$;

