-- =============================================================
-- DealJoy Deal管理 Migration
-- 为 deals 表添加商家端所需字段
-- 新建 deal_images 表
-- 添加 RLS 策略 和 toggle_deal_status 函数
-- =============================================================

-- -------------------------------------------------------------
-- 1. 为 deals 表补充商家端必需字段
--    原有字段: id, merchant_id, title, description, category,
--    original_price, discount_price, discount_percent(generated),
--    image_urls, stock_limit, total_sold, rating, review_count,
--    is_featured, is_active, refund_policy, lat, lng, address,
--    discount_label, dishes, merchant_hours, expires_at,
--    created_at, updated_at
-- -------------------------------------------------------------

-- 1.1 使用规则: 可用星期（如 ["Mon","Tue","Wed"]，空数组=全周可用）
ALTER TABLE public.deals
  ADD COLUMN IF NOT EXISTS usage_days text[] NOT NULL DEFAULT '{}';

-- 1.2 每人限用数量（NULL 表示不限制）
ALTER TABLE public.deals
  ADD COLUMN IF NOT EXISTS max_per_person integer DEFAULT NULL;

-- 1.3 是否可叠加其他优惠
ALTER TABLE public.deals
  ADD COLUMN IF NOT EXISTS is_stackable boolean NOT NULL DEFAULT true;

-- 1.4 有效期类型: "fixed_date" 或 "days_after_purchase"
ALTER TABLE public.deals
  ADD COLUMN IF NOT EXISTS validity_type text NOT NULL DEFAULT 'fixed_date'
  CONSTRAINT deals_validity_type_check
    CHECK (validity_type IN ('fixed_date', 'days_after_purchase'));

-- 1.5 购买后有效天数（validity_type = 'days_after_purchase' 时使用）
ALTER TABLE public.deals
  ADD COLUMN IF NOT EXISTS validity_days integer DEFAULT NULL
  CONSTRAINT deals_validity_days_check
    CHECK (validity_days IS NULL OR validity_days BETWEEN 1 AND 365);

-- 1.6 审核拒绝原因（平台运营填写）
ALTER TABLE public.deals
  ADD COLUMN IF NOT EXISTS review_notes text DEFAULT NULL;

-- 1.7 首次上架时间戳
ALTER TABLE public.deals
  ADD COLUMN IF NOT EXISTS published_at timestamptz DEFAULT NULL;

-- 1.8 Deal审核状态（区分于 is_active 的展示状态）
--     pending: 待审核, active: 已上架, inactive: 已下架, rejected: 已拒绝
ALTER TABLE public.deals
  ADD COLUMN IF NOT EXISTS deal_status text NOT NULL DEFAULT 'pending'
  CONSTRAINT deals_deal_status_check
    CHECK (deal_status IN ('pending', 'active', 'inactive', 'rejected'));

-- 1.9 套餐包含内容（详细说明套餐内的菜品/服务）
ALTER TABLE public.deals
  ADD COLUMN IF NOT EXISTS package_contents text NOT NULL DEFAULT '';

-- 1.10 使用须知（消费者须知，英文）
ALTER TABLE public.deals
  ADD COLUMN IF NOT EXISTS usage_notes text NOT NULL DEFAULT '';

-- 有效期类型索引（筛选购买后X天类型的过期任务用）
CREATE INDEX IF NOT EXISTS idx_deals_validity_type
  ON public.deals(validity_type);

-- deal_status 索引（列表筛选用）
CREATE INDEX IF NOT EXISTS idx_deals_deal_status
  ON public.deals(deal_status);

-- -------------------------------------------------------------
-- 2. 新建 deal_images 表
--    存储 Deal 图片（文件本体存 Supabase Storage bucket: deal-images）
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.deal_images (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  deal_id     uuid        NOT NULL REFERENCES public.deals(id) ON DELETE CASCADE,
  image_url   text        NOT NULL,     -- Supabase Storage public URL
  sort_order  int         NOT NULL DEFAULT 0,
  is_primary  boolean     NOT NULL DEFAULT false,  -- true = 第一张/封面图
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- 按 deal_id 查询索引
CREATE INDEX IF NOT EXISTS idx_deal_images_deal_id
  ON public.deal_images(deal_id);

-- 确保每个 deal 只有一张主图（通过 partial unique index）
CREATE UNIQUE INDEX IF NOT EXISTS idx_deal_images_primary
  ON public.deal_images(deal_id)
  WHERE is_primary = true;

-- 按 sort_order 查询索引
CREATE INDEX IF NOT EXISTS idx_deal_images_sort
  ON public.deal_images(deal_id, sort_order);

-- -------------------------------------------------------------
-- 3. RLS: deal_images 表
-- -------------------------------------------------------------
ALTER TABLE public.deal_images ENABLE ROW LEVEL SECURITY;

-- 商家查看自己 deal 的图片
CREATE POLICY "deal_images_select_own"
  ON public.deal_images
  FOR SELECT
  USING (
    deal_id IN (
      SELECT d.id FROM public.deals d
      JOIN public.merchants m ON m.id = d.merchant_id
      WHERE m.user_id = auth.uid()
    )
  );

-- 用户端（已登录用户）可查看 active deal 的图片
CREATE POLICY "deal_images_select_active"
  ON public.deal_images
  FOR SELECT
  USING (
    deal_id IN (
      SELECT id FROM public.deals WHERE is_active = true
    )
  );

-- 商家插入自己 deal 的图片
CREATE POLICY "deal_images_insert_own"
  ON public.deal_images
  FOR INSERT
  WITH CHECK (
    deal_id IN (
      SELECT d.id FROM public.deals d
      JOIN public.merchants m ON m.id = d.merchant_id
      WHERE m.user_id = auth.uid()
    )
  );

-- 商家更新自己 deal 的图片（如修改 sort_order / is_primary）
CREATE POLICY "deal_images_update_own"
  ON public.deal_images
  FOR UPDATE
  USING (
    deal_id IN (
      SELECT d.id FROM public.deals d
      JOIN public.merchants m ON m.id = d.merchant_id
      WHERE m.user_id = auth.uid()
    )
  );

-- 商家删除自己 deal 的图片
CREATE POLICY "deal_images_delete_own"
  ON public.deal_images
  FOR DELETE
  USING (
    deal_id IN (
      SELECT d.id FROM public.deals d
      JOIN public.merchants m ON m.id = d.merchant_id
      WHERE m.user_id = auth.uid()
    )
  );

-- -------------------------------------------------------------
-- 4. 补充 deals 表的商家端 RLS 策略
--    注意: initial_schema.sql 已有:
--    - deals_read_active (is_active = true, 公开)
--    - deals_merchant_manage (merchant_id in own merchants, ALL)
--    以下策略按操作类型细化（如已有 manage 策略，下面为补充说明）
-- -------------------------------------------------------------

-- 商家可查看自己所有状态的 deal（包括 pending/rejected/inactive）
-- initial_schema 的 deals_merchant_manage 已覆盖，但其 SELECT 不含 is_active=false 的情况
-- 若 deals_merchant_manage 用 ALL，Supabase 需要同时满足 USING，
-- 补充一条明确的 SELECT 策略
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'deals' AND policyname = 'deals_merchant_select_own'
  ) THEN
    EXECUTE $policy$
      CREATE POLICY "deals_merchant_select_own"
        ON public.deals
        FOR SELECT
        USING (
          merchant_id IN (
            SELECT id FROM public.merchants WHERE user_id = auth.uid()
          )
        )
    $policy$;
  END IF;
