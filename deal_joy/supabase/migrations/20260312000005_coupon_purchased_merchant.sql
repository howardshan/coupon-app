-- ============================================================
-- coupons 表新增 purchased_merchant_id 字段
-- 记录用户购买时选择的门店（brand_multi_store deal 用）
-- store_only deal 的 purchased_merchant_id = merchant_id（创建者门店）
-- ============================================================

-- 1. 添加字段（允许 NULL，兼容历史数据）
ALTER TABLE public.coupons
  ADD COLUMN IF NOT EXISTS purchased_merchant_id UUID REFERENCES public.merchants(id) DEFAULT NULL;

-- 2. orders 表也添加 purchased_merchant_id，让前端在创建订单时传入
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS purchased_merchant_id UUID REFERENCES public.merchants(id) DEFAULT NULL;

-- 3. 索引
CREATE INDEX IF NOT EXISTS idx_coupons_purchased_merchant_id
  ON public.coupons(purchased_merchant_id);

-- 4. 回填历史数据：已有 coupon 的 purchased_merchant_id 设为 merchant_id
UPDATE public.coupons
SET purchased_merchant_id = merchant_id
WHERE purchased_merchant_id IS NULL;

-- 5. 更新 auto_create_coupon 触发器：读取 order 的 purchased_merchant_id
CREATE OR REPLACE FUNCTION public.auto_create_coupon()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  new_coupon_id UUID;
  deal_row RECORD;
BEGIN
  -- 获取 deal 的 merchant_id 和 expires_at
  SELECT merchant_id, expires_at INTO deal_row
    FROM public.deals WHERE id = NEW.deal_id;

  -- 生成 coupon，purchased_merchant_id 优先取 order 传入的值，否则用 deal 的 merchant_id
  INSERT INTO public.coupons (order_id, user_id, deal_id, merchant_id, purchased_merchant_id, qr_code, expires_at)
  VALUES (
    NEW.id,
    NEW.user_id,
    NEW.deal_id,
    deal_row.merchant_id,
    COALESCE(NEW.purchased_merchant_id, deal_row.merchant_id),
    encode(gen_random_bytes(32), 'hex'),
    deal_row.expires_at
  )
  RETURNING id INTO new_coupon_id;

  -- 回填 orders.coupon_id
  UPDATE public.orders SET coupon_id = new_coupon_id WHERE id = NEW.id;

  RETURN NEW;
END;
$$;
