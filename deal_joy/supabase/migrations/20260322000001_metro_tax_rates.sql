-- metro_tax_rates: 按 metro 区域设置税率
-- merchants 添加 metro_area 字段
-- orders / order_items 添加 tax 字段

-- 1. 创建 metro_tax_rates 表
CREATE TABLE IF NOT EXISTS public.metro_tax_rates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  metro_area text NOT NULL UNIQUE,
  tax_rate numeric(6, 4) NOT NULL DEFAULT 0,  -- 如 0.0825 = 8.25%
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- RLS: 所有人可读，仅 admin 可写
ALTER TABLE public.metro_tax_rates ENABLE ROW LEVEL SECURITY;

CREATE POLICY "metro_tax_rates_read_all" ON public.metro_tax_rates
  FOR SELECT USING (true);

CREATE POLICY "metro_tax_rates_admin_write" ON public.metro_tax_rates
  FOR ALL USING (public.is_admin());

-- 2. merchants 添加 metro_area 字段
ALTER TABLE public.merchants ADD COLUMN IF NOT EXISTS metro_area text;
CREATE INDEX IF NOT EXISTS idx_merchants_metro_area ON public.merchants (metro_area);

-- 3. orders 添加 tax 字段
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS tax_amount numeric(10, 2) NOT NULL DEFAULT 0;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS tax_rate numeric(6, 4);

-- 4. order_items 添加 tax 字段
ALTER TABLE public.order_items ADD COLUMN IF NOT EXISTS tax_amount numeric(10, 2) NOT NULL DEFAULT 0;
ALTER TABLE public.order_items ADD COLUMN IF NOT EXISTS tax_rate numeric(6, 4);

-- 5. 插入 Dallas metro 默认税率（Texas sales tax 8.25%）
INSERT INTO public.metro_tax_rates (metro_area, tax_rate)
VALUES ('Dallas', 0.0825)
ON CONFLICT (metro_area) DO NOTHING;
