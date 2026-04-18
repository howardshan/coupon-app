# 任务开始前必做（最高优先级）
- **每次开始新任务前，必须读取项目根目录的 `COMPLETED.md`**
- 判断任务是否涉及已完成模块的受保护文件
- 如果涉及：先向用户说明原因，等待确认后才能修改
- 可用 `/protected` slash command 快速检查规则

# 沟通规则（最高优先级）
- **所有与用户的对话和解释必须用中文回复**
- **代码注释用中文**
- **代码本身（变量名、函数名、类名等）和 UI 文案用英文**

# 项目路径规则（最高优先级）
- **用户端（deal_joy）**: `/Users/howardshansmac/github/coupon app/coupon-app/deal_joy/`
- **商家端（dealjoy_merchant）**: `/Users/howardshansmac/github/coupon app/coupon-app/dealjoy_merchant/`
- **Supabase 后端（migrations + functions）**: `/Users/howardshansmac/github/coupon app/coupon-app/deal_joy/supabase/`
- 两个 Flutter 项目代码互不交叉修改
- Supabase 相关文件（migrations, functions）统一在 deal_joy/supabase/ 下

# DealJoy — 本地生活团购平台

## 项目概述
北美 Dallas 地区本地生活团购平台，核心差异化：**"随时买，随时退"** — 无条件即时退款。
两个独立 Flutter App + 共享 Supabase 后端。

## 技术栈
- **前端**: Flutter 3.x + Dart ^3.11.0
- **状态管理**: Riverpod 2.6.1 (flutter_riverpod), **AsyncNotifier 模式**
- **导航**: go_router 14.3.0
- **后端**: Supabase 2.8.0 (PostgreSQL, Edge Functions/Deno, Auth, Storage)
- **支付**: Stripe (flutter_stripe ^11.1.0, 仅 customer app)

## 用户端（deal_joy）目录结构
```
deal_joy/lib/
├── main.dart
├── app.dart                        # DealJoyApp 根 Widget
├── core/
│   ├── config/env.dart             # flutter_dotenv 环境变量
│   ├── constants/app_constants.dart
│   ├── theme/app_theme.dart
│   ├── errors/app_exception.dart
│   ├── widgets/main_scaffold.dart  # 4-tab 底部导航
│   └── router/app_router.dart      # go_router
├── features/                       # Feature-First Clean Architecture
│   ├── auth/          # ✅ email+password, Google Sign-In
│   ├── deals/         # ✅ HomeScreen, DealDetail, search, collection
│   ├── checkout/      # ⚠️ Stripe 支付流程
│   ├── orders/        # ✅ 订单列表, QR coupon
│   ├── reviews/       # ✅ 评价系统
│   ├── profile/       # ⚠️ 个人中心
│   ├── merchant/      # ⚠️ 商家详情页
│   ├── chat/          # ❌ 占位
│   └── cart/          # ❌ 占位
└── shared/providers/, widgets/
```

## 用户端模块目录约定（必须严格遵循）
```
features/{module}/
├── data/
│   ├── models/         # 数据模型（DealModel, MerchantSummary 等）
│   └── repositories/   # Repository（直接查 Supabase 表 + RPC 函数）
├── domain/
│   └── providers/      # Riverpod Providers
└── presentation/
    ├── screens/        # XxxScreen 页面
    └── widgets/        # 模块内组件
```

## 用户端数据层关键点
- **Repository 直接查 Supabase 表**，不走 Edge Function
- deals 查询用 join: `merchants(id, name, logo_url, phone, homepage_cover_url)`
- 搜索用 RPC: `search_deals_nearby()` / `search_deals_by_city()`
- RPC 返回扁平结构，用 `DealModel.fromSearchJson()` 解析（字段名带 `merchant_` 前缀）
- 普通查询返回嵌套结构，用 `DealModel.fromJson()` 解析（merchants 是嵌套对象）

## 用户端导航
底部 4 Tab: `/home` | `/chat` | `/cart` | `/profile`
主要路由: `/deals/:id`, `/checkout/:dealId`, `/merchant/:id`, `/search`, `/orders`, `/collection`, `/coupons`

## Supabase 后端
### Edge Functions（16个，Deno/TypeScript）
核心: `create-payment-intent`, `create-refund`, `auto-refund-expired`, `stripe-webhook`
商家: `merchant-register`, `merchant-store`, `merchant-deals`, `merchant-dashboard`,
      `merchant-scan`, `merchant-orders`, `merchant-earnings`, `merchant-reviews`,
      `merchant-analytics`, `merchant-notifications`, `merchant-marketing`, `merchant-influencer`

### RPC 函数
- `search_deals_nearby(p_lat, p_lng, p_radius_m, p_category, p_limit, p_offset)` → 返回 `merchant_homepage_cover_url`
- `search_deals_by_city(p_city, p_user_lat, p_user_lng, p_category, p_limit, p_offset)` → 返回 `merchant_homepage_cover_url`

