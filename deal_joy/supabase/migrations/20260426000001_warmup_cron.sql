-- 每 4 分钟 ping 核心 Edge Functions，防止 Deno isolate 冷启动
-- Supabase 的 Edge Function 空闲约 5 分钟后进入休眠，每次唤醒需 3-8s（冷启动）
-- 通过 pg_cron + pg_net 定时发送 x-warmup 请求，把冷启动开销转移到 cron 任务上

-- 启用扩展（Supabase 项目默认已有，安全地 IF NOT EXISTS）
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

-- 清理旧任务（允许重复执行 migration）
SELECT cron.unschedule('warmup-create-payment-intent') WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'warmup-create-payment-intent'
);
SELECT cron.unschedule('warmup-create-order-v3') WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'warmup-create-order-v3'
);
SELECT cron.unschedule('warmup-create-refund') WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'warmup-create-refund'
);

-- warmup create-payment-intent（每 4 分钟）
SELECT cron.schedule(
  'warmup-create-payment-intent',
  '*/4 * * * *',
  $$
  SELECT net.http_post(
    url     := 'https://kqyolvmgrdekybjrwizx.supabase.co/functions/v1/create-payment-intent',
    headers := jsonb_build_object(
      'Content-Type',   'application/json',
      'Authorization',  'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtxeW9sdm1ncmRla3lianJ3aXp4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzIzMTk2NTksImV4cCI6MjA4Nzg5NTY1OX0.1edjpxO5lT191vv2tjVc25EcXHf6cEJkc0lL4QyXV8k',
      'x-warmup',       'true'
    ),
    body    := '{}'::jsonb
  ) AS request_id;
  $$
);

-- warmup create-order-v3（每 4 分钟，错开 1 分钟）
SELECT cron.schedule(
  'warmup-create-order-v3',
  '1-59/4 * * * *',
  $$
  SELECT net.http_post(
    url     := 'https://kqyolvmgrdekybjrwizx.supabase.co/functions/v1/create-order-v3',
    headers := jsonb_build_object(
      'Content-Type',   'application/json',
      'Authorization',  'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtxeW9sdm1ncmRla3lianJ3aXp4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzIzMTk2NTksImV4cCI6MjA4Nzg5NTY1OX0.1edjpxO5lT191vv2tjVc25EcXHf6cEJkc0lL4QyXV8k',
      'x-warmup',       'true'
    ),
    body    := '{}'::jsonb
  ) AS request_id;
  $$
);

-- warmup create-refund（每 4 分钟，错开 2 分钟）
SELECT cron.schedule(
  'warmup-create-refund',
  '2-59/4 * * * *',
  $$
  SELECT net.http_post(
    url     := 'https://kqyolvmgrdekybjrwizx.supabase.co/functions/v1/create-refund',
    headers := jsonb_build_object(
      'Content-Type',   'application/json',
      'Authorization',  'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtxeW9sdm1ncmRla3lianJ3aXp4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzIzMTk2NTksImV4cCI6MjA4Nzg5NTY1OX0.1edjpxO5lT191vv2tjVc25EcXHf6cEJkc0lL4QyXV8k',
      'x-warmup',       'true'
    ),
    body    := '{}'::jsonb
  ) AS request_id;
  $$
);
