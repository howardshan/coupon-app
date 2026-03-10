# DealJoy 多门店系统：完成所有未完成功能 + 自动化测试

## 当前状态

V1 共 93 项功能点，约 25% 已完成。以下是每个模块的完成状态和待办事项。
你需要按顺序完成所有待办，每完成一个模块就生成该模块的 Maestro 测试脚本并运行。

## 关键路径

商家端项目：`/Users/howardshansmac/github/coupon app/coupon-app/dealjoy_merchant/`
用户端项目：`/Users/howardshansmac/github/coupon app/coupon-app/deal_joy/`
共享后端：`/Users/howardshansmac/github/coupon app/coupon-app/deal_joy/supabase/`
多门店方案文档：`/Users/howardshansmac/github/coupon app/DealJoy_多门店系统完整方案.md`
测试报告 Excel：`/Users/howardshansmac/github/coupon app/DealJoy_MultiStore_Test_Report.xlsx`

**先读取多门店方案文档，理解全部 93 个功能点的需求再开始写代码。**

---

## Maestro 测试脚本编写规则（⭐ 必须严格遵守）

### 规则1: 先看实际 UI，再写脚本，绝不猜测

每个模块生成测试脚本之前，必须先：

1. 读 Flutter 源码 → 找到该模块所有页面的 Widget 树
2. 列出所有可交互组件（按钮、输入框、开关等）的**实际文字和 Key**
3. 检查是否有 ValueKey，没有的先加上（见规则2）
4. Build APK 安装到模拟器
5. 运行 `maestro studio`，手动走一遍流程，确认：
   - 每个按钮的**实际文字**（不是猜的）
   - 每个输入框的**实际 label**
   - 页面跳转后**实际显示的文字**
6. 基于实际 UI 写 YAML 测试脚本
7. 运行测试 → 修复 → 重跑

**绝对不要跳过第 1-5 步直接凭猜测写脚本。**

常见错误示例：
- ❌ 猜的：`tapOn: "Email"` → 实际 UI 是 "Business Email"
- ❌ 猜的：一个 Upload 按钮 → 实际有多个不同的 Upload 按钮
- ✅ 看了源码/Studio：`tapOn: "Business Email"` 或 `tapOn: { id: "auth_business_email_field" }`

### 规则2: 所有可交互 Widget 必须有 ValueKey

在写测试脚本之前，先在 Flutter 代码中给所有可交互组件加 Key：

```dart
// 输入框
TextFormField(
  key: const ValueKey('auth_business_email_field'),
  decoration: InputDecoration(labelText: 'Business Email'),
)

// 按钮
ElevatedButton(
  key: const ValueKey('auth_submit_btn'),
  onPressed: () {},
  child: Text('Create Account'),
)

// 上传区域（多个时每个不同 Key）
GestureDetector(
  key: const ValueKey('upload_business_license_btn'),
  child: UploadArea(label: 'Business License'),
)
GestureDetector(
  key: const ValueKey('upload_health_permit_btn'),
  child: UploadArea(label: 'Health Permit'),
)
```

Key 命名规则：`{模块}_{组件描述}_{类型}`
- `auth_business_email_field`
- `auth_submit_btn`
- `dashboard_revenue_card`
- `scan_confirm_btn`
- `deal_create_title_field`
- `upload_business_license_btn`
- `upload_health_permit_btn`

测试脚本中优先用 Key，不要用显示文字（文字可能变化）：
```yaml
# ❌ 不稳定
- tapOn: "Upload"

# ✅ 稳定
- tapOn:
    id: "upload_business_license_btn"
```

### 规则3: 设置超时，防止卡死循环

Maestro 默认会无限重试找不到的元素。**必须给每个等待步骤设超时**：

```yaml
# ❌ 会卡死：如果 "Dashboard" 永远不出现，就无限循环
- assertVisible: "Dashboard"

# ✅ 设超时：最多等15秒，超时直接判 FAIL
- extendedWaitUntil:
    visible: "Dashboard"
    timeout: 15000

# 非关键步骤用 optional，找不到就跳过
- tapOn:
    text: "Skip Tutorial"
    optional: true
```

