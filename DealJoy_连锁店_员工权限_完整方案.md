# DealJoy 连锁店 + 员工权限 完整设计方案

> 本方案整合了连锁店（Chain Store）、品牌管理、门店员工角色、邀请机制、安全校验等所有内容。
> 本次只出设计方案，不写代码。

---

## 一、整体角色权限体系

### 1.1 两层架构

```
品牌层 (可选)
├── brands 表 ← 品牌信息
├── brand_admins 表 ← 品牌级管理员
│
门店层 (核心)
├── merchants 表 ← 门店信息（brand_id 可为 NULL = 独立门店）
├── merchants.user_id ← 门店老板（注册人）
├── merchant_staff 表 ← 门店员工
```

### 1.2 完整角色表

| 层级 | 角色 | 来源 | 说明 |
|------|------|------|------|
| 品牌层 | brand_owner | brand_admins.role='owner' | 品牌创建者，一切权限 |
| 品牌层 | brand_admin | brand_admins.role='admin' | 总部运营，管理所有门店 |
| 门店层 | store_owner | merchants.user_id | 门店注册人/老板，该店一切权限 |
| 门店层 | manager | merchant_staff.role='manager' | 店长，管理该店全部功能 |
| 门店层 | cashier | merchant_staff.role='cashier' | 核销员/收银，只能扫码+看订单 |
| 门店层 | service | merchant_staff.role='service' | 客服，核销+订单+回复评价 |

### 1.3 权限优先级链

```
brand_owner > brand_admin > store_owner > manager > service > cashier
```

### 1.4 门店级权限矩阵

| 功能 | store_owner | manager | cashier | service |
|------|:---:|:---:|:---:|:---:|
| 扫码核销 | ✅ | ✅ | ✅ | ✅ |
| 查看订单列表 | ✅ | ✅ | ✅ | ✅ |
| 查看订单详情 | ✅ | ✅ | ❌ | ✅ |
| 回复评价 | ✅ | ✅ | ❌ | ✅ |
| 创建/编辑 Deal | ✅ | ✅ | ❌ | ❌ |
| Deal 上下架 | ✅ | ✅ | ❌ | ❌ |
| 编辑门店信息 | ✅ | ✅ | ❌ | ❌ |
| 查看财务数据 | ✅ | ✅ | ❌ | ❌ |
| 管理员工 | ✅ | ✅ | ❌ | ❌ |
| Influencer 管理 | ✅ | ✅ | ❌ | ❌ |
| 营销工具 | ✅ | ✅ | ❌ | ❌ |
| 数据分析 | ✅ | ✅ | ❌ | ❌ |
| 门店设置 | ✅ | ❌ | ❌ | ❌ |
| 删除门店 | ✅ | ❌ | ❌ | ❌ |

品牌管理员（brand_owner/brand_admin）对旗下所有门店拥有 store_owner 同等权限。

---

## 二、DB Schema

### 2.1 新增 brands 表

```sql
CREATE TABLE public.brands (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name         TEXT NOT NULL,              -- 品牌名 (如 "Panda Express")
  logo_url     TEXT,
  description  TEXT,
  category     TEXT,
  website      TEXT,
  company_name TEXT,
  ein          TEXT,                       -- Tax ID（总部级别）
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 触发器自动更新 updated_at
CREATE TRIGGER set_brands_updated_at
  BEFORE UPDATE ON brands
  FOR EACH ROW EXECUTE FUNCTION moddatetime(updated_at);
```

### 2.2 新增 brand_admins 表

```sql
CREATE TABLE public.brand_admins (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  brand_id   UUID NOT NULL REFERENCES brands(id) ON DELETE CASCADE,
  user_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role       TEXT NOT NULL CHECK (role IN ('owner', 'admin')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (brand_id, user_id)
);
```

### 2.3 新增 brand_invitations 表

