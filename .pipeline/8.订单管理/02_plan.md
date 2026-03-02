# 8.订单管理 开发计划

## 优先级 1: 修复/完善 Model 层

### Task 1.1: 更新 OrderModel
- **文件**: `deal_joy/lib/features/orders/data/models/order_model.dart`
- **改动**: 添加 `unitPrice`, `updatedAt`, `refundReason` 字段
- **原因**: DB schema 有这些字段但 model 缺失，订单详情页需要

### Task 1.2: 增强 DealSummary
- **文件**: `deal_joy/lib/features/orders/data/models/order_model.dart`
- **改动**: 添加 merchant `logoUrl`, `address` 字段
- **原因**: 订单卡片需要显示商家 Logo，详情页需要商家地址

## 优先级 2: 完善 Repository 层

### Task 2.1: 增强 OrdersRepository
- **文件**: `deal_joy/lib/features/orders/data/repositories/orders_repository.dart`
- **改动**:
  - `fetchUserOrders` 增加 status 筛选参数
  - `requestRefund` 改为调用 create-refund Edge Function（而非直接更新状态）
  - `fetchOrderById` select 补充 unit_price, updated_at, refund_reason
  - 查询补充 merchants(name, logo_url, address)
- **原因**: 支持 Tab 筛选 + 正确的退款流程 + 详情页数据

## 优先级 3: 完善 Provider 层

### Task 3.1: 增强 OrdersProvider
- **文件**: `deal_joy/lib/features/orders/domain/providers/orders_provider.dart`
- **改动**:
  - 添加 filteredOrdersProvider (按 status 筛选)
  - 添加 refundOrderProvider (调用退款)
  - 添加 selectedTabProvider
- **原因**: UI 层的 Tab 筛选和退款操作需要

## 优先级 4: UI 层 - 改造 OrdersScreen

### Task 4.1: 重构 OrdersScreen 加入 TabBar
- **文件**: `deal_joy/lib/features/orders/presentation/screens/orders_screen.dart`
- **改动**:
  - 添加 TabBar: All / Active / Completed / Refunded
  - 每个 Tab 下显示对应 status 的订单
  - 支持下拉刷新
- **原因**: 需求 8.1.1 Tab 分类

### Task 4.2: 增强 _OrderCard
- **文件**: `deal_joy/lib/features/orders/presentation/screens/orders_screen.dart`
- **改动**:
  - 显示商家 Logo
  - 显示下单时间
  - 根据状态显示操作按钮
  - 点击进入订单详情页
- **原因**: 需求 8.1.1 卡片和操作

## 优先级 5: UI 层 - 新建 OrderDetailScreen

### Task 5.1: 创建 OrderDetailScreen
- **文件**: `deal_joy/lib/features/orders/presentation/screens/order_detail_screen.dart` (新建)
- **内容**:
  - 订单号、下单时间、支付方式、支付时间
  - Deal 标题 + 价格 + 数量 + 商家名 + 地址
  - 金额明细: 单价 × 数量 = 小计 → 实付金额
  - 券信息: Active → QR Code 按钮, Completed → 核销时间
  - 退款按钮 (Active 状态)
- **原因**: 需求 8.1.2

### Task 5.2: 添加路由
- **文件**: `deal_joy/lib/core/router/app_router.dart`
- **改动**: 添加 `/orders/:orderId` 路由
- **原因**: 支持从订单列表进入详情页

## 优先级 6: 后端检查
- schema.sql 已有完整的 orders 和 coupons 表结构
- create-refund Edge Function 已实现
- RLS 策略已配置
- 无需新增 migration 或 Edge Function
