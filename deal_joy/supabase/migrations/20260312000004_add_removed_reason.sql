-- ============================================================
-- deal_applicable_stores 新增 removed_reason 字段
-- 区分"门店主动退出"(store_initiated) 和"被品牌踢出"(brand_kicked)
-- 同时重建 remove_deal_store() RPC 以接受新参数
-- ============================================================

-- 1. 创建退出原因枚举
CREATE TYPE deal_store_removed_reason AS ENUM (
  'store_initiated',   -- 门店主动退出
  'brand_kicked'       -- 被品牌踢出
);

-- 2. 添加字段（status 为 removed 时才有值）
ALTER TABLE public.deal_applicable_stores
  ADD COLUMN removed_reason deal_store_removed_reason DEFAULT NULL;

-- 3. 重建 remove_deal_store()：新增 p_removed_reason 参数（默认 store_initiated）
--    参数签名变了，必须 DROP 旧版本再 CREATE
DROP FUNCTION IF EXISTS public.remove_deal_store(UUID, UUID, UUID);

CREATE FUNCTION public.remove_deal_store(
  p_deal_id        UUID,
  p_store_id       UUID,
  p_user_id        UUID,
  p_removed_reason deal_store_removed_reason DEFAULT 'store_initiated'
)
RETURNS INT AS $$
DECLARE
  v_active_count INT;
BEGIN
  UPDATE public.deal_applicable_stores
  SET
    status         = 'removed',
    removed_by     = p_user_id,
    removed_at     = NOW(),
    removed_reason = p_removed_reason
  WHERE deal_id  = p_deal_id
    AND store_id = p_store_id
    AND status   IN ('active', 'pending_store_confirmation');

  -- 若退出后已无 active 门店，自动下架 Deal
  SELECT COUNT(*) INTO v_active_count
  FROM public.deal_applicable_stores
  WHERE deal_id = p_deal_id AND status = 'active';

  IF v_active_count = 0 THEN
    UPDATE public.deals
    SET is_active = false, deal_status = 'inactive', updated_at = NOW()
    WHERE id = p_deal_id AND is_active = true;
  END IF;

  RETURN v_active_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. 授权
GRANT EXECUTE ON FUNCTION public.remove_deal_store(UUID, UUID, UUID, deal_store_removed_reason)
  TO authenticated;
