-- V2.3 更多角色：区域经理(regional_manager)、财务(finance)、实习生(trainee)
-- merchant_staff.role 字段类型为 text，无需修改枚举
-- 此 migration 仅添加注释说明合法角色值

-- 更新 merchant_staff 表注释
COMMENT ON COLUMN merchant_staff.role IS
  'Staff role: cashier | service | manager | finance | regional_manager | trainee';

-- 添加 CHECK 约束确保角色值合法（如果还没有的话）
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.check_constraints
    WHERE constraint_name = 'merchant_staff_role_check'
  ) THEN
    ALTER TABLE merchant_staff
      ADD CONSTRAINT merchant_staff_role_check
      CHECK (role IN ('cashier', 'service', 'manager', 'finance', 'regional_manager', 'trainee'));
  END IF;
END $$;

-- 区域经理可以管理多个门店，需要在 merchant_staff 中有多条记录
-- 或通过品牌权限管理。以下添加索引优化查询
CREATE INDEX IF NOT EXISTS idx_merchant_staff_role
  ON merchant_staff(role);
