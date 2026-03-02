-- =============================================================
-- Migration: 新增促销码（Promo Codes）表
-- 用于结账时用户输入促销码享受折扣
-- =============================================================

-- -------------------------------------------------------------
-- 创建 promo_codes 表
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.promo_codes (
  id               UUID         PRIMARY KEY DEFAULT gen_random_uuid(),

  -- 促销码字符串，如 "WELCOME10"，全库唯一、不区分大小写存储时建议统一大写
  code             TEXT         NOT NULL UNIQUE,

  -- 折扣类型：percentage（百分比）或 fixed（固定金额）
  discount_type    TEXT         NOT NULL CHECK (discount_type IN ('percentage', 'fixed')),

  -- 折扣数值：percentage 时为 0-100 的百分比，fixed 时为正数美元金额
  -- P0 fix: CHECK 防止负值或零值折扣被用于绕过价格校验
  discount_value   NUMERIC(10,2) NOT NULL CHECK (discount_value > 0),

  -- percentage 类型时额外约束上限为 100%
  -- (handled via trigger below since CHECK can't reference another column easily)

  -- 使用门槛：订单小计须达到此金额才可使用，默认 0（无门槛）
  min_order_amount NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (min_order_amount >= 0),

  -- 最高折扣上限：仅 percentage 类型有意义，null 表示无上限
  max_discount     NUMERIC(10,2) CHECK (max_discount IS NULL OR max_discount > 0),

  -- 最大使用总次数，null 表示不限次数
  max_uses         INT CHECK (max_uses IS NULL OR max_uses > 0),

  -- 当前已使用次数；P0 fix: CHECK 防止并发问题导致变负
  current_uses     INT          NOT NULL DEFAULT 0 CHECK (current_uses >= 0),

  -- 关联特定 deal（null 表示适用于所有 deal）
  deal_id          UUID         REFERENCES public.deals(id) ON DELETE SET NULL,

  -- 过期时间，null 表示永不过期
  expires_at       TIMESTAMPTZ,

  -- 是否启用
  is_active        BOOLEAN      NOT NULL DEFAULT true,

  created_at       TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- -------------------------------------------------------------
-- 索引
-- -------------------------------------------------------------
-- 用户结账时按 code 查找，最高频操作
CREATE INDEX IF NOT EXISTS idx_promo_codes_code
  ON public.promo_codes (code);

-- 按特定 deal 过滤促销码
CREATE INDEX IF NOT EXISTS idx_promo_codes_deal_id
  ON public.promo_codes (deal_id);

-- 管理后台按启用状态筛选
CREATE INDEX IF NOT EXISTS idx_promo_codes_is_active
  ON public.promo_codes (is_active);

-- P0 fix: 校验 percentage 类型的折扣值不超过 100%
CREATE OR REPLACE FUNCTION public.check_promo_code_discount_value()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.discount_type = 'percentage' AND NEW.discount_value > 100 THEN
    RAISE EXCEPTION 'percentage discount_value cannot exceed 100, got %', NEW.discount_value;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_promo_codes_discount_value
  BEFORE INSERT OR UPDATE ON public.promo_codes
  FOR EACH ROW EXECUTE FUNCTION public.check_promo_code_discount_value();

-- P0 fix: 原子递增 current_uses，防止并发竞态（多个用户同时使用同一优惠码时
-- 客户端 read-then-write 模式会导致计数不准确，甚至超过 max_uses）。
-- 调用方：checkout 完成后由 Edge Function 或服务端调用。
-- 返回 true 表示递增成功，false 表示已达上限或码不存在/未激活。
CREATE OR REPLACE FUNCTION public.increment_promo_code_uses(p_code TEXT)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_max_uses    INT;
  v_current     INT;
  v_rows_updated INT;
BEGIN
  -- 加行锁，防止并发冲突
  SELECT max_uses, current_uses
    INTO v_max_uses, v_current
    FROM public.promo_codes
    WHERE code = p_code AND is_active = true
    FOR UPDATE;

  IF NOT FOUND THEN
    RETURN FALSE;
  END IF;

  IF v_max_uses IS NOT NULL AND v_current >= v_max_uses THEN
    RETURN FALSE;
  END IF;

  UPDATE public.promo_codes
    SET current_uses = current_uses + 1
    WHERE code = p_code;

  RETURN TRUE;
END;
$$;

-- 仅允许已认证用户调用（service_role 也可调用，RLS 不限制函数）
REVOKE ALL ON FUNCTION public.increment_promo_code_uses(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.increment_promo_code_uses(TEXT) TO service_role;

-- -------------------------------------------------------------
-- Row Level Security
-- -------------------------------------------------------------
ALTER TABLE public.promo_codes ENABLE ROW LEVEL SECURITY;

-- 所有已登录用户可查询启用中的促销码（结账验证需要）
CREATE POLICY "promo_codes_select_active" ON public.promo_codes
  FOR SELECT
  TO authenticated
  USING (is_active = true);

-- INSERT / UPDATE / DELETE 仅允许 service_role（管理员通过后台或 Edge Function 操作）
-- Supabase 中 service_role 默认绕过 RLS，此处不需要额外策略；
-- 为明确表达意图，禁止普通用户写操作（无写策略即等同于拒绝）

-- -------------------------------------------------------------
-- 种子数据：示例促销码
-- -------------------------------------------------------------

-- WELCOME10：新用户欢迎码，享 10% 折扣，最高优惠 $5，不限使用次数
INSERT INTO public.promo_codes
  (code, discount_type, discount_value, min_order_amount, max_discount, max_uses, expires_at)
VALUES
  ('WELCOME10', 'percentage', 10.00, 0.00, 5.00, NULL, NULL);

-- SAVE5：满 $20 减 $5，固定金额折扣
INSERT INTO public.promo_codes
  (code, discount_type, discount_value, min_order_amount, max_discount, max_uses, expires_at)
VALUES
  ('SAVE5', 'fixed', 5.00, 20.00, NULL, NULL, NULL);

-- FIRST20：首单专属 20% 折扣，最高优惠 $10，全平台限用 100 次
INSERT INTO public.promo_codes
  (code, discount_type, discount_value, min_order_amount, max_discount, max_uses, expires_at)
VALUES
  ('FIRST20', 'percentage', 20.00, 0.00, 10.00, 100, NULL);
