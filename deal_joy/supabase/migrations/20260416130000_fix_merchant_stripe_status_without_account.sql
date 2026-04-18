-- 修复脏数据：stripe_account_id 已空但状态仍为 connected，导致客户端与 merchant-withdrawal 不一致

UPDATE public.merchants
SET
  stripe_account_status = 'not_connected',
  updated_at = now()
WHERE stripe_account_id IS NULL
  AND stripe_account_status = 'connected';
