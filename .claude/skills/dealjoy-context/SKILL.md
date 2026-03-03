---
name: dealjoy-context
description: "DealJoy 项目上下文。所有代码修改必须遵循此规范。自动触发。"
invocation: auto
---

# DealJoy 项目规范

## 核心原则
- **直接修改 `deal_joy/` 目录下的代码**，不要生成到 output/ 或其他地方
- **先读后改**：修改任何文件前必须先读取理解现有代码
- **遵循现有模式**：看看相邻文件怎么写的，保持一致

## 目录约定（不可违反）
```
deal_joy/lib/features/{module}/
├── data/repositories/   # XxxRepository 类
├── data/models/         # XxxModel 类
├── domain/providers/    # Riverpod providers
└── presentation/
    ├── screens/         # XxxScreen 页面
    └── widgets/         # XxxCard, XxxTile 组件
```

后端代码：
```
deal_joy/supabase/
├── migrations/YYYYMMDDHHMMSS_描述.sql
└── functions/{function-name}/index.ts
```

## 语言规则（最高优先级）
- **英文**：UI 文案、变量名、函数名、类名、字符串、错误提示、路由
- **中文**：仅限代码注释

## 状态管理
- 使用 Riverpod 2.x（flutter_riverpod）
- 异步操作用 AsyncNotifier 或 FutureProvider
- 禁止在有 Riverpod 的页面用 setState

## 已有的共享组件（请复用）
- `AppButton` - deal_joy/lib/shared/widgets/app_button.dart
- `AppTextField` - deal_joy/lib/shared/widgets/app_text_field.dart
- `MainScaffold` - deal_joy/lib/core/widgets/main_scaffold.dart（底部导航）
- `AppColors` - deal_joy/lib/core/theme/app_colors.dart
- `AppTheme` - deal_joy/lib/core/theme/app_theme.dart
- `supabaseProvider` - deal_joy/lib/shared/providers/supabase_provider.dart

## 数据库
- Supabase PostgreSQL，schema 在 `deal_joy/supabase/schema.sql`
- 每张表必须有 RLS 策略
- 新增表用 migration 文件，不要直接改 schema.sql
