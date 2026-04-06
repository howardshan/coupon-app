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
- 扩展（2026-03）：`myWrittenReviewsProvider`、`pending_reviews_provider`（`toReviewProvider`）、聚合页 `/my-reviews`、已用券详情「Your Review」、My Coupons Used 评价提示、**My Coupons 顶层 Tab「Reviews」含子 Tab Pending | Submitted**（用户明确要求）
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

#### Brand Deal 创建 + 审批 + 客户端展示 ✅
- 状态：已完成，品牌 Deal 创建、门店确认、客户端搜索和商家详情页展示测试通过
- 改动内容：
  - 修复 RPC 函数 `search_deals_by_city` / `search_deals_nearby` 的 `m.city` 类型不匹配 bug（`varchar(50)` → `::TEXT`）
  - 用户端商家详情页 `fetchActiveDeals` 增加 `deal_applicable_stores` 关联查询，子门店可展示品牌 Deal
  - `pendingStoreDealsProvider` 改为 `.autoDispose`，修复切换账号后缓存旧结果的 bug
- 受保护文件：
  - `deal_joy/supabase/migrations/20260312000002_rpc_deal_applicable_stores.sql` — `m.city::TEXT` 转换
  - `deal_joy/lib/features/merchant/data/repositories/store_detail_repository.dart` — `fetchActiveDeals()` 含 `deal_applicable_stores` 关联查询
  - `deal_joy/lib/features/deals/data/repositories/deals_repository.dart` — `_filterBrandDealsWithActiveStores()`
  - `dealjoy_merchant/lib/features/deals/providers/deals_provider.dart` — `pendingStoreDealsProvider`（`.autoDispose`）
  - `dealjoy_merchant/lib/features/deals/pages/store_deal_confirm_page.dart`
  - `dealjoy_merchant/lib/features/dashboard/pages/dashboard_page.dart` — `_PendingBrandDealsBanner`

#### Brand 鉴权 + 门店切换 ✅
- 状态：已完成，品牌管理员识别、门店切换、默认门店逻辑测试通过
- 改动内容：
  - `resolveAuth()` 品牌管理员检测（brand_admins 表）+ 角色映射
  - 默认 merchantId 优先使用用户自己拥有的门店，而非品牌下第一家
  - StoreSelector 门店切换组件（品牌管理员专用）
  - Dashboard ShortcutGrid 品牌入口（仅 `isBrandAdmin` 可见）
- 受保护文件：
  - `deal_joy/supabase/functions/_shared/auth.ts` — `resolveAuth()` 品牌管理员检测逻辑、角色权限映射、默认 merchantId 选择
  - `dealjoy_merchant/lib/features/store/widgets/store_selector.dart`（整个文件）
  - `dealjoy_merchant/lib/features/store/providers/store_provider.dart` — `isBrandAdmin`、`switchStore()` 逻辑
  - `dealjoy_merchant/lib/features/dashboard/widgets/shortcut_grid.dart` — Brand 入口条件判断

#### Brand Logo 上传 + 客户端展示 ✅
- 状态：已完成，商家端品牌 Logo 上传、客户端 Chain 标识 + 品牌 Badge 展示测试通过
- 改动内容：
  - Brand Info 页面支持品牌 Logo 上传（image_picker → Supabase Storage `merchant-photos/brand-logos/`）
  - 客户端 DealCard 图片右上角 Chain 标识（品牌 Logo 16px + "Chain" 文字，半透明黑底）
  - 客户端 DealCard 信息区品牌 Badge（品牌 Logo 14px + 品牌名，连锁店显示）
  - 客户端 DealDetailScreen、DealCardHorizontal、DealCardV2 品牌 Badge
- 受保护文件：
  - `dealjoy_merchant/lib/features/store/pages/brand_info_page.dart` — `_pickAndUploadLogo()` Logo 上传逻辑
  - `deal_joy/lib/features/deals/presentation/widgets/deal_card.dart` — `_DealCardBrandBadge`、Chain 标识（`isChainStore` 判断 + Positioned badge）
  - `deal_joy/lib/features/deals/presentation/screens/deal_detail_screen.dart` — `_DetailBrandBadge`
  - `deal_joy/lib/features/merchant/presentation/widgets/deal_card_horizontal.dart` — `_HorizontalBrandBadge`
  - `deal_joy/lib/features/merchant/presentation/widgets/deal_card_v2.dart` — `_V2BrandBadge`
  - `deal_joy/lib/features/deals/data/models/deal_model.dart` — `MerchantSummary.isChainStore`、`brandLogoUrl`、`brandName` 字段

#### 首页固定头部 ✅
- 状态：已完成，城市选择器 + 通知图标始终固定在顶部
- 改动内容：
  - SliverAppBar 重构：城市+通知从 FlexibleSpaceBar 移至 `title`（始终固定）
  - 搜索栏移至 `bottom: PreferredSize`
- 受保护文件：
  - `deal_joy/lib/features/deals/presentation/screens/home_screen.dart` — SliverAppBar `title`（城市+通知）、`bottom`（搜索栏）结构

---

### Admin 管理端（admin/）

