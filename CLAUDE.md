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