全局配置文件 `.maestro/config.yaml`：
```yaml
appId: com.dealjoy.merchant
onFlowStart:
  - clearState
  - launchApp
```

### 规则4: 多个相似按钮用 Key 或相对定位

```yaml
# ❌ 错误：多个 "Upload" 按钮，只会点第一个
- tapOn: "Upload"

# ✅ 方案A：用不同的 Key（首选）
- tapOn:
    id: "upload_business_license_btn"
- tapOn:
    id: "upload_health_permit_btn"

# ✅ 方案B：用 index 指定第几个
- tapOn:
    text: "Upload"
    index: 0
- tapOn:
    text: "Upload"
    index: 1

# ✅ 方案C：用 below 相对定位
- tapOn:
    text: "Upload"
    below: "Business License"
- tapOn:
    text: "Upload"
    below: "Health Permit"
```

### 规则5: 每个测试脚本的标准结构

```yaml
appId: com.dealjoy.merchant
tags:
  - registration
---
# TC001: Email Registration
# 前置条件：App 已安装，未登录状态

- clearState
- launchApp

# Step 1: 进入注册页
- tapOn:
    id: "signup_btn"
- extendedWaitUntil:
    visible: "Create Account"
    timeout: 10000

# Step 2: 填写邮箱
- tapOn:
    id: "auth_business_email_field"
- inputText: "test@dealjoy.com"

# Step 3: 填写密码
- tapOn:
    id: "auth_password_field"
- inputText: "Test123456"

# Step 4: 提交
- tapOn:
    id: "auth_submit_btn"

# 验证：进入了 onboarding 页面（带超时）
- extendedWaitUntil:
    visible: "Company Name"
    timeout: 15000
- assertVisible: "Company Name"
```

### 规则6: 可复用的子流程

需要登录的测试用例引用共享登录 flow，不要重复写：

```yaml
# .maestro/shared/login.yaml
appId: com.dealjoy.merchant
---
- clearState
- launchApp
- tapOn:
    id: "login_email_field"
- inputText: "testmerchant@dealjoy.com"
- tapOn:
    id: "login_password_field"
- inputText: "Test123456"
- tapOn:
    id: "login_submit_btn"
- extendedWaitUntil:
    visible: "Dashboard"
    timeout: 15000
```

其他测试脚本引用：
```yaml
appId: com.dealjoy.merchant
tags:
  - dashboard
---
- runFlow: ../shared/login.yaml
# 然后开始测试 Dashboard 功能...
- assertVisible: "Today's Orders"
```

### 规则7: 测试脚本生成的完整工作流程

对每个模块，严格按以下顺序执行：

```
1. 读源码 → 找到所有页面和组件
2. 给缺少 Key 的 Widget 补上 ValueKey
3. flutter build apk --debug
4. adb install -r build/app/outputs/flutter-apk/app-debug.apk
5. maestro studio → 手动走一遍 → 记录实际 UI 文字
6. 写 YAML 测试脚本（基于实际 UI，不是猜的）
7. maestro test 运行 → 看结果
8. FAIL 的 → 分析原因 → 修代码或修脚本 → 回到 step 3 或 step 6
9. 全部 PASS → 进入下一模块
```

---

## Phase 1: 完成注册流程改造（#7-#11）

### 已完成
- brands, brand_admins 表已建

### 待完成
1. 商家端注册页面添加选择：Single Location / Multiple Locations（SegmentedButton）
2. 选 Single Location → 走现有注册流程，不变
3. 选 Multiple Locations → 新增品牌信息填写步骤（品牌名、Logo、描述）→ 然后填第一家门店信息 → 一起提交审核
4. 提交时创建 brands 记录 + brand_admins(role='owner') + merchants(brand_id) + merchant_applications
5. 独立门店设置页添加 "Upgrade to Chain" 入口
6. 升级流程：自动用现有门店信息预填品牌 → 确认后创建 brand → 更新 merchants.brand_id

### Flutter Key 要求
- `auth_location_type_single` — Single Location 按钮
- `auth_location_type_multi` — Multiple Locations 按钮
- `brand_name_field` — 品牌名输入框
- `brand_logo_upload_btn` — 品牌 Logo 上传
- `brand_submit_btn` — 品牌信息提交
- `settings_upgrade_chain_btn` — 升级为连锁按钮

