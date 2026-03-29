-- ============================================================
-- 修复 get_deal_remaining_stock：
-- COALESCE(customer_status, 'active') 会触发 enum 类型校验错误
-- 改用 IS NULL OR != 写法
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_deal_remaining_stock(p_deal_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_stock_limit integer;
  v_sold_count  integer;
BEGIN
  -- 获取该 deal 的总库存上限
  SELECT stock_limit INTO v_stock_limit
  FROM public.deals
  WHERE id = p_deal_id;

  -- 无库存限制时返回大数（不限制）
  IF v_stock_limit IS NULL OR v_stock_limit <= 0 THEN
    RETURN 99999;
  END IF;

  -- 统计已售出且未退款的 order_items 数量（每行 = 1 份 deal）
  -- customer_status IS NULL 表示新购未处理状态，也算已售；不能用 COALESCE 赋 enum 字面量
  SELECT COUNT(*) INTO v_sold_count
  FROM public.order_items oi
  WHERE oi.deal_id = p_deal_id
    AND (oi.customer_status IS NULL OR oi.customer_status::text != 'refund_success');

  RETURN GREATEST(0, v_stock_limit - v_sold_count);
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_deal_remaining_stock(uuid)
  TO authenticated;
