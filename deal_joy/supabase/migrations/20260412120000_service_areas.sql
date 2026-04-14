-- ============================================================
-- service_areas: 地区管理表（State → Metro → City 三级结构）
-- 替代用户端硬编码的 _locationData，支持 Admin 端动态管理
-- ============================================================

-- 1. 建表
CREATE TABLE IF NOT EXISTS public.service_areas (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  level text NOT NULL CHECK (level IN ('state', 'metro', 'city')),
  state_name text NOT NULL,
  metro_name text,
  city_name text,
  sort_order int NOT NULL DEFAULT 0,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (state_name, metro_name, city_name)
);

-- 2. 索引
CREATE INDEX IF NOT EXISTS idx_service_areas_level_state
  ON public.service_areas (level, state_name, metro_name);

-- 3. RLS
ALTER TABLE public.service_areas ENABLE ROW LEVEL SECURITY;

-- 所有人可读（用户端需要加载地区列表）
CREATE POLICY "service_areas_select_all"
  ON public.service_areas FOR SELECT
  USING (true);

-- 仅 admin 可写
CREATE POLICY "service_areas_insert_admin"
  ON public.service_areas FOR INSERT
  WITH CHECK (
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );

CREATE POLICY "service_areas_update_admin"
  ON public.service_areas FOR UPDATE
  USING (
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );

CREATE POLICY "service_areas_delete_admin"
  ON public.service_areas FOR DELETE
  USING (
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );

-- 4. 种子数据：从现有硬编码 _locationData 迁移
-- State
INSERT INTO public.service_areas (level, state_name, metro_name, city_name, sort_order) VALUES
  ('state', 'Texas', NULL, NULL, 0)
ON CONFLICT DO NOTHING;

-- Metros
INSERT INTO public.service_areas (level, state_name, metro_name, city_name, sort_order) VALUES
  ('metro', 'Texas', 'DFW',     NULL, 0),
  ('metro', 'Texas', 'Austin',  NULL, 1),
  ('metro', 'Texas', 'Houston', NULL, 2)
ON CONFLICT DO NOTHING;

-- Cities - DFW
INSERT INTO public.service_areas (level, state_name, metro_name, city_name, sort_order) VALUES
  ('city', 'Texas', 'DFW', 'Dallas',      0),
  ('city', 'Texas', 'DFW', 'Richardson',  1),
  ('city', 'Texas', 'DFW', 'Plano',       2),
  ('city', 'Texas', 'DFW', 'Frisco',      3),
  ('city', 'Texas', 'DFW', 'Fairview',    4),
  ('city', 'Texas', 'DFW', 'McKinney',    5),
  ('city', 'Texas', 'DFW', 'Fort Worth',  6),
  ('city', 'Texas', 'DFW', 'Arlington',   7)
ON CONFLICT DO NOTHING;

-- Cities - Austin
INSERT INTO public.service_areas (level, state_name, metro_name, city_name, sort_order) VALUES
  ('city', 'Texas', 'Austin', 'Austin',     0),
  ('city', 'Texas', 'Austin', 'Round Rock', 1),
  ('city', 'Texas', 'Austin', 'Cedar Park', 2),
  ('city', 'Texas', 'Austin', 'Georgetown', 3)
ON CONFLICT DO NOTHING;

-- Cities - Houston
INSERT INTO public.service_areas (level, state_name, metro_name, city_name, sort_order) VALUES
  ('city', 'Texas', 'Houston', 'Houston',       0),
  ('city', 'Texas', 'Houston', 'The Woodlands', 1),
  ('city', 'Texas', 'Houston', 'Sugar Land',    2),
  ('city', 'Texas', 'Houston', 'Katy',          3)
ON CONFLICT DO NOTHING;
