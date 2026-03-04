# DealJoy 全栈代码生成项目

## 项目概述
DealJoy 是一个本地生活团购平台（类似美团/Groupon），目标市场为北美 Dallas 地区。
核心差异化：**"随时买，随时退"** — 无条件即时退款。

## 技术栈
- **前端**: Flutter 3.x + Dart 3.x, Riverpod 2.x, go_router, Material Design 3
- **后端**: Supabase (PostgreSQL 15+, Edge Functions/Deno, Auth, Storage, Realtime)
- **支付**: Stripe
- **推送**: Firebase Cloud Messaging

## 需求清单
需求来源文件: `requirements/DealJoy_V1_详细需求清单_v3.xlsx`
- 用户端 App: 18个功能系统, 682行需求
- 商家端: 13个功能系统
- 运营端: 13个功能系统
- 非功能需求: 性能/安全/合规/兼容性

## Agent 流水线架构
本项目通过6个专业子代理（sub-agents）自动生成代码：

```
需求Excel → [需求解析器] → [架构师] → [后端开发] → [前端开发] → [代码审查] → [测试工程师]
```

每个 Agent 是独立的 Claude Code 子代理，Pixel Agents 可实时可视化。

## 参考文档（Skills）
所有 Agent 在编写代码前**必须先阅读**相关参考文档：

| 文档 | 内容 | 哪些 Agent 必须读 |
|------|------|------------------|
| `docs/ui/meituan-reference.md` | **用户端**首页/详情/下单/券码/订单/搜索/个人中心全部页面的布局规范和交互细节 | 架构师, 前端开发, 代码审查 |
| `docs/ui/merchant-reference.md` | **商家端**注册/工作台/核销/Deal管理/订单/财务全部页面的布局规范 | 架构师, 前端开发, 代码审查 |
| `docs/features/influencer-module.md` | Influencer合作模块完整设计(商家端+Influencer端) | 架构师, 前端开发 |
| `docs/flutter/patterns.md` | Riverpod/Widget/Router 代码模板 | 前端开发, 测试工程师 |
| `docs/supabase/patterns.md` | SQL Migration/Edge Function/RLS 模板 | 架构师, 后端开发, 测试工程师 |
| `docs/business/rules.md` | 业务规则/错误码/限额/合规 | 所有 Agent |
| `docs/testing/patterns.md` | Widget测试/Provider测试/Deno测试模板 | 测试工程师 |

**规则**: 生成的代码必须与参考文档中的模式保持一致。如果需要偏离，必须在注释中说明原因。

## 代码规范
- **语言规则**: 前端代码除注释外全部英文（UI文案、变量名、字符串、错误提示等），注释用中文
- **后端注释**: 中文
- **代码风格**: 遵循 Dart/TypeScript 官方风格指南
- **文件结构**: Feature-First (`lib/features/{module}/pages|widgets|providers|services/`)
- **状态管理**: Riverpod AsyncNotifier 模式
- **数据库**: 每张表必须有 RLS 策略，默认拒绝所有

## 输出目录结构
```
output/{模块名}/
├── 01_requirements.json      # 需求解析器输出
├── 02_architecture.json      # 架构师输出
├── 03_backend/               # 后端开发输出
│   ├── migrations/*.sql
│   ├── functions/**/*.ts
│   └── policies/*.sql
├── 04_frontend/              # 前端开发输出
│   └── lib/features/{module}/**/*.dart
├── 05_review.json            # 代码审查输出
└── 06_tests/                 # 测试工程师输出
```

## 商家端模块
需求来源: `requirements/DealJoy_商家端需求清单.xlsx`
UI参考: `docs/ui/merchant-reference.md`
Pipeline: `/merchant-pipeline <模块名>`
Excel读取: `python3 scripts/read_merchant_excel.py <模块名>`
输出目录: `output/merchant/{模块名}/`

商家端共13个模块(P0=6, P1=4, P2=3):
1.商家注册与认证(P0) 2.商家工作台(P0) 3.门店信息管理(P0)
4.Deal管理(P0) 5.团购券核销(P0) 6.订单管理(P0)
7.财务与结算(P1) 8.评价管理(P1) 9.数据分析(P1) 10.消息通知(P1)
11.营销工具(P2) 12.Influencer合作(P2) 13.商家设置(P2)

**商家端注意事项**:
- 商家和用户是不同角色(Supabase Auth role)，注册流程独立
- RLS策略基于merchant_id，商家只能看自己门店数据
- 不同类别需不同证件(见Excel Sheet3证件矩阵)
- 退款是自动的，商家端只需查看，无需审批

## 当前试点模块
**用户端** 1-8模块已完成
**商家端** 从1.商家注册与认证开始