### 涉及文件
- `dealjoy_merchant/lib/features/merchant_auth/pages/` — 注册页面改造
- `dealjoy_merchant/lib/features/settings/` — Upgrade to Chain 入口
- `supabase/functions/` — 支持品牌注册
- `supabase/migrations/` — 如需补充字段

---

## Phase 2: 完成角色权限 UI 控制（#18-#22）

### 已完成
- _shared/auth.ts 已有 6 角色 + 13 权限定义

### 待完成
1. 商家端 app_shell.dart 根据登录用户的 permissions 动态控制 Bottom Navigation tab 显隐：
   - cashier → 只显示 Scan + Orders（2个tab）
   - service → Scan + Orders + Reviews（3个tab）
   - manager → 全部（除 Settings 里的危险操作）
   - store_owner → 全部
   - brand_admin/brand_owner → 全部 + 门店切换器
2. 创建权限 Provider：登录时从后端获取当前用户的 role 和 permissions，全局可用
3. 每个页面顶部检查权限，无权限的页面显示 "No Access" 或直接不渲染

### 涉及文件
- `dealjoy_merchant/lib/app_shell.dart` — 动态 tab
- `dealjoy_merchant/lib/core/providers/auth_provider.dart` — 权限 Provider
- 所有页面 — 加权限检查

---

## Phase 3: 完成登录路由逻辑（#89-#93）

### 待完成
1. 登录后调用后端获取用户身份信息
2. 按以下逻辑路由：
   - 查 brand_admins 有记录 → 品牌管理员 → 进入门店选择页
   - 查 merchants.user_id 有记录 → 门店老板 → 直接进 Dashboard
   - 查 merchant_staff 有记录且 is_active=true → 员工 → 按角色权限进入对应界面（cashier 直接进扫码页）
   - 查 merchant_applications 有记录 → 审核中 → 显示审核状态页
   - 都没有 → 新用户 → 注册流程
3. 创建对应的路由逻辑和页面

### Flutter Key 要求
- `store_selector_page` — 门店选择页
- `store_selector_item_{merchantId}` — 每个门店卡片
- `under_review_page` — 审核中页面

### 涉及文件
- `dealjoy_merchant/lib/router/app_router.dart`
- `dealjoy_merchant/lib/core/providers/auth_provider.dart`
- 可能需要新建 `store_selector_page.dart`

---

## Phase 4: 完成品牌管理员功能（#28-#33）

### 待完成
1. **门店切换器 Widget**：AppBar 顶部下拉，显示旗下所有门店，选中后切换当前操作门店
2. 切换后所有数据（Dashboard/订单/评价等）刷新为该门店数据
3. 所有 API 请求自动带上 X-Merchant-Id header
4. **品牌管理页**（新页面）：
   - 品牌信息编辑（名称、Logo、描述）
   - 门店列表（查看/添加/移除门店）
   - 管理员列表（查看/邀请/移除品牌管理员）
5. 添加新门店两种方式：
   - 直接创建：填门店信息 + 指定门店老板邮箱 + 上传证件 → 提交审核
   - 邀请现有门店：输入门店老板邮箱 → 发邀请
6. Settings 页添加 "Brand Management" 入口

### Flutter Key 要求
- `store_switcher_btn` — 门店切换下拉按钮
- `store_switcher_item_{merchantId}` — 下拉中每个门店
- `brand_manage_name_field` — 品牌名编辑
- `brand_manage_add_store_btn` — 添加门店按钮
- `brand_manage_invite_admin_btn` — 邀请管理员按钮
- `settings_brand_management_btn` — Settings 入口

### 涉及文件
- 新建 `dealjoy_merchant/lib/features/store/widgets/store_selector.dart`
- 新建 `dealjoy_merchant/lib/features/store/pages/brand_manage_page.dart`
- `dealjoy_merchant/lib/features/store/services/store_service.dart` — 加 X-Merchant-Id
- `supabase/functions/merchant-brand/index.ts` — 完善所有路由

