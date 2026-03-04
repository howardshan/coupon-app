-- =============================================================
-- Migration: 退款系统支撑字段与权限配置
-- 为"随时买，随时退"核心功能提供数据库层支撑：
--   1. orders 表新增退款时间戳字段
--   2. orders 表新增 RLS UPDATE 策略（用户申请退款）
--      USING 限制：仅允许对自己的 'unused' 订单执行
--      WITH CHECK 限制：状态只能变更为 'refund_requested'
--   3. payments 表不增加对外 UPDATE 策略；
--      Edge Function 使用 service_role 绕过 RLS 写入
--   4. orders.refunded_at 索引（auto-refund-expired 定时任务用）
-- =============================================================

-- -------------------------------------------------------------
-- 1. orders 表：新增退款相关时间戳字段
-- -------------------------------------------------------------

-- 用户提交退款申请的时间（状态变为 refund_requested 时写入）
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS refund_requested_at TIMESTAMPTZ;

-- 退款实际到账完成的时间（Stripe 退款成功、状态变为 refunded 时写入）
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS refunded_at TIMESTAMPTZ;

-- -------------------------------------------------------------
-- 2. orders 表：用户申请退款的 RLS UPDATE 策略
--    - USING：只允许操作自己的、且当前状态为 'unused' 的订单
--      （防止用户对已过期/已使用/已退款订单重复提交退款申请）
--    - WITH CHECK：更新后的 status 必须是 'refund_requested'
--      （防止用户随意篡改 status 为其他任意值）
-- -------------------------------------------------------------
CREATE POLICY "orders_update_refund_request" ON public.orders
  FOR UPDATE
  USING (auth.uid() = user_id AND status = 'unused')
  WITH CHECK (status = 'refund_requested');

-- -------------------------------------------------------------
-- 3. payments 表：service_role 更新策略
--    Edge Function（create-refund / auto-refund-expired）均使用
--    SUPABASE_SERVICE_ROLE_KEY 运行，service_role 默认绕过 RLS，
--    无需显式策略即可读写。
--    为防止普通用户 JWT 通过其他路径篡改 payments 记录，
--    此处 **不** 创建对外开放的 UPDATE 策略；
--    service_role 的写入权限由 Supabase 平台层保证。
-- -------------------------------------------------------------
-- （payments_service_update 策略已移除：service_role 绕过 RLS，
--   对普通用户开放 USING(true) 的 UPDATE 策略存在安全风险）

-- -------------------------------------------------------------
-- 4. orders.refunded_at 索引
--    auto-refund-expired Edge Function 会按 refunded_at IS NULL
--    AND status = 'refund_requested' 批量查询待处理退款，
--    此索引避免全表扫描。
-- -------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_orders_refunded_at
  ON public.orders (refunded_at);
