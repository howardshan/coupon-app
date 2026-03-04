-- ============================================================
-- Migration: 20260303000013_merchant_settings.sql
-- 模块: 13.商家设置 — 员工子账号 RBAC 数据表
-- 说明: 为 V2 员工子账号功能创建数据库基础设施
--       通知偏好使用客户端 SharedPreferences 存储，无需后端表
-- ============================================================

-- ------------------------------------------------------------
-- 1. 创建员工子账号表
--    角色: scan_only（仅核销）/ full_access（完整权限）
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS merchant_staff (
  id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id     uuid        NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
  staff_user_id   uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role            text        NOT NULL CHECK (role IN ('scan_only', 'full_access')),
  invited_by      uuid        REFERENCES auth.users(id),
  created_at      timestamptz DEFAULT now(),
  -- 同一商家不可重复添加同一员工
  UNIQUE (merchant_id, staff_user_id)
);

COMMENT ON TABLE merchant_staff IS '商家员工子账号表，支持 RBAC 权限隔离（V2）';
COMMENT ON COLUMN merchant_staff.role IS 'scan_only: 仅核销扫码权限；full_access: 完整管理权限';
COMMENT ON COLUMN merchant_staff.invited_by IS '邀请人（商家主账号 user_id）';

-- ------------------------------------------------------------
-- 2. 性能索引
-- ------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_merchant_staff_merchant_id
  ON merchant_staff (merchant_id);

CREATE INDEX IF NOT EXISTS idx_merchant_staff_user_id
  ON merchant_staff (staff_user_id);

-- ------------------------------------------------------------
-- 3. 启用 RLS
-- ------------------------------------------------------------
ALTER TABLE merchant_staff ENABLE ROW LEVEL SECURITY;

-- ------------------------------------------------------------
-- 4. RLS 策略 — merchant_staff 表权限隔离
-- ------------------------------------------------------------

-- 4a. 商家主账号：可对自己名下员工执行增删改查
CREATE POLICY "merchant_owner_manage_staff"
  ON merchant_staff
  FOR ALL
  USING (
    merchant_id IN (
      SELECT id FROM merchants WHERE user_id = auth.uid()
    )
  )
  WITH CHECK (
    merchant_id IN (
      SELECT id FROM merchants WHERE user_id = auth.uid()
    )
  );

-- 4b. 员工账号：只能查看自己的记录（知道自己属于哪个商家）
CREATE POLICY "staff_read_own_record"
  ON merchant_staff
  FOR SELECT
  USING (staff_user_id = auth.uid());

-- ------------------------------------------------------------
-- 5. 更新 merchants 表 RLS — 允许 full_access 员工读取商家数据
--    注意: 原 SELECT 策略只允许 user_id = auth.uid() 的用户读取
--    现在额外允许: 在 merchant_staff 表中 role='full_access' 的员工也可读取
-- ------------------------------------------------------------

-- 先删除现有的 merchants SELECT 策略（如果存在）
DROP POLICY IF EXISTS "merchant_read_own_data" ON merchants;
DROP POLICY IF EXISTS "merchants_select_own" ON merchants;

-- 重建 merchants SELECT 策略：商家本人 + full_access 员工均可读取
CREATE POLICY "merchants_readable_by_owner_and_full_staff"
  ON merchants
  FOR SELECT
  USING (
    -- 商家主账号
    user_id = auth.uid()
    OR
    -- full_access 员工
    id IN (
      SELECT merchant_id
      FROM merchant_staff
      WHERE staff_user_id = auth.uid()
        AND role = 'full_access'
    )
  );

-- scan_only 员工只需访问核销相关表，merchants 表本身不开放给他们
-- 核销权限通过 coupons 表的 RLS 单独控制（V2 时补充）

-- ------------------------------------------------------------
-- 6. 验证查询（可在部署后手动执行检查）
-- ------------------------------------------------------------
-- SELECT COUNT(*) FROM merchant_staff;                     -- 应为 0
-- SELECT COUNT(*) FROM pg_policies WHERE tablename = 'merchant_staff';  -- 应为 2