#### Deal Sort Order ✅
- 状态：已完成，排序功能测试通过
- 受保护文件：
  - `admin/components/deal-sort-order.tsx`
  - `admin/app/actions/admin.ts` — `updateDealSortOrder`
  - `admin/app/(dashboard)/deals/page.tsx` — sort_order 列

#### Admin 邮件侧栏 + Email Log ✅
- 状态：已完成，侧栏「Email」分组展开（Email Settings / Email Log），日志列表分页 + HTML 预览
- 受保护文件：
  - `admin/components/sidebar.tsx` — admin 导航含 Email 分组
  - `admin/app/(dashboard)/settings/email-logs/page.tsx`
  - `admin/components/email-logs-table.tsx`
  - `admin/app/actions/email-logs.ts` — `getEmailLogHtmlBody`

#### Admin 商户活动时间线（审计表）✅
- 状态：已完成，`merchant_activity_events` 记录申请/审批/上下线/闭店；商户详情页时间线合并展示；管理员可强制上下线
- 受保护文件：
  - `deal_joy/supabase/migrations/20260402140000_merchant_activity_events.sql`
  - `deal_joy/supabase/functions/_shared/merchant_activity_log.ts`
  - `admin/lib/merchant-activity-events.ts`、`admin/lib/merchant-admin-timeline.ts`
  - `admin/app/actions/admin.ts` — `approveMerchant` / `rejectMerchant` / `revokeMerchantApproval` / `adminSetMerchantStoreOnline` 与审计写入
  - `admin/components/merchant-admin-visibility-actions.tsx`
  - `deal_joy/supabase/functions/merchant-register/index.ts`、`merchant-dashboard/index.ts`、`merchant-store/index.ts` — 对应审计写入

#### Admin 退款争议活动时间线（Phase 3）✅
- 状态：已完成，订单详情侧栏与审批中心 Refund Dispute 抽屉展示 `refund_requests` 里程碑；同单多争议合并排序；仲裁后 `revalidatePath` 刷新订单页
- 受保护文件：
  - `admin/lib/refund-dispute-admin-timeline.ts`
  - `admin/app/(dashboard)/orders/[id]/page.tsx` — Refund dispute timeline 查询与挂载
  - `admin/app/(dashboard)/approvals/page.tsx` — `RefundDisputeItem` 字段与 `fetchRefundDisputes` / 统一 Tab 批量查询
  - `admin/components/approvals/refund-dispute-drawer.tsx` — 抽屉内时间线
  - `admin/app/actions/approvals.ts` — `approveRefundDispute` / `rejectRefundDispute` 成功后 `revalidatePath(/orders/[id])`

#### Admin 售后活动时间线（Phase 4）✅
- 状态：已完成，审批中心 After-Sales 抽屉使用通用 `AdminActivityTimelineCard`；`timeline` JSONB 经 `buildAfterSalesTimelineEntries` 映射；条目附件链接保留
- 受保护文件：
  - `admin/lib/after-sales-admin-timeline.ts`
  - `admin/components/approvals/after-sales-drawer.tsx`
  - `admin/lib/admin-activity-timeline-types.ts` — 可选 `attachments` 字段（与各域 builder 共用）
  - `admin/components/admin-activity-timeline-card.tsx` — 多行 subtitle、附件链接展示

#### Admin 审批中心抽屉活动时间预览（Phase 5）✅
- 状态：已完成，Deal/Merchant 抽屉内 `AdminActivityTimelineCard` 预览（与详情页 builder 一致）；After-Sales 详情含 `order_id` 时链至订单页；Refund 抽屉补充订单页说明
- 受保护文件：
  - `admin/components/approvals/deal-drawer.tsx`、`merchant-drawer.tsx`、`refund-dispute-drawer.tsx`、`after-sales-drawer.tsx`
  - `admin/app/(dashboard)/approvals/page.tsx` — `DealItem` 与 `fetchDeals` / All Tab deals 查询字段
  - `admin/app/api/approvals/merchant/[id]/route.ts` — `updated_at`

---

## 更新记录

| 日期 | 更新内容 | 操作人 |
|------|----------|--------|
| 2026-03-12 | 初始化文件，录入已知完成模块 | Claude |
| 2026-03-12 | 多店 Deal 门店确认机制全部实施完成 | Claude |
| 2026-03-12 | Brand Management 改版 + 门店确认入口 + Brand Deals 过滤 | Claude |
| 2026-03-13 | Brand Deal 创建/审批/客户端展示 — RPC 类型修复 + 商家详情页关联查询 + provider autoDispose | Claude |
| 2026-03-13 | Brand 鉴权/门店切换 + Logo 上传/客户端展示 + 首页固定头部 — 全部加入保护清单 | Claude |
| 2026-03-21 | Admin 侧栏 Email 分组 + Email Log 页面与预览 Action | Claude |
| 2026-03-30 | Admin 退款争议活动时间线（订单详情 + Refund 抽屉 + revalidate） | Claude |
| 2026-03-30 | Admin 售后时间线统一通用卡片 + `after-sales-admin-timeline.ts` | Claude |
| 2026-03-30 | Admin Phase 5：审批抽屉 Activity preview + 订单跳转与说明 | Claude |

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
