-- ============================================================
-- orders.applicable_store_ids — 购买时门店快照
-- 记录用户下单时哪些门店是 active 的，用于券核销验证
-- ============================================================

-- 1. 新增列
ALTER TABLE public.orders
ADD COLUMN applicable_store_ids uuid[] DEFAULT NULL;

-- 2. 创建触发器函数：INSERT 时自动填充 applicable_store_ids
CREATE OR REPLACE FUNCTION public.fn_snapshot_applicable_stores()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_store_ids uuid[];
BEGIN
  -- 查询该 Deal 当前所有 active 的门店
  SELECT array_agg(das.store_id)
  INTO v_store_ids
  FROM public.deal_applicable_stores das
  WHERE das.deal_id = NEW.deal_id
    AND das.status = 'active';

  -- 如果有 active 门店，写入快照
  IF v_store_ids IS NOT NULL AND array_length(v_store_ids, 1) > 0 THEN
    NEW.applicable_store_ids := v_store_ids;
  ELSE
    -- 没有 deal_applicable_stores 记录（极早期 Deal），
    -- 回退为 Deal 的 merchant_id（单店场景）
    SELECT ARRAY[d.merchant_id]
    INTO v_store_ids
    FROM public.deals d
    WHERE d.id = NEW.deal_id;

    NEW.applicable_store_ids := v_store_ids;
  END IF;

  RETURN NEW;
END;
$$;

-- 3. 绑定触发器到 orders 表的 INSERT
CREATE TRIGGER trg_snapshot_applicable_stores
BEFORE INSERT ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.fn_snapshot_applicable_stores();

-- 4. 回填历史订单（从 deal_applicable_stores 中取当前 active 门店）
-- 注意：历史订单只能取当前状态，无法还原购买时的快照
UPDATE public.orders o
SET applicable_store_ids = sub.store_ids
FROM (
  SELECT das.deal_id, array_agg(das.store_id) AS store_ids
  FROM public.deal_applicable_stores das
  WHERE das.status = 'active'
  GROUP BY das.deal_id
) sub
WHERE o.deal_id = sub.deal_id
  AND o.applicable_store_ids IS NULL;

-- 对于没有 deal_applicable_stores 记录的历史订单，用 deal 的 merchant_id 回填
UPDATE public.orders o
SET applicable_store_ids = ARRAY[d.merchant_id]
FROM public.deals d
WHERE o.deal_id = d.id
  AND o.applicable_store_ids IS NULL;

-- 5. 索引：加速按门店查询订单
CREATE INDEX idx_orders_applicable_store_ids
ON public.orders USING GIN (applicable_store_ids);
