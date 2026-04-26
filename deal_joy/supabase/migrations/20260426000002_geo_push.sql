-- ============================================================
-- Geo Push Notifications
-- 1. users 表增加位置字段（App 登录时写入）
-- 2. push_campaigns 表记录发送历史
-- 3. find_users_for_geo_push RPC 查找范围内用户
-- ============================================================

-- 1. users 表加字段
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS last_lat  double precision,
  ADD COLUMN IF NOT EXISTS last_lng  double precision,
  ADD COLUMN IF NOT EXISTS last_location_at timestamptz;

-- 空间索引（加速地理查询）
CREATE INDEX IF NOT EXISTS idx_users_location
  ON public.users (last_lat, last_lng)
  WHERE last_lat IS NOT NULL AND last_lng IS NOT NULL;

-- RLS：用户只能更新自己的位置
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'users' AND policyname = 'users can update own location'
  ) THEN
    CREATE POLICY "users can update own location" ON public.users FOR UPDATE USING (auth.uid() = id) WITH CHECK (auth.uid() = id);
  END IF;
END $$;

-- 2. push_campaigns 表
CREATE TABLE IF NOT EXISTS public.push_campaigns (
  id               uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  title            text        NOT NULL,
  body             text        NOT NULL,
  deal_id          uuid        REFERENCES public.deals(id) ON DELETE SET NULL,
  merchant_id      uuid        REFERENCES public.merchants(id) ON DELETE SET NULL,
  radius_meters    int         NOT NULL DEFAULT 40234,
  target_lat       double precision NOT NULL,
  target_lng       double precision NOT NULL,
  sent_user_count  int         NOT NULL DEFAULT 0,
  created_by       uuid        REFERENCES public.users(id) ON DELETE SET NULL,
  created_at       timestamptz NOT NULL DEFAULT now()
);

-- RLS：只有 admin 可读写 campaigns
ALTER TABLE public.push_campaigns ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'push_campaigns' AND policyname = 'admin can manage push_campaigns'
  ) THEN
    CREATE POLICY "admin can manage push_campaigns"
      ON public.push_campaigns
      FOR ALL
      USING (
        EXISTS (
          SELECT 1 FROM public.users
          WHERE id = auth.uid() AND role = 'admin'
        )
      );
  END IF;
END $$;

-- 3. RPC：找指定半径内有 FCM token 的用户
CREATE OR REPLACE FUNCTION find_users_for_geo_push(
  p_lat      double precision,
  p_lng      double precision,
  p_radius_m int DEFAULT 40234
)
RETURNS TABLE (user_id uuid)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT DISTINCT u.id
  FROM public.users u
  JOIN public.user_fcm_tokens t ON t.user_id = u.id
  WHERE
    u.last_lat IS NOT NULL
    AND u.last_lng IS NOT NULL
    AND (
      3958.8 * 2 * ASIN(SQRT(
        POWER(SIN(RADIANS((u.last_lat - p_lat) / 2)), 2) +
        COS(RADIANS(p_lat)) * COS(RADIANS(u.last_lat)) *
        POWER(SIN(RADIANS((u.last_lng - p_lng) / 2)), 2)
      )) * 1609.34
    ) <= p_radius_m;
$$;