END
$$;

-- 商家只能插入绑定自己 merchant_id 的 deal
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'deals' AND policyname = 'deals_merchant_insert_own'
  ) THEN
    EXECUTE $policy$
      CREATE POLICY "deals_merchant_insert_own"
        ON public.deals
        FOR INSERT
        WITH CHECK (
          merchant_id IN (
            SELECT id FROM public.merchants WHERE user_id = auth.uid()
          )
        )
    $policy$;
  END IF;
END
$$;

-- 商家只能更新自己的 deal
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'deals' AND policyname = 'deals_merchant_update_own'
  ) THEN
    EXECUTE $policy$
      CREATE POLICY "deals_merchant_update_own"
        ON public.deals
        FOR UPDATE
        USING (
          merchant_id IN (
            SELECT id FROM public.merchants WHERE user_id = auth.uid()
          )
        )
    $policy$;
  END IF;
END
$$;

-- 商家只能删除自己的 inactive deal
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'deals' AND policyname = 'deals_merchant_delete_own'
  ) THEN
    EXECUTE $policy$
      CREATE POLICY "deals_merchant_delete_own"
        ON public.deals
        FOR DELETE
        USING (
          merchant_id IN (
            SELECT id FROM public.merchants WHERE user_id = auth.uid()
          )
          AND deal_status = 'inactive'
        )
    $policy$;
  END IF;
END
$$;

-- -------------------------------------------------------------
-- 5. toggle_deal_status 函数
--    由 Edge Function 调用，验证所有权后切换上下架状态
--    p_deal_id: 要操作的 deal ID
--    p_is_active: true=上架(active), false=下架(inactive)
--    返回: updated deal_status
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.toggle_deal_status(
  p_deal_id   uuid,
  p_is_active boolean
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_merchant_id uuid;
  v_current_status text;
  v_new_status text;
BEGIN
  -- 查询当前 deal 状态和所属商家
  SELECT d.merchant_id, d.deal_status
  INTO v_merchant_id, v_current_status
  FROM public.deals d
  WHERE d.id = p_deal_id;

  -- deal 不存在
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Deal not found: %', p_deal_id;
  END IF;

  -- 验证调用者是该 deal 的商家
  IF v_merchant_id NOT IN (
    SELECT id FROM public.merchants WHERE user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Access denied: not your deal';
  END IF;

  -- pending / rejected 状态不允许商家手动上架
  IF p_is_active AND v_current_status IN ('pending', 'rejected') THEN
    RAISE EXCEPTION 'Cannot activate deal with status: %', v_current_status;
  END IF;

  -- 确定新状态
  v_new_status := CASE WHEN p_is_active THEN 'active' ELSE 'inactive' END;

  -- 更新状态
  UPDATE public.deals
  SET
    deal_status  = v_new_status,
    is_active    = p_is_active,
    published_at = CASE
                     WHEN p_is_active AND published_at IS NULL THEN now()
                     ELSE published_at
                   END,
    updated_at   = now()
  WHERE id = p_deal_id;

  RETURN v_new_status;
END;
$$;

-- -------------------------------------------------------------
-- 6. 自动更新 updated_at 触发器（如果 deals 表还没有）
-- -------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'deals_updated_at' AND tgrelid = 'public.deals'::regclass
  ) THEN
    -- 确保 update_updated_at_column 函数存在
    PERFORM proname FROM pg_proc WHERE proname = 'update_updated_at_column';
    IF FOUND THEN
      EXECUTE $trig$
        CREATE TRIGGER deals_updated_at
          BEFORE UPDATE ON public.deals
          FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column()
      $trig$;
    END IF;
  END IF;
EXCEPTION
  WHEN OTHERS THEN
    -- 触发器可能已存在，忽略错误
    NULL;
END
$$;
