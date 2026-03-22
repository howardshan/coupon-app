-- =============================================================
-- Migration: phase5_cron_jobs
-- Phase 5 Cron Job 定时任务注册
--
-- 新增 4 个 pg_cron 定时任务：
--   1. notify-expiring-coupons  — 每日 UTC 14:00（US Central 09:00）
--   2. notify-expiring-deals    — 每日 UTC 14:00（US Central 09:00）
--   3. admin-daily-digest       — 每日 UTC 08:00（US Central 03:00）
--   4. monthly-settlement-report — 每月 1 日 UTC 02:00
--
-- 依赖：
--   - pg_cron 扩展（Supabase 默认已启用）
--   - pg_net 扩展（Supabase 默认已启用）
--   - vault secrets: supabase_url, cron_secret
--   - 上述 4 个 Edge Functions 已部署
-- =============================================================

-- ─────────────────────────────────────────────────────────────
-- 1. notify-expiring-coupons（每日 UTC 14:00）
-- ─────────────────────────────────────────────────────────────
SELECT cron.unschedule('notify-expiring-coupons-daily')
WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'notify-expiring-coupons-daily'
);

SELECT cron.schedule(
  'notify-expiring-coupons-daily',
  '0 14 * * *',
  $$
  SELECT net.http_post(
    url := (
      SELECT decrypted_secret FROM vault.decrypted_secrets
      WHERE name = 'supabase_url' LIMIT 1
    ) || '/functions/v1/notify-expiring-coupons',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (
        SELECT decrypted_secret FROM vault.decrypted_secrets
        WHERE name = 'cron_secret' LIMIT 1
      )
    ),
    body := '{}'::jsonb
  ) AS request_id;
  $$
);

-- ─────────────────────────────────────────────────────────────
-- 2. notify-expiring-deals（每日 UTC 14:00）
-- ─────────────────────────────────────────────────────────────
SELECT cron.unschedule('notify-expiring-deals-daily')
WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'notify-expiring-deals-daily'
);

SELECT cron.schedule(
  'notify-expiring-deals-daily',
  '0 14 * * *',
  $$
  SELECT net.http_post(
    url := (
      SELECT decrypted_secret FROM vault.decrypted_secrets
      WHERE name = 'supabase_url' LIMIT 1
    ) || '/functions/v1/notify-expiring-deals',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (
        SELECT decrypted_secret FROM vault.decrypted_secrets
        WHERE name = 'cron_secret' LIMIT 1
      )
    ),
    body := '{}'::jsonb
  ) AS request_id;
  $$
);

-- ─────────────────────────────────────────────────────────────
-- 3. admin-daily-digest（每日 UTC 08:00）
-- ─────────────────────────────────────────────────────────────
SELECT cron.unschedule('admin-daily-digest')
WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'admin-daily-digest'
);

SELECT cron.schedule(
  'admin-daily-digest',
  '0 8 * * *',
  $$
  SELECT net.http_post(
    url := (
      SELECT decrypted_secret FROM vault.decrypted_secrets
      WHERE name = 'supabase_url' LIMIT 1
    ) || '/functions/v1/admin-daily-digest',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (
        SELECT decrypted_secret FROM vault.decrypted_secrets
        WHERE name = 'cron_secret' LIMIT 1
      )
    ),
    body := '{}'::jsonb
  ) AS request_id;
  $$
);

-- ─────────────────────────────────────────────────────────────
-- 4. monthly-settlement-report（每月 1 日 UTC 02:00）
-- ─────────────────────────────────────────────────────────────
SELECT cron.unschedule('monthly-settlement-report')
WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'monthly-settlement-report'
);

SELECT cron.schedule(
  'monthly-settlement-report',
  '0 2 1 * *',
  $$
  SELECT net.http_post(
    url := (
      SELECT decrypted_secret FROM vault.decrypted_secrets
      WHERE name = 'supabase_url' LIMIT 1
    ) || '/functions/v1/monthly-settlement-report',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (
        SELECT decrypted_secret FROM vault.decrypted_secrets
        WHERE name = 'cron_secret' LIMIT 1
      )
    ),
    body := '{}'::jsonb
  ) AS request_id;
  $$
);

-- =============================================================
-- 备注：若 vault 未配置，可在 Supabase Dashboard SQL Editor 执行：
--
-- SELECT cron.schedule(
--   'notify-expiring-coupons-daily', '0 14 * * *',
--   $$ SELECT net.http_post(
--     url := 'https://kqyolvmgrdekybjrwizx.supabase.co/functions/v1/notify-expiring-coupons',
--     headers := '{"Content-Type":"application/json","x-cron-secret":"<YOUR_CRON_SECRET>"}'::jsonb,
--     body := '{}'::jsonb
--   ); $$
-- );
-- （其他 3 个任务类似，替换 function name 和 cron expression 即可）
-- =============================================================
