# DealJoy - 本地生活团购平台

## 项目概述
北美 Dallas 地区本地生活团购平台，核心差异化：**"随时买，随时退"** — 无条件即时退款。
项目当前完成度约 **70%**，核心购买流程可用，需补全缺失功能并修复问题。

## 技术栈
- **前端**: Flutter 3.x + Dart 3.x, Riverpod 2.x, go_router, Material Design 3
- **后端**: Supabase (PostgreSQL 15+, Edge Functions/Deno, Auth, Storage, Realtime)
- **支付**: Stripe
- **推送**: Firebase Cloud Messaging

## 项目结构
所有代码在 `deal_joy/` 目录下：
```
deal_joy/
├── lib/
│   ├── main.dart                    # 入口：初始化 Supabase + Stripe
│   ├── app.dart                     # DealJoyApp 根 Widget
│   ├── core/
│   │   ├── config/env.dart          # 环境变量加载
│   │   ├── constants/app_constants.dart
│   │   ├── theme/app_theme.dart, app_colors.dart
│   │   ├── errors/app_exception.dart
│   │   ├── widgets/main_scaffold.dart  # 底部导航
│   │   └── router/app_router.dart      # go_router 路由配置
│   ├── features/                    # Feature-First 架构
│   │   ├── auth/                    # ✅ 已实现
│   │   ├── deals/                   # ⚠️ 90% - HomeScreen UI 未完成
│   │   ├── checkout/                # ⚠️ 95% - UI 部分缺失
│   │   ├── orders/                  # ✅ 已实现
│   │   ├── reviews/                 # ✅ 已实现
│   │   ├── merchant/                # ❌ 20% - dashboard 骨架
│   │   ├── chat/                    # ❌ 0% - 纯占位
│   │   ├── cart/                    # ❌ 5% - 纯占位
│   │   └── profile/                 # ⚠️ 60% - 缺编辑功能
│   └── shared/
│       ├── providers/supabase_provider.dart
│       └── widgets/app_button.dart, app_text_field.dart
├── supabase/
│   ├── schema.sql                   # 完整数据库架构
│   ├── seed.sql                     # 种子数据
│   ├── migrations/                  # ✅ 2 个 migration
│   └── functions/                   # ✅ create-payment-intent, create-refund
├── test/                            # ❌ 仅占位测试
└── .env                             # Supabase + Stripe 密钥
```

## 每个目录的约定（必须严格遵循）
```
features/{module}/
├── data/
│   ├── repositories/   # Repository 类（API 调用、数据库查询）
│   └── models/         # 数据模型（freezed/json_serializable）
├── domain/
│   └── providers/      # Riverpod Providers
└── presentation/
    ├── screens/        # 页面级 Widget（XxxScreen）
    └── widgets/        # 模块内组件（XxxCard, XxxTile）
```

## 当前已知问题
1. test/widget_test.dart 引用不存在的 MyApp（应为 DealJoyApp）
2. HomeScreen UI 未完成（位置选择菜单和 deal grid 截断）
3. CheckoutScreen UI 部分缺失
4. Chat 功能只有静态 UI，无后端
5. Cart 功能只有空状态，无逻辑
6. Profile 无编辑功能
7. Merchant Dashboard 只有骨架
8. Stripe key 格式为 sb_publishable_*（应为 pk_test_*）
9. geolocator 已声明但未使用真实 GPS
10. Saved Deals 有 repository 但无 UI 页面

## 需求来源
- Excel: `requirements/DealJoy_V1_详细需求清单_v3.xlsx`
- 读取: `python3 scripts/read_excel.py "<模块名>"`

## 代码规范
- **UI 全英文**（面向北美市场），注释用中文
- Riverpod AsyncNotifier 模式（不要用 setState）
- 每张 Supabase 表必须有 RLS 策略
- 表单必须用 GlobalKey<FormState> + validator
- 每个文件只放一个公开 Widget
- 严格遵循现有目录结构，不要创建新的目录层级

## 开发命令
```bash
# 从 Excel 读取模块需求
python3 scripts/read_excel.py "1.用户认证系统"

# 运行 Flutter 测试
cd deal_joy && flutter test

# 运行 app
cd deal_joy && flutter run
```
