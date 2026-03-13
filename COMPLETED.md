# DealJoy — 已完成模块清单

> **重要**：Claude Code 每次开始新任务前必须读取本文件。
> 本文件中列出的模块已测试通过，**禁止在未经用户明确确认的情况下修改**。
> 如需改动，必须先说明原因并等待确认。

---

## 如何使用本文件

1. 任务开始前读取本文件
2. 判断本次任务是否涉及下方任何受保护文件
3. 如果涉及：向用户说明原因 → 等待确认 → 再修改
4. 任务完成后：将新完成的模块补充到本文件

---

## 已完成模块

### 用户端（deal_joy）

#### Auth 认证模块 ✅
- 状态：已完成，email+password + Google Sign-In 测试通过
- 受保护文件：
  - `deal_joy/lib/features/auth/`（整个目录）

#### Deals 首页 + 详情 ✅
- 状态：已完成，首页展示、Deal 详情、搜索、收藏测试通过
- 受保护文件：
  - `deal_joy/lib/features/deals/data/repositories/deals_repository.dart`
  - `deal_joy/lib/features/deals/data/models/deal_model.dart`
  - `deal_joy/lib/features/deals/domain/providers/` — `featuredDealsProvider`、`fetchFeaturedDeals()`
  - `deal_joy/lib/features/deals/presentation/screens/home_screen.dart`
  - `deal_joy/lib/features/deals/presentation/screens/deal_detail_screen.dart`
  - 首页水平滚动券 UI widgets
- 注意：`deals.sort_order` 字段逻辑**绝对不动**

#### Orders 订单 + QR Coupon ✅
- 状态：已完成，订单列表、QR 码券展示测试通过
- 受保护文件：
  - `deal_joy/lib/features/orders/`（整个目录）

#### Reviews 评价系统 ✅
- 状态：已完成，提交评价、展示评价测试通过
- 受保护文件：
  - `deal_joy/lib/features/reviews/`（整个目录）

---

### 商家端（dealjoy_merchant）

#### Deal Category 分类系统 ✅
- 状态：已完成，分类增删改查测试通过
- 受保护文件：
  - `dealjoy_merchant/lib/features/deals/models/deal_category.dart`
  - `dealjoy_merchant/lib/features/deals/services/deals_service.dart` — fetchDealCategories, createDealCategory, updateDealCategory, deleteDealCategory
  - `dealjoy_merchant/lib/features/deals/providers/deals_provider.dart` — dealCategoriesProvider, dealsServiceProvider
  - `dealjoy_merchant/lib/features/deals/pages/deal_create_page.dart` — `_buildDealCategoryDropdown()`
  - `dealjoy_merchant/lib/features/deals/pages/deal_edit_page.dart` — `_buildDealCategoryDropdown()`
  - `dealjoy_merchant/lib/features/deals/pages/deals_list_page.dart` — `_CategoryManagerSheet`
  - `dealjoy_merchant/lib/features/deals/models/merchant_deal.dart` — `dealCategoryId` 字段

---

### Supabase 后端

#### merchant-deals Edge Function ✅
- 状态：已完成
- 受保护文件：
  - `deal_joy/supabase/functions/merchant-deals/index.ts` — deal_category_id, deal_type, badge_text 相关逻辑

#### DB 表 ✅
- `deal_categories` 表结构**禁止修改**

#### 多店 Deal 门店确认机制 ✅
- 状态：已完成，数据库迁移 + Edge Function + 前端 UI 全部部署
- 核心：`deal_applicable_stores` 表替代 `deals.applicable_merchant_ids` 数组，支持 per-store 状态追踪
- 受保护文件：
  - `deal_joy/supabase/migrations/20260312000001_deal_applicable_stores.sql`
  - `deal_joy/supabase/migrations/20260312000002_rpc_deal_applicable_stores.sql`
  - `deal_joy/supabase/migrations/20260312000003_deal_activation_trigger.sql`
  - `deal_joy/supabase/functions/merchant-deals/index.ts` — `handleStoreConfirm()`、`deriveStoreConfirmations()`
  - `deal_joy/supabase/functions/merchant-scan/index.ts` — `checkStoreRedemptionEligibility()`
  - `dealjoy_merchant/lib/features/deals/pages/store_deal_confirm_page.dart`（新文件）
  - `deal_joy/lib/features/deals/data/models/deal_model.dart` — `activeStoreCount` 字段
  - `deal_joy/lib/features/deals/presentation/screens/deal_detail_screen.dart` — `_ApplicableStores`
- 注意：`applicable_merchant_ids` 字段仍保留，`CouponModel` 仍依赖此字段，禁止删除

#### Brand Management 品牌管理改版 ✅
- 状态：已完成，网格卡片布局 + 子路由 + Brand Deals 过滤 + 门店确认入口
- 改动内容：
  - Brand Management 页面从 3-tab 改为 5 格网格卡片（Brand Info / Stores / Admins / Deals / Overview）
  - 提取独立子页面并注册子路由 `/brand-manage/{info,stores,admins,deals}`
  - Brand Deals 列表只显示多店 Deal（`brandOnly` 参数过滤 `applicableMerchantIds` 非空）
  - Dashboard Quick Actions 添加 Brand 入口（仅品牌管理员可见）
  - Dashboard 添加 Pending Brand Deals 待确认横幅（`pendingStoreDealsProvider`）
  - 注册门店确认路由 `/deals/confirm/:dealId` → `StoreDealConfirmPage`
  - 修复 `StoreDealConfirmPage` 中 `.eq('merchant_id', ...)` → `.eq('store_id', ...)` 的 bug
- 受保护文件：
  - `dealjoy_merchant/lib/features/store/pages/brand_manage_page.dart`
  - `dealjoy_merchant/lib/features/store/pages/brand_info_page.dart`
  - `dealjoy_merchant/lib/features/store/pages/brand_stores_page.dart`
  - `dealjoy_merchant/lib/features/store/pages/brand_admins_page.dart`
  - `dealjoy_merchant/lib/features/dashboard/widgets/shortcut_grid.dart` — Brand 入口
  - `dealjoy_merchant/lib/features/deals/providers/deals_provider.dart` — `pendingStoreDealsProvider`

---

### Admin 管理端（admin/）

#### Deal Sort Order ✅
- 状态：已完成，排序功能测试通过
- 受保护文件：
  - `admin/components/deal-sort-order.tsx`
  - `admin/app/actions/admin.ts` — `updateDealSortOrder`
  - `admin/app/(dashboard)/deals/page.tsx` — sort_order 列

---

## 更新记录

| 日期 | 更新内容 | 操作人 |
|------|----------|--------|
| 2026-03-12 | 初始化文件，录入已知完成模块 | Claude |
| 2026-03-12 | 多店 Deal 门店确认机制全部实施完成 | Claude |
| 2026-03-12 | Brand Management 改版 + 门店确认入口 + Brand Deals 过滤 | Claude |

---

## 如何新增记录

当一个模块测试通过后，在对应章节添加条目，格式：

```
#### 模块名 ✅
- 状态：已完成，[测试通过的具体功能]
- 受保护文件：
  - [文件路径或目录]
```

同时在更新记录表格追加一行。
