-- =============================================================
-- 闭店 / account-delete：merchants.status = 'closed'
-- 历史枚举仅有 pending | approved | rejected，与 Edge merchant-store/close 不一致
-- =============================================================

ALTER TYPE public.merchant_status ADD VALUE IF NOT EXISTS 'closed';