---

## Phase 5: 完成邀请机制 + 员工管理（#23-#27, #34-#38）

### 已完成
- staff_invitations 表已建
- GET staff + accept invite API 完成

### 待完成
1. **invite API**：POST /merchant-staff/invite — 创建 staff_invitations 记录
2. **update API**：PATCH /merchant-staff/:id — 修改员工角色（只能改比自己低的角色）
3. **remove API**：DELETE /merchant-staff/:id — 设 is_active=false
4. **品牌邀请管理员 API**：POST /merchant-brand/admins — 创建 brand_invitations
5. **品牌邀请门店 API**：POST /merchant-brand/stores/invite
6. **员工管理页面**（新页面）：
   - 员工列表（头像、昵称、角色、状态）
   - 邀请按钮 → 输入邮箱 + 选角色
   - 每个员工行：修改角色 / 移除
7. 邀请方可以取消未接受的邀请
8. 角色创建权限校验：只能邀请比自己低的角色

### Flutter Key 要求
- `staff_invite_btn` — 邀请员工按钮
- `staff_invite_email_field` — 邀请邮箱输入
- `staff_invite_role_dropdown` — 角色选择
- `staff_invite_submit_btn` — 发送邀请
- `staff_item_{staffId}_role_btn` — 修改角色
- `staff_item_{staffId}_remove_btn` — 移除员工

### 涉及文件
- `supabase/functions/merchant-staff/index.ts` — 补全 invite/update/remove
- `supabase/functions/merchant-brand/index.ts` — 补全 admins/stores invite
- 新建 `dealjoy_merchant/lib/features/settings/pages/staff_manage_page.dart`

---

## Phase 6: 完成 Deal 多店通用（#39-#43）

### 待完成
1. 创建 `deal_applicable_stores` 表（如果还没建）
2. 品牌管理员创建 Deal 页面增加适用范围选择：
   - "This store only"（默认，不插入 deal_applicable_stores）
   - "Multiple locations" → 显示门店列表可勾选
3. 选中的门店写入 deal_applicable_stores
4. 多店通用 Deal 在每个适用门店的详情页都展示
5. 用户端 Deal 详情页显示 "Available at X locations" + 门店列表（含距离）
6. 用户券面上标注适用门店

### Flutter Key 要求
- `deal_scope_this_store_btn` — 仅本店
- `deal_scope_multi_store_btn` — 多店通用
- `deal_store_checkbox_{merchantId}` — 每个门店勾选

### 涉及文件
- `supabase/migrations/` — deal_applicable_stores 表
- `dealjoy_merchant/lib/features/deals/` — 创建 Deal 表单添加门店选择
- `supabase/functions/merchant-deals/index.ts` — 保存适用门店
- `deal_joy/lib/features/deals/` — 用户端展示适用门店

---

## Phase 7: 完成核销逻辑改造（#44-#47）

### 待完成
1. 核销时校验逻辑：
   - 先查 deal_applicable_stores 有无记录
   - 有记录 → 检查当前门店是否在适用范围内
   - 无记录 → 走原逻辑 deals.merchant_id == 当前门店
2. orders 表确保有 redeemed_merchant_id 字段
3. 核销成功时写入 redeemed_merchant_id = 当前门店
4. 错误提示：
   - "This voucher is not valid at this location. Valid at: [门店列表]"
   - 其他错误（已使用/已退款/已过期）保持不变

### 涉及文件
- `supabase/functions/merchant-scan/index.ts` — 核销校验逻辑
- `supabase/migrations/` — orders.redeemed_merchant_id

---

## Phase 8: 完成结算与提现（#48-#61）

### 待完成
1. 结算逻辑：钱结算给 redeemed_merchant_id（实际核销的门店）
2. 已核销订单 T+7 天后进入可提现余额
3. 退款自动从余额扣除
4. 每家门店绑定 Stripe Connect（merchants 表有 stripe_connect_id）
5. **提现页面**：
   - 可提现余额展示
   - 手动提现按钮（仅门店老板可见）
   - 自动提现设置（仅门店老板可见）
   - 提现记录列表
