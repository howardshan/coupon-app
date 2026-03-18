-- =============================================================
-- Migration: add_order_status_enum_values
-- 为 orders.status enum 添加预授权 + 三级退款审批相关状态值
--
-- 背景：20260310000001_orders_preauth_support.sql 只加了 is_captured 列，
--       但遗漏了对 order_status enum 的修改，导致写入 'authorized' 时报错：
--       invalid input value for enum order_status: "authorized"
-- =============================================================

-- PostgreSQL 15+：ADD VALUE IF NOT EXISTS 可安全重复执行
ALTER TYPE public.order_status ADD VALUE IF NOT EXISTS 'authorized';
ALTER TYPE public.order_status ADD VALUE IF NOT EXISTS 'refund_pending_merchant';
ALTER TYPE public.order_status ADD VALUE IF NOT EXISTS 'refund_pending_admin';
ALTER TYPE public.order_status ADD VALUE IF NOT EXISTS 'refund_rejected';
