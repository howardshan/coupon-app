# 项目路径规则（最高优先级）
- **本项目（商家端）代码路径**：`/Users/howardshansmac/github/coupon app/coupon-app/dealjoy_merchant/`
- **用户端代码路径**（只读参考）：`/Users/howardshansmac/github/coupon app/coupon-app/deal_joy/`
- 所有商家端代码修改必须在本项目路径下，不可修改用户端路径

# 沟通规则（最高优先级）
- **所有与用户的对话和解释必须用中文回复**
- **代码注释用中文**
- **代码本身（变量名、函数名、类名等）和 UI 文案用英文**
- **每次完成代码改动后，必须自动重启 Android 模拟器**：
  ```bash
  pkill -f "qemu-system" 2>/dev/null; pkill -f "emulator" 2>/dev/null
  nohup ~/Library/Android/sdk/emulator/emulator -avd Medium_Phone_API_36.1 -no-snapshot-load -no-audio > /tmp/emulator.log 2>&1 &
  sleep 20
  cd "/Users/howardshansmac/github/coupon app/coupon-app/dealjoy_merchant" && nohup ~/flutter/bin/flutter run -d emulator-5554 > /tmp/flutter_run.log 2>&1 &
  ```

# DealJoy Merchant — 商家端 App

## 项目概述
北美 Dallas 地区本地生活团购平台的**商家端独立 App**。
与用户端（coupon-app）共享同一套 Supabase 后端，专注商家视角的功能：
- 店铺管理、Deal 创建、订单核销、收款、数据分析、达人营销

## 技术栈
- **前端**: Flutter 3.x + Dart 3.x, Riverpod 2.x, go_router, Material Design 3
- **后端**: Supabase (与用户端共享同一数据库)
- **扫码**: mobile_scanner
- **图片**: image_picker + cached_network_image

## 项目结构
```
dealjoy_merchant/
├── lib/
│   ├── main.dart              # 入口
│   ├── app_shell.dart         # 商家端主容器（4-tab 底部导航）
│   └── features/
│       ├── merchant_auth/     # 商家注册/登录/认证
│       ├── dashboard/         # 首页仪表盘
│       ├── store/             # 店铺管理
│       ├── deals/             # Deal 创建与管理
│       ├── scan/              # 核销扫码
│       ├── orders/            # 订单管理
│       ├── earnings/          # 收益/结算
│       ├── reviews/           # 评价管理
│       ├── analytics/         # 数据分析
│       ├── notifications/     # 通知
│       ├── marketing/         # 营销工具
│       ├── influencer/        # 达人合作
│       └── settings/          # 账户设置
├── requirements/              # 需求清单 Excel
├── scripts/                   # 工具脚本
├── docs/                      # 项目文档
├── output/                    # Pipeline 输出
└── .claude/                   # Claude 配置
```

## 每个模块的目录约定（必须严格遵循）
```
features/{module}/
├── pages/       # 页面级 Widget（XxxPage）
├── widgets/     # 模块内组件（XxxCard, XxxTile）
├── providers/   # Riverpod Providers
├── services/    # 业务逻辑服务
└── models/      # 数据模型
```

## 代码规范
- **UI 全英文**（面向北美市场），注释用中文
- Riverpod `AsyncNotifier` 模式（不要用 `setState`）
- 每张 Supabase 表必须有 RLS 策略
- 表单必须用 `GlobalKey<FormState>` + validator
- 每个文件只放一个公开 Widget
- 严格遵循现有目录结构，不要创建新的目录层级

## 需求来源
- Excel: `requirements/DealJoy_商家端需求清单.xlsx`
- 读取: `python3 scripts/read_merchant_excel.py "<模块名>"`

## 开发命令
```bash
# 从 Excel 读取模块需求
python3 scripts/read_merchant_excel.py "1.商家注册与认证"

# 运行 Flutter 测试
flutter test

# 运行 app
flutter run
```