6. 绑定/修改银行账户（仅门店老板）
7. 店长可查看财务和提现记录，不能提现
8. 品牌管理员可查看每家门店的提现记录，不能替门店提现

### Flutter Key 要求
- `earnings_withdraw_btn` — 提现按钮（仅门店老板可见）
- `earnings_auto_withdraw_toggle` — 自动提现开关
- `earnings_bank_account_btn` — 修改银行账户

### 涉及文件
- `supabase/functions/merchant-earnings/index.ts` — 结算和提现 API
- `dealjoy_merchant/lib/features/earnings/` — 提现页面
- Stripe Connect 集成

---

## Phase 9: 完成闭店功能（#62-#68）

### 待完成
1. 仅门店老板可在设置里发起闭店
2. 闭店前处理：
   - 未核销的券全部自动退款
   - 待结算金额正常结算完
   - 提示提现余额
3. 闭店后：状态变 "Closed"，用户端搜不到
4. 历史数据保留
5. 连锁店闭店自动从品牌脱离

### Flutter Key 要求
- `settings_close_store_btn` — 闭店按钮
- `close_store_confirm_btn` — 确认闭店

### 涉及文件
- `supabase/functions/merchant-store/index.ts` — 闭店 API
- `dealjoy_merchant/lib/features/settings/` — 闭店入口和确认流程

---

## Phase 10: 完成解除品牌合作（#69-#82）

### 待完成
1. 门店老板 "Leave Brand" 功能
2. 品牌老板 "Remove Store" 功能
3. 解除后：brand_id 清空、品牌管理员失去权限、品牌通用 Deal 移除该门店
4. 用户已购券处理：
   - 查出受影响的未核销券
   - 给用户发通知："[门店] is no longer participating..."
   - 券详情页该门店显示删除线 + "No longer available"
   - 新增 "Request Refund" 按钮
   - Deal 无任何适用门店时 → 自动全额退款

### Flutter Key 要求
- `settings_leave_brand_btn` — 门店退出品牌
- `brand_manage_remove_store_{merchantId}` — 品牌踢出门店

### 涉及文件
- `supabase/functions/merchant-brand/index.ts` — leave/remove 路由
- `supabase/functions/` — 通知和退款逻辑
- `deal_joy/lib/features/orders/` — 用户端券详情页改动

---

## Phase 11: 完成用户端改动（#83-#88）

### 待完成
1. 搜索品牌名时所有门店按距离出现
2. 商家详情页显示品牌 Logo + 品牌名 + "X locations"
3. Recommended tab 增加 "Other Locations" section
4. 多店通用 Deal 显示 "Available at X locations" + 门店列表
5. 券面标注适用门店
6. 解除合作后受影响的券显示变更信息 + 退款按钮

### 涉及文件
- `deal_joy/lib/features/deals/` — 搜索、详情页、Deal 详情
- `deal_joy/lib/features/orders/` — 券详情

---

## 每完成一个 Phase 后的测试流程

### Step 1: 给该 Phase 涉及的 Widget 加 Key

检查所有新增/修改的页面，确保每个可交互组件都有 ValueKey。
参考每个 Phase 下面列出的 "Flutter Key 要求"。

### Step 2: Build 并安装