### 主要表
users, merchants, deals, orders, coupons, reviews, payments, saved_deals, categories,
merchant_photos, merchant_hours, merchant_documents, deal_images

## 代码规范
- **UI 全英文**（面向北美市场），注释用中文
- Riverpod AsyncNotifier 模式（**不要用 setState**）
- 每张 Supabase 表必须有 RLS 策略
- Model 的 `fromJson` 所有字段必须 null-safe（`as String? ?? ''`），避免 `null as String` 崩溃
- 严格遵循现有目录结构，不要创建新的目录层级

## 常见错误（必须避免）
1. **fromJson 硬转换**: 写 `json['x'] as String` 而不是 `json['x'] as String? ?? ''` → null 时崩溃
2. **Edge Function select 不全**: join 子查询没有 select 某字段，但 Dart model 期望该字段
3. **RPC 字段名不同**: RPC 返回的是 `merchant_name`, `merchant_logo_url` 等带前缀的扁平结构，不是嵌套的 `merchants` 对象
4. **PostgreSQL 函数改返回类型**: 不能 CREATE OR REPLACE，必须先 DROP FUNCTION 再 CREATE
5. **Edge Function 本地改了没部署**: 需要 `supabase functions deploy <name>` 或在 Dashboard 更新

## 禁止修改的模块（除非用户明确命令）
### Deal Category 分类系统
以下文件的 Deal Category 相关逻辑**禁止修改**，除非用户明确命令要求：
- `dealjoy_merchant/lib/features/deals/models/deal_category.dart`
- `dealjoy_merchant/lib/features/deals/services/deals_service.dart` — fetchDealCategories, createDealCategory, updateDealCategory, deleteDealCategory
- `dealjoy_merchant/lib/features/deals/providers/deals_provider.dart` — dealCategoriesProvider, dealsServiceProvider
- `dealjoy_merchant/lib/features/deals/pages/deal_create_page.dart` — _buildDealCategoryDropdown()
- `dealjoy_merchant/lib/features/deals/pages/deal_edit_page.dart` — _buildDealCategoryDropdown()
- `dealjoy_merchant/lib/features/deals/pages/deals_list_page.dart` — _CategoryManagerSheet
- `dealjoy_merchant/lib/features/deals/models/merchant_deal.dart` — dealCategoryId 字段
- `deal_joy/supabase/functions/merchant-deals/index.ts` — deal_category_id, deal_type, badge_text 相关逻辑
- DB 表 `deal_categories`

### 客户端 Deal 详情页
以下文件**禁止修改**，除非用户明确命令要求：
- `deal_joy/lib/features/deals/presentation/screens/deal_detail_screen.dart` — 整个文件（图片画廊、套餐吸顶选择器、价格区、详情区、底部栏等所有布局逻辑）

### 客户端认证页面（登录、注册、验证）
以下文件**禁止修改**，除非用户明确命令要求：
- `deal_joy/lib/features/auth/presentation/screens/login_screen.dart`
- `deal_joy/lib/features/auth/presentation/screens/register_screen.dart`
- `deal_joy/lib/features/auth/presentation/screens/verify_otp_screen.dart`
- `deal_joy/lib/features/auth/presentation/screens/welcome_screen.dart`
- `deal_joy/lib/features/auth/data/repositories/auth_repository.dart` — signUp/signIn/isUsernameTaken/isEmailTaken 逻辑

### 客户端 Gifted 赠送券功能
以下文件的赠送券过滤、状态展示、Gift 详情逻辑**禁止修改**，除非用户明确命令要求：
- `deal_joy/lib/features/orders/domain/providers/coupons_provider.dart` — couponsByStatusProvider 中 gifted/expired case 分支逻辑
- `deal_joy/lib/features/orders/presentation/widgets/coupon_card.dart` — customerStatus == 'gifted' 判断、displayStatus、QR 码隐藏逻辑
- `deal_joy/lib/features/orders/presentation/screens/coupon_screen.dart` — _StatusBanner 中 customerStatus == 'gifted' 判断、_CouponDetailBody 中 gifted 分支（QR 隐藏 + GiftInfoSection 展示）
- `deal_joy/lib/features/orders/data/models/coupon_gift_model.dart` — GiftStatus 枚举、CouponGiftModel 数据模型
- `deal_joy/lib/features/orders/presentation/widgets/gift_bottom_sheet.dart` — GiftBottomSheet 赠送弹窗
- `deal_joy/supabase/functions/auto-refund-expired/index.ts` — customer_status == 'gifted' 的过期退款逻辑、C15 邮件通知

