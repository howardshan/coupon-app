-- ============================================================
-- RPC: get_deal_remaining_stock
-- 返回指定 deal 的剩余库存数量
-- SECURITY DEFINER 绕过 RLS，可从客户端安全调用
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
  -- customer_status IS NULL 表示新购未处理状态，也算已售
  SELECT COUNT(*) INTO v_sold_count
  FROM public.order_items oi
  JOIN public.orders o ON o.id = oi.order_id
  WHERE oi.deal_id = p_deal_id
    AND COALESCE(oi.customer_status, 'active') != 'refund_success';

  RETURN GREATEST(0, v_stock_limit - v_sold_count);
END;
$$;

-- 允许已登录用户调用
GRANT EXECUTE ON FUNCTION public.get_deal_remaining_stock(uuid)
  TO authenticated;
