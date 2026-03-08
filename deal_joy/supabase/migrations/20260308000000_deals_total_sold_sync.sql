-- =============================================================
-- deals.total_sold 与订单同步
-- 1. 订单插入时：deals.total_sold += order.quantity
-- 2. 订单状态变为 refunded 时：deals.total_sold -= order.quantity
-- 3. 一次性按当前 orders 数据回填所有 deal 的 total_sold
-- =============================================================

-- 1. 订单插入时增加对应 deal 的 total_sold
CREATE OR REPLACE FUNCTION public.sync_deal_total_sold_on_order_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.deals
  SET total_sold = total_sold + NEW.quantity,
      updated_at = now()
  WHERE id = NEW.deal_id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_deal_total_sold_insert ON public.orders;
CREATE TRIGGER trg_sync_deal_total_sold_insert
  AFTER INSERT ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_deal_total_sold_on_order_insert();

-- 2. 订单状态变为 refunded 时减少对应 deal 的 total_sold
CREATE OR REPLACE FUNCTION public.sync_deal_total_sold_on_order_refund()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF OLD.status IS DISTINCT FROM 'refunded' AND NEW.status = 'refunded' THEN
    UPDATE public.deals
    SET total_sold = GREATEST(0, total_sold - NEW.quantity),
        updated_at = now()
    WHERE id = NEW.deal_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_deal_total_sold_refund ON public.orders;
CREATE TRIGGER trg_sync_deal_total_sold_refund
  AFTER UPDATE ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_deal_total_sold_on_order_refund();

-- 3. 一次性回填：按当前订单（非退款）汇总每个 deal 的 total_sold
UPDATE public.deals d
SET total_sold = COALESCE((
  SELECT SUM(o.quantity)::int
  FROM public.orders o
  WHERE o.deal_id = d.id AND o.status != 'refunded'
), 0),
updated_at = now();