```sql
CREATE TABLE public.brand_invitations (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  brand_id      UUID NOT NULL REFERENCES brands(id) ON DELETE CASCADE,
  invited_email TEXT NOT NULL,
  role          TEXT NOT NULL CHECK (role IN ('admin', 'store_owner')),
  merchant_id   UUID REFERENCES merchants(id),  -- 邀请现有门店加入品牌时用
  invited_by    UUID NOT NULL REFERENCES auth.users(id),
  status        TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'expired', 'cancelled')),
  expires_at    TIMESTAMPTZ NOT NULL DEFAULT now() + interval '7 days',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

### 2.4 merchants 表新增 brand_id

```sql
ALTER TABLE public.merchants
  ADD COLUMN IF NOT EXISTS brand_id UUID REFERENCES brands(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_merchants_brand ON merchants(brand_id);
```

独立门店 brand_id = NULL，行为完全不变。

### 2.5 新增 merchant_staff 表

```sql
CREATE TABLE public.merchant_staff (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id  UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
  user_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role         TEXT NOT NULL CHECK (role IN ('manager', 'cashier', 'service')),
  nickname     VARCHAR(50),              -- 显示名，如 "Front Desk Amy"
  is_active    BOOLEAN NOT NULL DEFAULT true,
  invited_by   UUID REFERENCES auth.users(id),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(merchant_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_staff_user ON merchant_staff(user_id);
CREATE INDEX IF NOT EXISTS idx_staff_merchant ON merchant_staff(merchant_id);
```

### 2.6 新增 staff_invitations 表

```sql
CREATE TABLE public.staff_invitations (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id   UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
  invited_email TEXT NOT NULL,
  role          TEXT NOT NULL CHECK (role IN ('manager', 'cashier', 'service')),
  invited_by    UUID NOT NULL REFERENCES auth.users(id),
  status        TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'expired', 'cancelled')),
  expires_at    TIMESTAMPTZ NOT NULL DEFAULT now() + interval '7 days',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

### 2.7 deals 表预留字段

```sql
-- 给未来品牌级 Deal 模板批量发布预留
ALTER TABLE deals ADD COLUMN IF NOT EXISTS deal_template_id UUID;
-- deal_template_id 不为 NULL = 从品牌模板复制而来
-- V1 不用，但提前加好避免后续 migration
```

### 2.8 RLS 策略（完整 SQL）

```sql
-- ============================================
-- brands 表: 所有人可读，品牌管理员可写
-- ============================================
ALTER TABLE brands ENABLE ROW LEVEL SECURITY;

CREATE POLICY "brands_select_all" ON brands
  FOR SELECT USING (true);

CREATE POLICY "brands_modify_admins" ON brands
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM brand_admins
      WHERE brand_admins.brand_id = brands.id
        AND brand_admins.user_id = auth.uid()
    )
  );

-- ============================================
-- brand_admins 表: 同品牌管理员可读，owner 可增删
-- ============================================
ALTER TABLE brand_admins ENABLE ROW LEVEL SECURITY;

CREATE POLICY "brand_admins_select" ON brand_admins
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM brand_admins ba2
      WHERE ba2.brand_id = brand_admins.brand_id
        AND ba2.user_id = auth.uid()
    )
  );

CREATE POLICY "brand_admins_insert" ON brand_admins
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM brand_admins ba2
      WHERE ba2.brand_id = brand_admins.brand_id
        AND ba2.user_id = auth.uid()
        AND ba2.role = 'owner'
    )
  );

CREATE POLICY "brand_admins_delete" ON brand_admins
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM brand_admins ba2
      WHERE ba2.brand_id = brand_admins.brand_id
        AND ba2.user_id = auth.uid()
        AND ba2.role = 'owner'
    )
  );

-- ============================================
-- merchants 表: 门店 owner 或 品牌管理员可管理
-- ============================================
-- 先 DROP 现有冲突策略再 CREATE
CREATE POLICY "merchants_select_all" ON merchants
  FOR SELECT USING (true);

CREATE POLICY "merchants_modify" ON merchants
  FOR ALL USING (
    -- 方式1: 门店 owner
    user_id = auth.uid()
    OR
    -- 方式2: 品牌管理员
    (brand_id IS NOT NULL AND EXISTS (
      SELECT 1 FROM brand_admins
      WHERE brand_admins.brand_id = merchants.brand_id
        AND brand_admins.user_id = auth.uid()
    ))
    OR
    -- 方式3: 门店 manager
    EXISTS (
      SELECT 1 FROM merchant_staff
      WHERE merchant_staff.merchant_id = merchants.id
        AND merchant_staff.user_id = auth.uid()
        AND merchant_staff.role = 'manager'
        AND merchant_staff.is_active = true
    )
  );

-- ============================================
-- merchant_staff 表: 同门店的 owner/manager 可管理，员工可读自己
-- ============================================
ALTER TABLE merchant_staff ENABLE ROW LEVEL SECURITY;

CREATE POLICY "staff_select" ON merchant_staff
  FOR SELECT USING (
    -- 员工自己
    user_id = auth.uid()
    OR
    -- 门店 owner
    EXISTS (SELECT 1 FROM merchants WHERE merchants.id = merchant_staff.merchant_id AND merchants.user_id = auth.uid())
    OR
    -- 门店 manager
    EXISTS (SELECT 1 FROM merchant_staff ms2 WHERE ms2.merchant_id = merchant_staff.merchant_id AND ms2.user_id = auth.uid() AND ms2.role = 'manager' AND ms2.is_active = true)
    OR
    -- 品牌管理员
    EXISTS (
      SELECT 1 FROM merchants m JOIN brand_admins ba ON ba.brand_id = m.brand_id
      WHERE m.id = merchant_staff.merchant_id AND ba.user_id = auth.uid()
    )
  );

CREATE POLICY "staff_manage" ON merchant_staff
  FOR ALL USING (
    -- 门店 owner
    EXISTS (SELECT 1 FROM merchants WHERE merchants.id = merchant_staff.merchant_id AND merchants.user_id = auth.uid())
    OR
    -- 门店 manager（可以增删 cashier/service，不能改 manager）
    EXISTS (SELECT 1 FROM merchant_staff ms2 WHERE ms2.merchant_id = merchant_staff.merchant_id AND ms2.user_id = auth.uid() AND ms2.role = 'manager' AND ms2.is_active = true)
    OR
    -- 品牌管理员
    EXISTS (
      SELECT 1 FROM merchants m JOIN brand_admins ba ON ba.brand_id = m.brand_id
      WHERE m.id = merchant_staff.merchant_id AND ba.user_id = auth.uid()
    )
  );

-- ============================================
-- deals 表: 门店 owner + manager + 品牌管理员可管理
-- ============================================
CREATE POLICY "deals_select_all" ON deals
  FOR SELECT USING (true);

CREATE POLICY "deals_modify" ON deals
  FOR ALL USING (
    -- 门店 owner
    EXISTS (SELECT 1 FROM merchants WHERE merchants.id = deals.merchant_id AND merchants.user_id = auth.uid())
    OR
    -- 门店 manager
    EXISTS (SELECT 1 FROM merchant_staff WHERE merchant_staff.merchant_id = deals.merchant_id AND merchant_staff.user_id = auth.uid() AND merchant_staff.role = 'manager' AND merchant_staff.is_active = true)
    OR
    -- 品牌管理员
    EXISTS (
      SELECT 1 FROM merchants m JOIN brand_admins ba ON ba.brand_id = m.brand_id
      WHERE m.id = deals.merchant_id AND ba.user_id = auth.uid()
    )
  );
```

---

## 三、Edge Function 改动

### 3.1 新增共享鉴权模块 _shared/auth.ts

所有 Edge Function 统一使用此模块鉴权：

```typescript
interface AuthResult {
  userId: string;
  merchantId: string;           // 当前操作的门店 ID
  merchantIds: string[];        // 该用户可管理的所有门店 ID
  role: 'brand_owner' | 'brand_admin' | 'store_owner' | 'manager' | 'cashier' | 'service';
  brandId: string | null;
  isBrandAdmin: boolean;
  permissions: string[];        // ['scan', 'orders', 'reviews', 'deals', 'store', 'finance', 'staff', 'influencer', 'marketing', 'analytics', 'settings']
}

// 解析当前请求的用户角色和权限
async function resolveAuth(supabase, userId, headers): Promise<AuthResult> {
  // 1. 检查是否品牌管理员
  const brandAdmin = await supabase.from('brand_admins')
    .select('brand_id, role').eq('user_id', userId).maybeSingle();
  
  // 2. 检查是否门店 owner
  const ownedStores = await supabase.from('merchants')
    .select('id, brand_id').eq('user_id', userId);
  
  // 3. 检查是否门店员工
  const staffRecords = await supabase.from('merchant_staff')
    .select('merchant_id, role').eq('user_id', userId).eq('is_active', true);
  
  // 4. 确定 merchantId（优先 X-Merchant-Id header）
  const headerMerchantId = headers.get('X-Merchant-Id');
  if (headerMerchantId) {
    // ⭐ 安全校验：确认该门店在用户的管理范围内
    if (!allAccessibleIds.includes(headerMerchantId)) {
      throw new Error('Unauthorized: you cannot access this merchant');
    }
    // ⭐ 安全校验：如果是品牌管理员，确认门店属于该品牌
    if (brandAdmin) {
      const merchant = await supabase.from('merchants')
        .select('brand_id').eq('id', headerMerchantId).single();
      if (merchant.brand_id !== brandAdmin.brand_id) {
        throw new Error('Unauthorized: merchant not in your brand');
      }
    }
  }
  
  // 5. 根据角色生成权限列表
  const permissions = getPermissionsByRole(role);
  
  return { userId, merchantId, merchantIds, role, brandId, isBrandAdmin, permissions };
}

// 权限检查中间件
function requirePermission(auth: AuthResult, permission: string) {
  if (!auth.permissions.includes(permission)) {
    throw new Error(`Forbidden: ${auth.role} does not have ${permission} permission`);
  }
}

// 角色 → 权限映射
function getPermissionsByRole(role: string): string[] {
  const map = {
    'brand_owner':  ['scan','orders','reviews','deals','store','finance','staff','influencer','marketing','analytics','settings','brand'],
    'brand_admin':  ['scan','orders','reviews','deals','store','finance','staff','influencer','marketing','analytics','settings','brand'],
    'store_owner':  ['scan','orders','reviews','deals','store','finance','staff','influencer','marketing','analytics','settings'],
    'manager':      ['scan','orders','reviews','deals','store','finance','staff','influencer','marketing','analytics'],
    'service':      ['scan','orders','reviews'],
    'cashier':      ['scan','orders'],
  };
  return map[role] || [];
}
```

### 3.2 现有 Edge Function 改动清单

所有以下 Edge Function 的开头替换为 `resolveAuth()` 统一鉴权：

| Edge Function | 需要的权限 | 改动 |
|---------------|-----------|------|
| merchant-store (GET/PATCH) | store | resolveAuth + requirePermission('store') |
| merchant-deals (CRUD) | deals | resolveAuth + requirePermission('deals') |
| merchant-scan (POST) | scan | resolveAuth + requirePermission('scan') |
| merchant-orders (GET) | orders | resolveAuth + requirePermission('orders') |
| merchant-earnings (GET) | finance | resolveAuth + requirePermission('finance') |
| merchant-reviews (GET/POST reply) | reviews | resolveAuth + requirePermission('reviews') |
| merchant-dashboard (GET) | orders (基础数据所有人可看) | resolveAuth，品牌管理员看汇总 |
| merchant-notifications (GET) | orders (基础) | resolveAuth |

### 3.3 新增 Edge Function

**merchant-brand（品牌管理）**
```
GET    /merchant-brand              — 品牌信息 + 门店列表 + 管理员列表
PATCH  /merchant-brand              — 更新品牌信息（requirePermission('brand')）
POST   /merchant-brand/stores       — 添加新门店（发邀请或直接创建空门店）
DELETE /merchant-brand/stores/:id   — 移除门店（解除 brand_id，不删门店）
POST   /merchant-brand/admins       — 邀请品牌管理员（发送邀请邮件）
DELETE /merchant-brand/admins/:id   — 移除品牌管理员
```

**merchant-staff（员工管理）**
```
GET    /merchant-staff              — 当前门店员工列表
POST   /merchant-staff/invite       — 邀请员工（发送邀请到邮箱）
PATCH  /merchant-staff/:id          — 修改员工角色/昵称
DELETE /merchant-staff/:id          — 移除员工
POST   /merchant-staff/accept       — 员工接受邀请
```

### 3.4 RPC 搜索函数更新

search_deals_nearby 和 search_deals_by_city 增加:
- 返回字段: `merchant_brand_name TEXT`, `merchant_brand_logo TEXT`
- LEFT JOIN brands b ON m.brand_id = b.id
- Logo fallback: COALESCE(m.logo_url, b.logo_url)

---

## 四、商家端 App 改动

### 4.1 新增 Models

```dart
// brand_info.dart
class BrandInfo {
  String id;
  String name;
  String? logoUrl;
  String? description;
  int storeCount;
}

// store_summary.dart
class StoreSummary {
  String id;
  String name;
  String address;
  String city;
  String status;
  String? logoUrl;
}

// staff_member.dart
class StaffMember {
  String id;
  String userId;
  String merchantId;
  String role;          // manager, cashier, service
  String? nickname;
  bool isActive;
  DateTime createdAt;
}
```

### 4.2 修改 StoreInfo Model

```dart
class StoreInfo {
  // ...现有字段...
  BrandInfo? brand;           // 新增
  bool isBrandAdmin;          // 新增
  String currentRole;         // 新增: brand_owner/brand_admin/store_owner/manager/cashier/service
  List<String> permissions;   // 新增: 权限列表
}
```

### 4.3 修改 StoreService

```dart
class StoreService {
  String? _activeMerchantId;  // 品牌管理员切换门店时使用
  
  // 所有请求增加 header
  Map<String, String> get _headers => {
    if (_activeMerchantId != null) 'X-Merchant-Id': _activeMerchantId!,
  };
  
  Future<List<StoreSummary>> fetchBrandStores();
  Future<void> switchStore(String merchantId);
  Future<List<StaffMember>> fetchStaff();
  Future<void> inviteStaff(String email, String role);
  Future<void> removeStaff(String staffId);
  Future<void> updateStaffRole(String staffId, String newRole);
}
```

### 4.4 新增 UI 页面

**StoreSelector Widget（AppBar 门店切换）**
- 仅品牌管理员可见
- 点击弹出 BottomSheet 显示旗下所有门店
- 切换后刷新全部数据

**BrandManagePage（品牌管理）**
- 品牌信息编辑（名称、Logo、描述）
- 门店列表（添加/移除门店）
- 管理员列表（邀请/移除管理员）
- 入口在 Settings 页

**StaffManagePage（员工管理）**
- 员工列表（头像、昵称、角色、状态）
- 邀请员工（输入邮箱、选角色）
- 修改角色（下拉选择 manager/cashier/service）
- 移除员工（确认弹窗）
- 入口在 Settings 页

**权限控制 UI 隐藏**
- 商家端所有页面根据 permissions 列表控制显示/隐藏
- cashier 登录后只看到: Dashboard(简化版) + Scan + Orders
- service 登录后只看到: Dashboard(简化版) + Scan + Orders + Reviews
- manager 看到全部（除 Settings 里的危险操作）
- Bottom Navigation 的 tab 数量根据权限动态调整

### 4.5 登录后路由逻辑

```
用户登录
  ↓
检查 brand_admins → 有记录 = 品牌管理员，进入门店选择页
  ↓ 没有
检查 merchants.user_id → 有记录 = 门店 owner，直接进 Dashboard
  ↓ 没有  
检查 merchant_staff → 有记录 = 员工，按角色权限进入对应界面
  ↓ 没有
检查 merchant_applications → 有记录 = 正在审核中，显示审核状态页
  ↓ 没有
新商家，进入注册流程
```

---

## 五、用户端 App 改动

### 5.1 Model 改动

```dart
// MerchantSummary（搜索结果卡片）
class MerchantSummary {
  // ...现有字段...
  String? brandId;            // 新增
  String? brandName;          // 新增
  String? brandLogoUrl;       // 新增
}

// MerchantDetail（详情页）
class MerchantDetail {
  // ...现有字段...
  String? brandId;
  String? brandName;
  String? brandLogoUrl;
  int? brandStoreCount;       // 该品牌有几家门店
}
```

### 5.2 查询改动

- deals 查询增加: `LEFT JOIN brands ON brands.id = merchants.brand_id`
- StoreDetailRepository 新增: `fetchSameBrandStores(brandId, excludeMerchantId)` — 获取同品牌其他门店

### 5.3 UI 改动

**商家详情页头部：**
- 有品牌时: 品牌 Logo 小图标 + 品牌名 + "N locations" 标签
- 无品牌时: 不显示，和现在一样

**商家详情页底部（More/Recommended tab 内）：**
- 如果是连锁店，增加 "Other Locations" section
- 显示同品牌其他门店卡片（地址+距离+评分）
- 点击跳转到该门店详情页

**搜索：**
- 搜索品牌名（如 "Panda Express"）时，该品牌所有门店都出现在结果中
- 按距离排序，和普通搜索一致

---

## 六、品牌管理员的 Dashboard

品牌管理员的工作台有两种视图切换：

**单店视图（默认）：**
- 和普通门店 owner 看到的 Dashboard 一样
- 顶部有门店切换器

**品牌总览（V2）：**
- 所有门店汇总: 总订单、总收入、总核销、总评分
- 各门店对比排行: 按收入/订单/评分排序
- 趋势图: 所有门店合并的 7 天趋势
- V1 先不做，预留入口

---

## 七、邀请流程

### 7.1 品牌邀请管理员

```
品牌 Owner 输入邮箱 + 选角色(admin)
  ↓
系统创建 brand_invitations 记录
  ↓
发送邮件（含邀请链接，7天过期）
  ↓
被邀请人点击链接 → 注册/登录 → 接受邀请
  ↓
系统创建 brand_admins 记录
```

### 7.2 品牌邀请门店加入

```
品牌 Owner/Admin 输入门店 owner 的邮箱
  ↓
系统创建 brand_invitations 记录 (role='store_owner', merchant_id=xxx)
  ↓
门店 owner 收到邀请 → 接受
  ↓
系统更新 merchants.brand_id = 该品牌 ID
```

### 7.3 门店邀请员工

```
门店 Owner/Manager 输入邮箱 + 选角色(manager/cashier/service)
  ↓
系统创建 staff_invitations 记录
  ↓
发送邮件（含邀请链接，7天过期）
  ↓
被邀请人点击链接 → 用商家端 App 注册/登录 → 接受邀请
  ↓
系统创建 merchant_staff 记录
  ↓
该用户登录商家端后，直接进入对应门店 + 对应权限界面
```

---

## 八、关键文件路径

### 后端（共享 Supabase）

| 文件 | 类型 |
|------|------|
| deal_joy/supabase/migrations/20260307000001_chain_store.sql | 新建 |
| deal_joy/supabase/migrations/20260307000002_merchant_staff.sql | 新建 |
| deal_joy/supabase/functions/_shared/auth.ts | 新建 |
| deal_joy/supabase/functions/merchant-brand/index.ts | 新建 |
| deal_joy/supabase/functions/merchant-staff/index.ts | 新建 |
| deal_joy/supabase/functions/merchant-store/index.ts | 修改 |
| deal_joy/supabase/functions/merchant-deals/index.ts | 修改 |
| deal_joy/supabase/functions/merchant-scan/index.ts | 修改 |
| deal_joy/supabase/functions/merchant-orders/index.ts | 修改 |
| deal_joy/supabase/functions/merchant-dashboard/index.ts | 修改 |
| deal_joy/supabase/functions/merchant-earnings/index.ts | 修改 |
| deal_joy/supabase/functions/merchant-reviews/index.ts | 修改 |

### 商家端

| 文件 | 类型 |
|------|------|
| dealjoy_merchant/lib/features/store/models/brand_info.dart | 新建 |
| dealjoy_merchant/lib/features/store/models/store_summary.dart | 新建 |
| dealjoy_merchant/lib/features/store/models/staff_member.dart | 新建 |
| dealjoy_merchant/lib/features/store/models/store_info.dart | 修改 |
| dealjoy_merchant/lib/features/store/services/store_service.dart | 修改 |
| dealjoy_merchant/lib/features/store/providers/store_provider.dart | 修改 |
| dealjoy_merchant/lib/features/store/pages/brand_manage_page.dart | 新建 |
| dealjoy_merchant/lib/features/store/pages/staff_manage_page.dart | 新建 |
| dealjoy_merchant/lib/features/store/widgets/store_selector.dart | 新建 |
| dealjoy_merchant/lib/features/settings/ | 修改(加入口) |
| dealjoy_merchant/lib/app_shell.dart | 修改(权限控制 tab) |
| dealjoy_merchant/lib/router/app_router.dart | 修改(登录路由逻辑) |

### 用户端

| 文件 | 类型 |
|------|------|
| deal_joy/lib/features/deals/data/models/deal_model.dart | 修改 |
| deal_joy/lib/features/merchant/data/models/merchant_detail_model.dart | 修改 |
| deal_joy/lib/features/merchant/data/repositories/store_detail_repository.dart | 修改 |
| deal_joy/lib/features/deals/widgets/merchant_info_section.dart | 修改(品牌标识) |
| deal_joy/lib/features/deals/widgets/recommended_tab.dart | 修改(Other Locations) |

---

## 九、实施顺序

```
Phase 1 (DB) — 1天
├── Migration: brands + brand_admins + brand_invitations
├── Migration: merchant_staff + staff_invitations  
├── Migration: merchants.brand_id + deals.deal_template_id
├── RLS 策略全部写好
└── RPC 函数更新（搜索函数加品牌字段）

Phase 2 (Backend) — 2-3天
├── _shared/auth.ts 共享鉴权模块
├── merchant-brand Edge Function（新建）
├── merchant-staff Edge Function（新建）
├── 所有现有 EF 替换鉴权为 resolveAuth()
└── 逐个测试每个 EF 的权限是否正确

Phase 3 (商家端) — 3-4天
├── Models（BrandInfo, StoreSummary, StaffMember）
├── Service（增加 X-Merchant-Id header + 新方法）
├── Provider（switchStore, staffProvider）
├── UI: StoreSelector（门店切换）
├── UI: BrandManagePage（品牌管理）
├── UI: StaffManagePage（员工管理）
├── 权限控制: Bottom Nav + 页面显隐
└── 登录路由逻辑更新

Phase 4 (用户端) — 1天
├── Models 加品牌字段
├── Repository 加同品牌门店查询
├── 商家详情页显示品牌标识
└── Recommended tab 加 Other Locations

Phase 5 (测试) — 1-2天
├── 独立门店（brand_id=NULL）全部功能回归测试
├── 连锁店: 创建品牌 → 关联门店 → 切换门店
├── 品牌管理员权限测试
├── 门店 owner 权限测试  
├── cashier 权限测试（只能扫码+看订单）
├── service 权限测试（扫码+订单+评价）
├── manager 权限测试（全部除设置）
├── X-Merchant-Id 越权测试（尝试访问非本品牌门店）
├── 邀请流程测试（品牌邀请管理员、门店邀请员工）
└── 用户端搜索品牌名 + 详情页品牌标识
```

---

## 十、风险与应对

| 风险 | 应对 |
|------|------|
| 品牌管理员没有 merchant 记录，现有 EF 的 .single() 会 404 | 统一用 _shared/auth.ts，不再直接查 merchants.user_id |
| X-Merchant-Id 越权访问其他品牌的门店 | resolveAuth 中必须校验门店属于该品牌 |
| RPC 函数返回类型变化需 DROP + CREATE | Migration 中先 DROP 再 CREATE |
| 大量 EF 需同时改鉴权 | _shared/auth.ts 一处改全局生效 |
| 新字段 null 导致前端解析崩溃 | fromJson 统一用 as String? 可空 |
| cashier 误操作看到了不该看的页面 | 前端 UI 隐藏 + 后端权限双重校验 |
| 员工离职忘记删账号 | is_active 字段，管理员可随时禁用，不影响 user 账号 |

---

## 十一、V2 预留（本次不做）

- 品牌总览 Dashboard（所有门店汇总数据）
- regional_manager 角色（管理指定区域的门店）
- finance 角色（只看财务数据）
- Deal 模板：品牌级创建 Deal → 一键发布到多个门店
- 品牌聚合页：用户端品牌页面，展示所有门店
- 门店间调货/库存共享
