-- =============================================================
-- Migration: auto_capture_preauth_cron
-- 为预授权自动 capture 添加 pg_cron 定时任务
--
-- 依赖：
--   - pg_cron 扩展（Supabase 默认已启用）
--   - pg_net 扩展（Supabase 默认已启用，用于 HTTP 调用）
--   - Edge Function: auto-capture-preauth（需已部署）
--   - 环境变量 CRON_SECRET 已在 Edge Function Secrets 中配置
--
-- 执行时机：每天 UTC 02:00（北京时间 10:00）
-- =============================================================

-- 若已存在同名 job 则先移除（幂等）
SELECT cron.unschedule('auto-capture-preauth-daily')
WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'auto-capture-preauth-daily'
);

-- 注册定时任务：每天 02:00 UTC 调用 Edge Function
-- 注意：SUPABASE_URL 和 CRON_SECRET 通过 app.settings 传入
-- 请在 Supabase Dashboard → Settings → API 中确认项目 URL
SELECT cron.schedule(
  'auto-capture-preauth-daily',
  '0 2 * * *',
  $$
  SELECT net.http_post(
    url := (
      SELECT decrypted_secret
      FROM vault.decrypted_secrets
      WHERE name = 'supabase_url'
      LIMIT 1
    ) || '/functions/v1/auto-capture-preauth',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (
        SELECT decrypted_secret
        FROM vault.decrypted_secrets
        WHERE name = 'cron_secret'
        LIMIT 1
      )
    ),
    body := '{}'::jsonb
  ) AS request_id;
  $$
);

-- =============================================================
-- 备注：若 vault 未配置 supabase_url / cron_secret，
-- 可在 Supabase Dashboard 手动添加 Cron Job：
--
--   1. 进入 Dashboard → Edge Functions → auto-capture-preauth
--   2. 点击 "Schedule" 标签
--   3. Cron Expression: 0 2 * * *
--   4. 在 Edge Function Secrets 中添加：
--      CRON_SECRET = <任意随机字符串>
--   5. Cron 调用时自动携带 x-cron-secret header
--
-- 或者直接在 SQL Editor 执行（将占位符替换为实际值）：
--
-- SELECT cron.schedule(
--   'auto-capture-preauth-daily',
--   '0 2 * * *',
--   $$
--   SELECT net.http_post(
--     url := 'https://kqyolvmgrdekybjrwizx.supabase.co/functions/v1/auto-capture-preauth',
--     headers := '{"Content-Type":"application/json","x-cron-secret":"<YOUR_CRON_SECRET>"}'::jsonb,
--     body := '{}'::jsonb
--   );
--   $$
-- );
-- =============================================================