```bash
cd "/Users/howardshansmac/github/coupon app/coupon-app/dealjoy_merchant"
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

### Step 3: 用 Maestro Studio 确认实际 UI

```bash
maestro studio
```

在 Studio 中手动走一遍该 Phase 的功能流程：
- 用 Element Inspector 查看每个按钮、输入框的**实际文字和 ID**
- 记录页面跳转后**实际显示的文字**
- 确认多个相似按钮的区分方式

### Step 4: 基于实际 UI 生成 Maestro 测试脚本

在 `.maestro/flows/{模块}/` 下创建 YAML 文件。

必须遵守：
- 用 ValueKey（`id:`）定位，不用显示文字
- 每个等待步骤带 `timeout: 15000`
- 多个相似按钮用 Key 或 `below:` 区分
- 需要登录的用例引用 `shared/login.yaml`
- 非关键步骤加 `optional: true`

### Step 5: 运行测试

```bash
maestro test .maestro/flows/{模块}/ --format junit --output .maestro/report/{模块}/
```

### Step 6: 分析并修复

- PASS → 进入下一个 Phase
- FAIL → 分析原因：
  1. **测试脚本问题**（Key 写错、文字不匹配）→ 修 YAML → 重跑
  2. **代码问题**（功能没实现、逻辑错误）→ 修代码 → 回到 Step 2 重新 build
  3. **超时卡死**（元素确实找不到）→ 检查该 Widget 是否有 Key、是否渲染了 → 修代码或修脚本
- 循环直到全部 PASS

---

## Maestro 测试目录结构

```
dealjoy_merchant/.maestro/
├── config.yaml
├── shared/
│   ├── login.yaml                    # 普通商家登录
│   ├── login_brand_admin.yaml        # 品牌管理员登录
│   └── login_cashier.yaml            # 核销员登录
├── flows/
│   ├── phase01_registration/
│   │   ├── TC_register_single.yaml
│   │   ├── TC_register_multi.yaml
│   │   ├── TC_upgrade_to_chain.yaml
│   │   └── ...
│   ├── phase02_permissions/
│   │   ├── TC_cashier_only_scan_orders.yaml
│   │   ├── TC_service_scan_orders_reviews.yaml
│   │   ├── TC_manager_all_except_settings.yaml
│   │   └── ...
│   ├── phase03_login_routing/
│   ├── phase04_brand_management/
│   ├── phase05_staff_management/
│   ├── phase06_deal_multi_store/
│   ├── phase07_scan_validation/
│   ├── phase08_earnings_withdrawal/
│   ├── phase09_close_store/
│   ├── phase10_leave_brand/
│   └── phase11_user_app/
└── report/
```

---

## 全部 Phase 完成后

### 1. 全量测试

```bash
maestro test .maestro/flows/ --format junit --output .maestro/report/full/
```

### 2. 生成测试报告 Excel

用 python3 + openpyxl 创建 `/Users/howardshansmac/github/coupon app/DealJoy_MultiStore_Test_Report.xlsx`：

**Sheet 1 "Test Results"：**
| TC # | Phase | Feature (功能点编号) | Test Description | Steps | Expected | Status (PASS/FAIL) | Failure Reason | Fixed |

**Sheet 2 "Summary"：**
| Phase | Total | Pass | Fail | Pass Rate |

**Sheet 3 "Issues Found"：**
| TC # | Issue Description | Root Cause (code/script/data) | Fix Applied | Verified |

### 3. 输出汇总报告

```
=== DealJoy Multi-Store System Test Report ===
Total Features: 93
Implemented: 93/93
Test Cases: XX
Passed: XX
Failed: XX
Pass Rate: XX%

Phase breakdown:
Phase 1 (Registration): X/X passed
Phase 2 (Permissions): X/X passed
Phase 3 (Login Routing): X/X passed
Phase 4 (Brand Management): X/X passed
Phase 5 (Staff Management): X/X passed
Phase 6 (Deal Multi-Store): X/X passed
Phase 7 (Scan Validation): X/X passed
Phase 8 (Earnings/Withdrawal): X/X passed
Phase 9 (Close Store): X/X passed
Phase 10 (Leave Brand): X/X passed
Phase 11 (User App): X/X passed
```

---

## 执行规则

1. 按 Phase 1 → 11 顺序执行，不要跳跃
2. 每个 Phase 内部按功能点编号顺序完成
3. 后端改动写到共享 Supabase 目录
4. 商家端代码只改 dealjoy_merchant/
5. 用户端代码只改 deal_joy/
6. UI 文案全英文，注释可中文
7. 使用 ConsumerWidget + Riverpod
8. **每个 Phase 完成后必须跑 Maestro 测试，不要等全部做完再测**
9. **写测试脚本前必须先用 maestro studio 确认实际 UI**
10. **所有可交互 Widget 必须有 ValueKey**
11. **所有等待步骤必须带 timeout**
12. 修复代码后要重新 flutter build apk + adb install
13. 如果遇到无法解决的问题，记录在 Notes 里继续下一个 Phase，不要卡住
