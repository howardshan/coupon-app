-- ============================================================
-- Order System V3: 触发器 + RPC 函数
--
-- 1. order_items INSERT → 自动创建 coupon（含 16 位券码）
-- 2. order_items BEFORE INSERT → 门店快照
-- 3. order_items INSERT → total_sold +1
-- 4. add_store_credit() RPC 函数
-- ============================================================


-- ============================================================
-- 1. order_item INSERT → 自动创建 coupon
-- ============================================================
CREATE OR REPLACE FUNCTION public.auto_create_coupon_per_item()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_deal       RECORD;
  v_expires_at timestamptz;
  v_coupon_id  uuid;
  v_user_id    uuid;
  v_code       char(16);
BEGIN
  -- 获取 deal 信息
  SELECT merchant_id, expires_at, validity_type, validity_days
  INTO v_deal
  FROM public.deals WHERE id = NEW.deal_id;

  -- 获取订单所属用户
  SELECT user_id INTO v_user_id
  FROM public.orders WHERE id = NEW.order_id;

  -- 根据 validity_type 计算过期时间
  v_expires_at := CASE v_deal.validity_type
    WHEN 'fixed_date'           THEN v_deal.expires_at
    WHEN 'short_after_purchase' THEN now() + (COALESCE(v_deal.validity_days, 7) || ' days')::interval
    WHEN 'long_after_purchase'  THEN now() + (COALESCE(v_deal.validity_days, 30) || ' days')::interval
    ELSE COALESCE(v_deal.expires_at, now() + INTERVAL '30 days')
  END;

  -- 生成唯一 16 位券码（碰撞时重试）
  LOOP
    v_code := UPPER(SUBSTRING(REPLACE(gen_random_uuid()::text, '-', ''), 1, 16));
    EXIT WHEN NOT EXISTS (SELECT 1 FROM public.coupons WHERE coupon_code = v_code);
  END LOOP;

  -- 创建 coupon
  INSERT INTO public.coupons (
    order_id, order_item_id, user_id, deal_id, merchant_id,
    purchased_merchant_id,
    qr_code, coupon_code, status, expires_at
  ) VALUES (
    NEW.order_id,
    NEW.id,
    v_user_id,
    NEW.deal_id,
    v_deal.merchant_id,
    COALESCE(NEW.purchased_merchant_id, v_deal.merchant_id),
    public.generate_qr_code_16_numeric(),  -- 复用现有的 16 位数字 QR 生成函数
    v_code,
    'unused',
    v_expires_at
  )
  RETURNING id INTO v_coupon_id;

  -- 回填 order_items.coupon_id
  UPDATE public.order_items SET coupon_id = v_coupon_id WHERE id = NEW.id;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_order_item_created ON public.order_items;
CREATE TRIGGER on_order_item_created
  AFTER INSERT ON public.order_items
  FOR EACH ROW EXECUTE FUNCTION public.auto_create_coupon_per_item();


-- ============================================================
-- 2. order_items BEFORE INSERT → 门店快照
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_snapshot_stores_for_item()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_store_ids uuid[];
BEGIN
  -- 如果调用方已传入 applicable_store_ids，直接使用
  IF NEW.applicable_store_ids IS NOT NULL AND array_length(NEW.applicable_store_ids, 1) > 0 THEN
    RETURN NEW;
  END IF;

  -- 从 deal_applicable_stores 查询活跃门店
  SELECT array_agg(das.store_id) INTO v_store_ids
  FROM public.deal_applicable_stores das
  WHERE das.deal_id = NEW.deal_id AND das.status = 'active';

  IF v_store_ids IS NOT NULL AND array_length(v_store_ids, 1) > 0 THEN
    NEW.applicable_store_ids := v_store_ids;
  ELSE
    -- 单店 deal：使用 deal 的 merchant_id
    SELECT ARRAY[d.merchant_id] INTO v_store_ids
    FROM public.deals d WHERE d.id = NEW.deal_id;
    NEW.applicable_store_ids := v_store_ids;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_snapshot_stores_for_item ON public.order_items;
CREATE TRIGGER trg_snapshot_stores_for_item
  BEFORE INSERT ON public.order_items
  FOR EACH ROW EXECUTE FUNCTION public.fn_snapshot_stores_for_item();


-- ============================================================
-- 3. order_items INSERT → total_sold +1
-- ============================================================
CREATE OR REPLACE FUNCTION public.sync_deal_total_sold_on_item_insert()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE public.deals
  SET total_sold = COALESCE(total_sold, 0) + 1,
      updated_at = now()
  WHERE id = NEW.deal_id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_deal_total_sold_item_insert ON public.order_items;
CREATE TRIGGER trg_sync_deal_total_sold_item_insert
  AFTER INSERT ON public.order_items
  FOR EACH ROW EXECUTE FUNCTION public.sync_deal_total_sold_on_item_insert();


-- ============================================================
-- 4. add_store_credit() RPC 函数
-- ============================================================
CREATE OR REPLACE FUNCTION public.add_store_credit(
  p_user_id       uuid,
  p_amount        numeric,
  p_order_item_id uuid    DEFAULT NULL,
  p_description   text    DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
  -- UPSERT store_credits：存在则累加，不存在则新建
  INSERT INTO public.store_credits (user_id, amount)
  VALUES (p_user_id, p_amount)
  ON CONFLICT (user_id)
  DO UPDATE SET amount = public.store_credits.amount + p_amount,
                updated_at = now();

  -- 记录流水
  INSERT INTO public.store_credit_transactions
    (user_id, order_item_id, amount, type, description)
  VALUES
    (p_user_id, p_order_item_id, p_amount, 'refund_credit', p_description);
END;
$$;

GRANT EXECUTE ON FUNCTION public.add_store_credit(uuid, numeric, uuid, text)
  TO authenticated, service_role;
