# 7.退款系统 Implementation Plan

## Priority: Bug Fix > 补全现有功能 > 新增功能

---

### P0: Backend Fixes (必须先修)

#### T1: DB Migration — 添加 RLS UPDATE 策略 + refund tracking 字段
- **文件**: `deal_joy/supabase/migrations/20260301100000_refund_system.sql`
- **修改**:
  - 添加 `orders` 表的 UPDATE RLS 策略（允许用户更新自己订单的 status 为 refund_requested）
  - 添加 `orders.refund_requested_at` 和 `orders.refunded_at` 时间戳字段
  - 添加 `payments` 表的 UPDATE RLS 策略（供 Edge Function service role 使用）
- **原因**: 当前无 UPDATE 策略导致 requestRefund() 会被 RLS 阻止

#### T2: Edge Function — 修复 create-refund 的安全漏洞
- **文件**: `deal_joy/supabase/functions/create-refund/index.ts`
- **修改**:
  - 添加 double-refund guard（status === 'refunded' || status === 'refund_requested' 时拒绝）
  - 添加 expired 状态检查（已过期不可手动退）
  - 使用 service role key 做 DB 更新（绕过 RLS 限制）
  - 更新 payments 表的 refund_amount 和 status
  - 记录 refunded_at 时间戳
- **原因**: 当前存在重复退款风险，且 payments 表未同步更新

#### T3: Edge Function — auto-refund-expired (过期自动退款)
- **文件**: `deal_joy/supabase/functions/auto-refund-expired/index.ts`
- **修改**: 新建，由 cron job 定期调用
  - 查找所有 expired 且未退款的订单
  - 批量调用 Stripe refund
  - 更新 orders + coupons + payments 状态
- **原因**: 需求 7.1.2 要求过期后 24h 自动退全额

---

### P1: Frontend — 修复 + 补全

#### T4: OrderModel — 添加缺失字段和 getters
- **文件**: `deal_joy/lib/features/orders/data/models/order_model.dart`
- **修改**:
  - 添加 `isRefundRequested` getter
  - 添加 `isExpired` getter
  - 添加 `refundReason` 字段
  - 添加 `refundedAt`, `refundRequestedAt` 字段
  - 添加 `canRefund` 计算属性（仅 unused 状态可退）
  - 更新 status 注释
- **原因**: Model 缺失退款追踪所需字段

#### T5: OrdersRepository — 修复 requestRefund 调用路径
- **文件**: `deal_joy/lib/features/orders/data/repositories/orders_repository.dart`
- **修改**:
  - `requestRefund` 改为调用 create-refund Edge Function
  - 添加 reason 参数
  - 返回退款结果（refundId, status）
- **原因**: 当前直接更新 DB 不会触发 Stripe 退款

#### T6: Refund Provider — 新建退款状态管理
- **文件**: `deal_joy/lib/features/orders/domain/providers/refund_provider.dart`
- **修改**: 新建
  - RefundNotifier (AsyncNotifier) 管理退款请求状态
  - 调用 repository.requestRefund
  - 成功后刷新 userOrdersProvider
- **原因**: 需要管理退款请求的 loading/error/success 状态

#### T7: RefundRequestScreen — 退款确认页面
- **文件**: `deal_joy/lib/features/orders/presentation/screens/refund_request_screen.dart`
- **修改**: 新建
  - 显示退款金额、退回方式、预计到账时间
  - "Confirm Refund" / "Cancel" 按钮
  - 退款原因选择（可选）
  - 退款规则说明
- **原因**: 需求 7.1.1 要求确认弹窗

#### T8: OrdersScreen — 添加退款入口按钮
- **文件**: `deal_joy/lib/features/orders/presentation/screens/orders_screen.dart`
- **修改**:
  - 为 unused 状态的订单卡片添加 "Refund" 按钮
  - 点击跳转到 /refund/:orderId
  - refund_requested 状态显示 "Processing..."
  - refunded 状态显示退款完成信息
- **原因**: 需求 7.1.1 要求订单详情有 Refund 入口

#### T9: CouponScreen — 添加 "Request Refund" 按钮
- **文件**: `deal_joy/lib/features/orders/presentation/screens/coupon_screen.dart`
- **修改**:
  - 在券详情底部添加 "Request Refund" 按钮（仅 unused 状态显示）
  - 点击跳转到 /refund/:orderId
- **原因**: 需求 7.1.1 要求券详情有 Request Refund 入口

#### T10: App Router — 添加退款路由
- **文件**: `deal_joy/lib/core/router/app_router.dart`
- **修改**:
  - 添加 `/refund/:orderId` 路由指向 RefundRequestScreen
- **原因**: 当前无退款页面路由

#### T11: App Constants — 添加退款状态常量
- **文件**: `deal_joy/lib/core/constants/app_constants.dart`
- **修改**:
  - 添加 `orderStatusRefundRequested = 'refund_requested'` 常量
- **原因**: 缺少 refund_requested 常量

---

### P2: 测试

#### T12: 编写退款模块测试
- **文件**: `deal_joy/test/features/orders/refund_test.dart`
- 测试 OrderModel 的 canRefund, isRefundRequested 等
- 测试 RefundNotifier 状态转换
- 修复 widget_test.dart (MyApp → DealJoyApp)

---

## 执行顺序
T1 → T2 → T3 → T4 → T5 → T6 → T11 → T10 → T7 → T8 → T9 → T12