### 客户端 Payment Methods 支付方式管理
以下文件**禁止修改**，除非用户明确命令要求：
- `deal_joy/lib/features/profile/presentation/screens/payment_methods_screen.dart` — 整个文件（卡片列表、编辑卡片表单、操作弹层、添加新卡 Stripe 流程）
- `deal_joy/lib/features/profile/data/repositories/payment_methods_repository.dart` — Stripe API 调用逻辑
- `deal_joy/lib/features/profile/domain/providers/payment_methods_provider.dart` — paymentMethodsProvider、updateCard、setDefault、deleteCard
- `deal_joy/lib/features/profile/data/models/saved_card_model.dart` — SavedCard 数据模型

### 客户端 Near Me / 城市切换功能
以下文件的地区切换、Near Me GPS 搜索、城市模式搜索相关逻辑**禁止修改**，除非用户明确命令要求：
- `deal_joy/lib/features/deals/domain/providers/deals_provider.dart` — selectedLocationProvider, isNearMeProvider, dealsListProvider 中 Near Me / 城市分支逻辑
- `deal_joy/lib/features/merchant/domain/providers/merchant_provider.dart` — merchantListProvider 中 Near Me / 城市分支逻辑
- `deal_joy/lib/features/merchant/data/repositories/merchant_repository.dart` — fetchMerchants() 的 city 过滤、fetchMerchantsNearby() RPC 调用
- `deal_joy/lib/features/deals/data/repositories/deals_repository.dart` — searchDealsNearby()、searchDealsByCity() RPC 调用
- `deal_joy/lib/features/deals/domain/providers/deals_provider.dart` — featuredDealsProvider、userLocationProvider 逻辑
- DB RPC 函数 `search_deals_nearby`、`search_deals_by_city`、`search_merchants_nearby`（含返回字段、排序、Haversine 距离计算）

### 客户端 Sales Tax 全链路
以下文件的税费计算、展示、退款含税逻辑**禁止修改**，除非用户明确命令要求：
- `deal_joy/lib/features/checkout/domain/providers/tax_rate_provider.dart` — metroTaxRatesProvider、cartTaxEstimateProvider、singleDealTaxEstimateProvider
- `deal_joy/lib/features/checkout/presentation/screens/checkout_screen.dart` — Tax (est.) 行展示、_lastBackendTotalTax 后端值刷新、onPaymentBreakdown 回调
- `deal_joy/lib/features/checkout/data/repositories/checkout_repository.dart` — onPaymentBreakdown 参数、totalTax 透传
- `deal_joy/lib/features/checkout/presentation/screens/order_success_screen.dart` — Subtotal / Tax / Amount Paid 拆分展示
- `deal_joy/lib/features/orders/presentation/screens/order_detail_screen.dart` — Price Breakdown Tax 行、Paid 含税金额
- `deal_joy/lib/features/orders/presentation/screens/coupon_screen.dart` — Refund Details 含税拆分（Vouchers / Subtotal / Tax / Refunded To）、_RefundDetailsCard
- `deal_joy/lib/features/orders/presentation/screens/refund_request_screen.dart` — 退款金额 Subtotal + Tax 拆分
- `deal_joy/lib/features/orders/presentation/screens/orders_screen.dart` — 订单卡片 Tax 行
- `deal_joy/lib/features/orders/data/models/order_model.dart` — taxAmount 字段
- `deal_joy/lib/features/orders/data/models/order_item_model.dart` — taxAmount、taxRate、usageDays、usageNotes 字段
- `deal_joy/lib/features/orders/data/models/order_detail_model.dart` — taxAmount 字段
- `deal_joy/lib/features/orders/data/models/coupon_model.dart` — taxAmount、taxRate 字段、isExpired 按商家时区 +30h 判断
- `deal_joy/supabase/functions/create-order-v3/index.ts` — per-item 税费计算 + tax_metro_area 快照写入
- `deal_joy/supabase/functions/create-payment-intent/index.ts` — 按 merchant.metro_area 查 metro_tax_rates 计税
- `deal_joy/supabase/functions/user-order-detail/index.ts` — tax_amount / tax_rate / usageDays / usageNotes 返回
- `deal_joy/supabase/migrations/20260413000001_tax_revenue_report.sql` — tax_metro_area 字段 + get_tax_revenue_report RPC
- DB 表 `metro_tax_rates`、`order_items.tax_amount`、`order_items.tax_rate`、`order_items.tax_metro_area`

