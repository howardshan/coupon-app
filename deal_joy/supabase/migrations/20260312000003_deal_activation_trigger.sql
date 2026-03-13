-- ============================================================
-- Deal 激活触发器：当 deal_status 变为 'active' 时，自动写入 deal_applicable_stores
-- 同时新增 store_confirmations 字段，用于品牌管理员在创建时记录预确认状态
-- ============================================================

-- 1. deals 表新增 store_confirmations 字段
--    格式（brand_multi_store）：[{"store_id": "uuid", "pre_confirmed": true/false}, ...]
--    store_only deal 保持 NULL，触发器会自动写一条 active 记录
ALTER TABLE public.deals
  ADD COLUMN IF NOT EXISTS store_confirmations JSONB DEFAULT NULL;

-- 2. 触发器函数：deal 审核通过（deal_status → active）时自动创建门店记录
CREATE OR REPLACE FUNCTION public.handle_deal_activation()
RETURNS TRIGGER AS $$
DECLARE
  v_confirmation  JSONB;
  v_store_id      UUID;
  v_pre_confirmed BOOLEAN;
BEGIN
  -- 只在 deal_status 从非 active 变为 active 时触发
  IF (OLD.deal_status IS DISTINCT FROM 'active') AND NEW.deal_status = 'active' THEN

    IF NEW.store_confirmations IS NULL THEN
      -- store_only deal：仅为创建门店写一条 active 记录
      INSERT INTO public.deal_applicable_stores (
        deal_id, store_id, deal_scope, status, created_at
      )
      VALUES (
        NEW.id,
        NEW.merchant_id,
        'store_only',
        'active',
        NOW()
      )
      ON CONFLICT (deal_id, store_id) DO NOTHING;

    ELSE
      -- brand_multi_store deal：按 store_confirmations 逐店创建记录
      FOR v_confirmation IN
        SELECT * FROM jsonb_array_elements(NEW.store_confirmations)
      LOOP
        v_store_id      := (v_confirmation->>'store_id')::UUID;
        v_pre_confirmed := COALESCE((v_confirmation->>'pre_confirmed')::BOOLEAN, FALSE);

        INSERT INTO public.deal_applicable_stores (
          deal_id, store_id, deal_scope, status, confirmed_at, created_at
        )
        VALUES (
          NEW.id,
          v_store_id,
          'brand_multi_store',
          CASE WHEN v_pre_confirmed
            THEN 'active'::deal_store_status
            ELSE 'pending_store_confirmation'::deal_store_status
          END,
          CASE WHEN v_pre_confirmed THEN NOW() ELSE NULL END,
          NOW()
        )
        ON CONFLICT (deal_id, store_id) DO NOTHING;
      END LOOP;

    END IF;

  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. 创建触发器
DROP TRIGGER IF EXISTS on_deal_activated ON public.deals;
CREATE TRIGGER on_deal_activated
  AFTER UPDATE ON public.deals
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_deal_activation();

-- 4. 辅助函数：门店 Accept Deal（更新 deal_applicable_stores）
--    返回操作后 active 门店数
CREATE OR REPLACE FUNCTION public.accept_deal_store(
  p_deal_id        UUID,
  p_store_id       UUID,
  p_user_id        UUID,
  p_menu_item_id   UUID DEFAULT NULL,
  p_store_original_price NUMERIC DEFAULT NULL
)
RETURNS INT AS $$
DECLARE
  v_active_count INT;
BEGIN
  -- 更新记录为 active
  UPDATE public.deal_applicable_stores
  SET
    status               = 'active',
    menu_item_id         = p_menu_item_id,
    store_original_price = p_store_original_price,
    confirmed_by         = p_user_id,
    confirmed_at         = NOW()
  WHERE deal_id  = p_deal_id
    AND store_id = p_store_id
    AND status   = 'pending_store_confirmation';

  -- 返回当前 active 门店数
  SELECT COUNT(*) INTO v_active_count
  FROM public.deal_applicable_stores
  WHERE deal_id = p_deal_id AND status = 'active';

  RETURN v_active_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. 辅助函数：门店 Decline Deal
CREATE OR REPLACE FUNCTION public.decline_deal_store(
  p_deal_id  UUID,
  p_store_id UUID,
  p_user_id  UUID
)
RETURNS VOID AS $$
BEGIN
  UPDATE public.deal_applicable_stores
  SET
    status       = 'declined',
    confirmed_by = p_user_id,
    confirmed_at = NOW()
  WHERE deal_id  = p_deal_id
    AND store_id = p_store_id
    AND status   = 'pending_store_confirmation';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6. 辅助函数：门店退出 Deal（主动或被踢出）
CREATE OR REPLACE FUNCTION public.remove_deal_store(
  p_deal_id  UUID,
  p_store_id UUID,
  p_user_id  UUID
)
RETURNS INT AS $$
DECLARE
  v_active_count INT;
BEGIN
  UPDATE public.deal_applicable_stores
  SET
    status     = 'removed',
    removed_by = p_user_id,
    removed_at = NOW()
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

-- 7. 授权
GRANT EXECUTE ON FUNCTION public.accept_deal_store(UUID, UUID, UUID, UUID, NUMERIC)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.decline_deal_store(UUID, UUID, UUID)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.remove_deal_store(UUID, UUID, UUID)
  TO authenticated;
