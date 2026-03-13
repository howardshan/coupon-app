# 沟通规则（最高优先级）
- **所有与用户的对话和解释必须用中文回复**
- **代码注释用中文**
- **代码本身（变量名、函数名、类名等）和 UI 文案用英文**

# 项目路径规则（最高优先级）
- **本项目（商家端）**: `/Users/howardshansmac/github/coupon app/coupon-app/dealjoy_merchant/`
- **用户端（只读参考）**: `/Users/howardshansmac/github/coupon app/coupon-app/deal_joy/`
- **Supabase 后端**: `/Users/howardshansmac/github/coupon app/coupon-app/deal_joy/supabase/`
- 商家端代码修改只改本项目路径，不改用户端路径
- Edge Functions / migrations 在 deal_joy/supabase/ 下（两个 app 共享）

# DealJoy Merchant — 商家端 App

## 项目概述
北美 Dallas 地区本地生活团购平台的**商家端独立 App**。
与用户端共享同一套 Supabase 后端，专注商家视角功能。

## 技术栈
- Flutter 3.x + Dart ^3.11.0
- Riverpod 2.6.1 (flutter_riverpod), **AsyncNotifier 模式**
- go_router 14.3.0
- supabase_flutter 2.8.0
- mobile_scanner ^6.0.3 (扫码核销)
- image_picker + cached_network_image

## 项目结构
```
dealjoy_merchant/lib/
├── main.dart
├── app_shell.dart          # 4-tab 底部导航
├── router/app_router.dart  # go_router
└── features/
    ├── merchant_auth/      # 商家注册/登录/审核
    ├── dashboard/          # 首页仪表盘
    ├── store/              # 店铺管理（基本信息、照片、营业时间、标签）
    ├── deals/              # Deal 创建与管理
    ├── scan/               # QR 核销
    ├── orders/             # 订单管理
    ├── earnings/           # 收益/结算
    ├── reviews/            # 评价管理
    ├── analytics/          # 数据分析
    ├── notifications/      # 通知
    ├── marketing/          # 营销工具
    ├── influencer/         # 达人合作
    ├── menu/               # 菜品/菜单管理
    └── settings/           # 账户设置
```

## 模块目录约定（必须严格遵循，与用户端不同！）
```
features/{module}/
├── models/       # 数据模型（MerchantDeal, StoreInfo, DealImage 等）
├── services/     # XxxService — 调 Edge Function 的业务逻辑层
├── providers/    # Riverpod AsyncNotifier Providers
├── pages/        # XxxPage 页面级 Widget
└── widgets/      # XxxCard, XxxTile 模块组件
```

## 数据层关键点（与用户端完全不同！）
- **商家端通过 Edge Function 访问数据**，不直接查表
- `DealsService` 调 `merchant-deals` Edge Function
- `StoreService` 调 `merchant-store` Edge Function
- Edge Function 返回的 JSON 结构和 Supabase 直接查表返回的不同！
- **Edge Function select 的字段可能不全** → Dart model 的 fromJson 必须全部 null-safe

## Edge Function 返回格式（关键参考）
### merchant-store GET
```json
{ "store": {...}, "photos": [...], "hours": [...] }
```
- StoreInfo.fromJson 先取 `json['store']`，再取 `json['photos']` 和 `json['hours']`

### merchant-deals GET
```json
{ "deals": [{ ...deal, "deal_images": [{id, image_url, sort_order, is_primary}] }] }
```
- 注意: deal_images 只 select 4 个字段，**没有 created_at, deal_id**
- MerchantDeal.fromJson 的所有字段必须 null-safe

### merchant-deals POST/PATCH (create/update deal)
```json
{ "deal": { ...all_columns } }
```
- 返回 `.select()` 全字段，但不包含 deal_images join

## 导航
底部 4 Tab: `/dashboard` | `/scan` | `/orders` | `/me`
主要路由: `/store`, `/deals`, `/deals/create`, `/deals/:dealId`, `/deals/confirm/:dealId`, `/reviews`, `/analytics`, `/earnings`
品牌管理: `/brand-manage`, `/brand-manage/info`, `/brand-manage/stores`, `/brand-manage/admins`, `/brand-manage/deals`, `/brand-overview`

## 代码规范
- **UI 全英文**，注释用中文
- Riverpod AsyncNotifier 模式（**不要用 setState**）
- Model 的 `fromJson` 所有字段必须 null-safe：
  - `json['x'] as String? ?? ''` 不是 `json['x'] as String`
  - `json['x'] != null ? DateTime.parse(json['x'] as String) : DateTime.now()`
  - `(json['x'] as num?)?.toDouble() ?? 0`
- 严格遵循现有目录结构

## 常见错误（必须避免）
1. **fromJson null 崩溃**: Edge Function select 可能不返回某些字段 → 必须 null-safe 解析
2. **Edge Function 没部署**: 本地改了 index.ts 必须部署才生效
   - `supabase functions deploy <name> --no-verify-jwt --project-ref kqyolvmgrdekybjrwizx`
   - 或在 Supabase Dashboard → Edge Functions 手动更新
3. **Edge Function PATCH 白名单**: 新增字段必须加到 `allowedFields` 数组
4. **混淆用户端和商家端模式**: 商家端用 `pages/services/`，不是 `presentation/screens/data/repositories/`

## 开发命令
```bash
# 运行商家端
cd "/Users/howardshansmac/github/coupon app/coupon-app/dealjoy_merchant" && ~/flutter/bin/flutter run -d emulator

# 需求
python3 scripts/read_merchant_excel.py "<模块名>"
```