### 客户端 Voucher Detail 页面
以下文件**禁止修改**，除非用户明确命令要求：
- `deal_joy/lib/features/orders/presentation/screens/voucher_detail_screen.dart` — _UnusedVouchersByOrderSection（券列表）、_DealInfoBlock（公共信息卡片：Valid Until / Available / Notes / Usage Rules / Refund Policy）、_VoucherQuickActions（Gift 按钮条件 unusedOrderItemIds.isNotEmpty）、QR 弹层 initialPage 定位
- `deal_joy/lib/features/orders/data/repositories/orders_repository.dart` — _orderSelect（含 tax_amount、tax_rate、usage_days、usage_rules、usage_notes、refund_policy、expires_at）
- `deal_joy/lib/features/orders/data/repositories/coupons_repository.dart` — _couponSelect（含 tax_amount、tax_rate）

### 客户端 Review 评价系统（维度评分 + 星级筛选 + 同名 deal 聚合）
以下文件**禁止修改**，除非用户明确命令要求：
- `deal_joy/lib/features/deals/data/repositories/deals_repository.dart` — fetchReviewsByDeal 按同 merchant + 同 title 聚合所有 deal 评价
- `deal_joy/lib/features/deals/data/models/review_model.dart` — storeName 字段
- `deal_joy/lib/features/deals/presentation/screens/deal_detail_screen.dart` — _ReviewsSection（星级筛选 chips + 评价数量 + actualRating/actualCount）、_RatingFilterChip、_RestaurantInfo 头部 actualRating/actualReviewCount
- `deal_joy/lib/features/merchant/presentation/screens/merchant_detail_screen.dart` — _buildReviewsSection 星级筛选 chips + _selectedReviewStar + _buildFilterChip
- `deal_joy/lib/features/merchant/presentation/widgets/review_stats_header.dart` — 维度评分进度条（Overall / Environment / Product / Service）
- `deal_joy/lib/features/merchant/presentation/widgets/review_card.dart` — storeName 门店来源标签
- `deal_joy/lib/features/merchant/data/models/review_stats_model.dart` — avgOverall / avgEnvironment / avgProduct / avgService 字段
- `deal_joy/lib/features/merchant/data/repositories/store_detail_repository.dart` — fetchMerchantReviews 按 reviews.merchant_id 查 + join merchants(name)、fetchReviewStats 按 reviews.merchant_id
- `deal_joy/lib/features/orders/domain/providers/pending_reviews_provider.dart` — redeemed_at_merchant_id 优先关联核销门店
- DB RPC `get_merchant_review_summary` — 按 reviews.merchant_id 统计 + 维度平均分

### 客户端 Gift 赠送 + Recall 码重生成
以下文件**禁止修改**，除非用户明确命令要求：
- `deal_joy/supabase/functions/send-gift/index.ts` — 赠送后调 regenerate_coupon_codes 重生码（in_app + external 两分支）
- `deal_joy/supabase/functions/recall-gift/index.ts` — 撤回后调 regenerate_coupon_codes 重生码
- `deal_joy/supabase/migrations/20260413000006_regenerate_coupon_codes.sql` — regenerate_coupon_codes RPC
- `deal_joy/lib/features/orders/domain/providers/coupons_provider.dart` — sendGift / sendGiftToFriend 成功后 invalidate couponDetailProvider + activeGiftProvider；couponsByStatusProvider expired case 排除 used；giftCoupon 旧方法保留但不再从 UI 调用

### 商家端 Dashboard Today's Stats
以下文件**禁止修改**，除非用户明确命令要求：
- `dealjoy_merchant/lib/features/dashboard/widgets/stats_card.dart` — infoText ? 图标 + AlertDialog 说明
- `dealjoy_merchant/lib/features/dashboard/pages/dashboard_page.dart` — _StatsSection 四个 StatsCard infoText 说明文字
- `dealjoy_merchant/lib/features/earnings/models/earnings_data.dart` — EarningsTransaction.taxAmount、TransactionTotals.taxAmount 字段
- `dealjoy_merchant/lib/features/earnings/widgets/transaction_tile.dart` — Tax 行 + TransactionTotalsRow.totalTaxAmount
- DB RPC `get_merchant_daily_stats` — today_revenue 按 redeemed_at 统计净额（扣除 commission + stripe fee）
- DB RPC `get_merchant_transactions` — 含 tax_amount 列

### 好友系统 Chat 自动创建
以下文件**禁止修改**，除非用户明确命令要求：
- `deal_joy/supabase/migrations/20260413000007_friend_accept_create_chat.sql` — friend_request accepted 触发器自动创建 direct conversation + 系统欢迎消息

## 开发命令
```bash
# Flutter
cd "/Users/howardshansmac/github/coupon app/coupon-app/deal_joy" && ~/flutter/bin/flutter run -d emulator

# Supabase (需要先 supabase login)
/opt/homebrew/bin/supabase functions deploy <function-name> --no-verify-jwt --project-ref kqyolvmgrdekybjrwizx
/opt/homebrew/bin/supabase db push --project-ref kqyolvmgrdekybjrwizx

# 需求
python3 scripts/read_excel.py "<模块名>"
```
