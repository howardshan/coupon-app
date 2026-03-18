# 预授权 + 三级退款审批系统 — 修改总结文档

> **完成日期：** 2026-03-16
> **分支：** tianzuo-coupon1
> **影响范围：** DB 迁移 × 3、Edge Functions × 9、用户端 Flutter × 5、商家端 Flutter × 8

---

## 一、功能概述

### 核心差异化：随时退款

DealJoy 的核心承诺是「随时买，随时退」。本次改造在此基础上扩展为两种退款场景：

| 场景 | 触发条件 | 退款方式 |
|------|----------|----------|
| **未使用退款** | 购买后未核销，随时申请 | Stripe 即时退款（原有逻辑） |
| **核销后退款** | 核销后 24h 内，填写原因申请 | 三级审批流 → 最终退款 |

### 预授权（Pre-Authorization）

对距离到期 ≤ 7 天的 Deal，支付时使用 Stripe `capture_method: 'manual'`，仅冻结资金不扣款；核销时才正式 capture。未核销则 cancel，实现真正无损退款。

### 三级退款审批流

```
用户提交申请 → 商家审批 → 拒绝时升级 → 管理员仲裁 → 最终结果
                ↓同意                      ↓同意/拒绝
            execute-refund             execute-refund / rejected_admin
```

---

## 二、数据库变更

### 2.1 `orders` 表新增字段

```sql
-- 文件: deal_joy/supabase/migrations/20260310000001_orders_preauth_support.sql
ALTER TABLE orders ADD COLUMN is_captured BOOLEAN NOT NULL DEFAULT true;
```

- `true`（默认）= 已扣款（普通订单 / 已 capture 的预授权订单）
- `false` = 预授权中，资金已冻结但未扣款

新增 `orders.status` 枚举值：

| 新状态值 | 含义 |
|----------|------|
| `authorized` | 预授权冻结中（未核销） |
| `refund_pending_merchant` | 等待商家审批退款 |
| `refund_pending_admin` | 商家拒绝，等待管理员仲裁 |
| `refund_rejected` | 管理员最终拒绝退款 |

### 2.2 `refund_requests` 表（新建）

```sql
-- 文件: deal_joy/supabase/migrations/20260310000002_refund_requests_table.sql
```

状态机：`pending_merchant → approved_merchant / rejected_merchant → pending_admin → approved_admin / rejected_admin → completed / cancelled`

关键字段：

| 字段 | 说明 |
|------|------|
| `order_id` | 关联订单 |
| `merchant_id` | 关联商家（方便 RLS 过滤） |
| `refund_amount` | 申请退款金额 |
| `reason` | 用户填写的原因 |
| `merchant_response` | 商家拒绝时填写的原因 |
| `admin_response` | 管理员决定时填写的备注 |
| `responded_at` | 商家处理时间 |
| `admin_decided_at` | 管理员决定时间 |

### 2.3 `merchant_adjustments` 表（新建）

```sql
-- 文件: deal_joy/supabase/migrations/20260310000003_merchant_adjustments.sql
```

用于记录退款扣除商家应付金额（负数）和后续欠款偿还（正数），实现无余额字段的动态账务追踪。

---

## 三、Edge Functions 变更

### 3.1 已修改的函数

#### `create-payment-intent`
- **变更：** 查询 `deals.expires_at`，如果距到期 ≤ 7 天，使用 `capture_method: 'manual'`（预授权）
- **返回值：** 新增 `captureMethod` 字段告知客户端

#### `create-refund`
- **变更：** 读取 `orders.is_captured`
  - `false` → 调用 `paymentIntents.cancel()`（无损取消预授权）
  - `true` → 调用 `refunds.create()`（正常退款）

#### `stripe-webhook`
- **变更：** 新增两个事件处理器
  - `payment_intent.amount_capturable_updated` → 订单状态更新为 `authorized`
  - `payment_intent.canceled` → 订单状态更新为 `refunded`，`is_captured` 写 `false`

#### `merchant-scan`
- **变更：** 核销成功后 fire-and-forget 调用 `capture-payment`
- 不等待结果，扫码响应速度不受影响

#### `merchant-orders`
- **变更：** 新增两条路由
  - `GET /merchant-orders/refund-requests` → 返回商家的退款申请列表
  - `PATCH /merchant-orders/refund-requests/:id` → 商家审批（approve/reject）

### 3.2 新建的函数

#### `capture-payment`
- **路径：** `deal_joy/supabase/functions/capture-payment/index.ts`
- **功能：** 对预授权订单执行 Stripe capture
- **幂等保障：** 检查 `is_captured`，已 capture 则跳过
- **调用方：** `merchant-scan`（fire-and-forget）

#### `submit-refund-request`
- **路径：** `deal_joy/supabase/functions/submit-refund-request/index.ts`
- **功能：** 用户在核销后 24h 内提交退款申请
- **校验：** 订单 `status == 'used'`，且 `coupons.used_at` 在 24h 内
- **副作用：** 创建 `refund_requests` 记录，订单状态 → `refund_pending_merchant`

#### `execute-refund`
- **路径：** `deal_joy/supabase/functions/execute-refund/index.ts`
- **功能：** 内部退款执行器（不对外暴露）
- **调用方：** `merchant-orders`（商家批准）、`admin-refund`（管理员批准）
- **逻辑：** 根据 `is_captured` 决定 cancel vs refund；幂等检查防重复执行

#### `admin-refund`
- **路径：** `deal_joy/supabase/functions/admin-refund/index.ts`
- **功能：** 管理员仲裁接口
- **权限：** 检查 `users.role` 为 `admin` 或 `super_admin`
- **路由：**
  - `GET /admin-refund` → 列出 `pending_admin` 状态申请
  - `PATCH /admin-refund/:id` → 批准（调用 execute-refund）或最终拒绝

---

## 四、Flutter 用户端变更

### `order_model.dart`
- 新增 `isCaptured` 字段（`bool`，默认 `true`）
- `fromJson` 中 `is_captured as bool? ?? true`（null-safe）

### `orders_repository.dart`
- 新增 `submitPostUseRefundRequest(orderId, reason)` 方法
- 调用 `submit-refund-request` Edge Function，传 `access_token` 到 body

### `coupons_provider.dart`（`RefundNotifier`）
- 新增 `submitPostUseRefundRequest(orderId, reason)` 方法
- 成功后同时 invalidate：`userCouponsProvider`、`userOrdersProvider`、`orderDetailProvider(orderId)`、`userOrderDetailProvider(orderId)`

### `post_use_refund_screen.dart`（新建）
- **路径：** `deal_joy/lib/features/orders/presentation/screens/post_use_refund_screen.dart`
- 4 种状态视图：
  - `form` — 填写原因并提交
  - `pending` — 申请已提交，等待商家审批
  - `refunded` — 退款成功
  - `rejected` / `not_eligible` — 拒绝或不符合条件

### `app_router.dart`
- 新增路由：`/post-use-refund/:orderId`

---

## 五、Flutter 商家端变更

### `orders_service.dart`
新增 4 个方法：

| 方法 | 说明 |
|------|------|
| `fetchRefundRequests({status?, page, perPage})` | GET 商家自己的退款申请列表 |
| `decideRefundRequest({refundRequestId, action, reason?})` | PATCH 审批退款申请 |
| `fetchAdminRefundRequests({status?, page, perPage})` | GET 管理员仲裁列表 |
| `adminDecideRefundRequest({refundRequestId, action, reason?})` | PATCH 管理员仲裁审批 |

### `refund_requests_page.dart`（新建）
- Pending / All 两 Tab
- 下拉刷新；点击进入 `RefundRequestDetailPage`

### `refund_request_detail_page.dart`（新建）
- 显示订单信息、用户退款原因、当前状态
- **Approve** 按钮 → 确认弹窗 → 调用 `decideRefundRequest(approve)`
- **Reject** 按钮 → 强制填写原因（≥10字）→ 调用 `decideRefundRequest(reject)` → 升级到管理员

### `admin_refund_requests_page.dart`（新建）
- 管理员专用，Pending / All 两 Tab
- 显示商家名称 + 商家拒绝原因

### `admin_refund_detail_page.dart`（新建）
- 显示：用户原因 + 商家拒绝原因 + 订单详情
- **Approve** → 调用 `adminDecideRefundRequest(approve)` → 实际退款
- **Reject** → 强制填写原因 → 最终拒绝，订单状态 → `refund_rejected`

### `orders_list_page.dart`
- AppBar 新增两个入口按钮：
  - `Icons.policy_outlined` → `RefundRequestsPage`（商家审批）
  - `Icons.admin_panel_settings_outlined` → `AdminRefundRequestsPage`（管理员仲裁）

---

## 六、手动测试流程

> **前提：** 两个 App 均已登录。用户账号已购买并核销一个 Deal。管理员账号在 `users` 表有 `role = 'admin'`。

---

### 测试 A：预授权流程

#### 测试 A-1：预授权扣款（短有效期 Deal）

**准备：** 在 Supabase Dashboard 将某个 Deal 的 `validity_type` 改为 `short_after_purchase`。

1. 用户端打开该 Deal，点击购买，完成 Stripe 支付
2. 检查 Supabase `orders` 表：
   - `status` = `authorized`（不是 `paid`）
   - `is_captured` = `false`

**期望结果：** 卡片被冻结金额，但不被真实扣款。

#### 测试 A-2：核销触发 capture

1. 商家端用扫码功能扫描该订单的 QR code
2. 等待 2-3 秒后检查：
   - `orders.is_captured` = `true`
   - `orders.status` = `used`
   - Stripe Dashboard 中该 PaymentIntent 状态变为 `succeeded`

**期望结果：** capture 在后台完成，扫码响应速度不受影响。

#### 测试 A-3：预授权取消（未核销退款）

1. 测试 A-1 的订单（`is_captured = false`），在用户端点「退款」
2. 检查：
   - `orders.status` = `refunded`
   - Stripe Dashboard：PaymentIntent 状态变为 `canceled`（不是 refunded）

**期望结果：** 退款金额立即释放，不产生 Stripe 手续费。

---

### 测试 B：核销后退款 — 完整三级审批流

#### 测试 B-1：用户提交退款申请

1. 用户端进入已核销的订单详情页（`status = used`）
2. 看到「Request Post-Use Refund」按钮（若已超过 24h 则看不到）
3. 点击按钮，进入 `/post-use-refund/:orderId` 页面
4. 填写原因（至少 10 个字符），点击「Submit Refund Request」

**期望结果：**
- 页面切换到 `pending` 状态视图（显示「Awaiting Merchant Review」）
- Supabase `refund_requests` 表新增一条记录，`status = pending_merchant`
- `orders.status` = `refund_pending_merchant`

#### 测试 B-2：商家审批（批准路径）

1. 商家端进入订单列表，点击 AppBar 中的 `Icons.policy_outlined`（退款申请）按钮
2. 在 `Pending` Tab 中看到该申请
3. 点击进入详情，阅读退款原因
4. 点击「Approve Refund」，确认弹窗中点「Approve」

**期望结果：**
- `refund_requests.status` = `approved_merchant`
- `orders.status` = `refunded`
- Stripe Dashboard：产生一笔 Refund 记录
- 用户端刷新订单详情：状态变为「Refunded」

#### 测试 B-3：商家审批（拒绝路径）→ 管理员仲裁

1. 重新触发一个退款申请（同 B-1）
2. 商家端点击「Reject & Escalate to Admin」
3. 填写拒绝原因（至少 10 字符），点「Reject」

**期望结果（商家端）：**
- `refund_requests.status` = `pending_admin`
- `orders.status` = `refund_pending_admin`
- 该申请从商家端 `Pending` Tab 消失（状态不再是 `pending_merchant`）

4. 商家端点击 AppBar 中的 `Icons.admin_panel_settings_outlined`（仲裁）按钮
5. 看到该申请在 `Pending` Tab，并显示商家的拒绝原因

**使用管理员账号登录后：**

6. 管理员端同样进入管理员仲裁列表
7. 点击该申请，查看：用户原因、商家拒绝原因
8. 点击「Approve（Admin）」→ 退款执行

**期望结果（批准）：**
- `refund_requests.status` = `approved_admin`
- `orders.status` = `refunded`
- Stripe 产生退款记录

**或者拒绝（最终拒绝）：**

8. 点击「Reject（Final）」，填写原因

**期望结果（拒绝）：**
- `refund_requests.status` = `rejected_admin`
- `orders.status` = `refund_rejected`
- `coupons.status` = `used`（恢复为已使用，不可再申请退款）
- 用户端详情页显示「Refund Rejected」状态

---

### 测试 C：边界条件

#### 测试 C-1：超过 24h 窗口

1. 将 `coupons.used_at` 手动改为 25 小时前
2. 用户端进入该订单的订单详情页

**期望结果：** 不显示「Request Post-Use Refund」按钮；若直接访问 `/post-use-refund/:orderId`，页面显示「Not Eligible」视图。

#### 测试 C-2：重复提交

1. 对同一订单再次调用 `submit-refund-request`（可通过 API 工具测试）

**期望结果：** 返回错误，`code = already_requested`，HTTP 400。

#### 测试 C-3：非管理员访问 admin-refund

1. 用普通商家账号（`role != 'admin'`）访问 `admin-refund` Edge Function

**期望结果：** HTTP 403，`{ error: 'forbidden', message: 'Admin access required' }`。

#### 测试 C-4：execute-refund 幂等性

1. 对同一个 `refundRequestId` 连续调用两次 `execute-refund`

**期望结果：** 第一次成功；第二次检查到 `status = completed` 后直接返回成功，不会触发二次 Stripe refund。

---

## 七、已知限制与后续优化建议

| 项目 | 说明 |
|------|------|
| **预授权触发条件** | 当前以 `deals.validity_type = 'short_after_purchase'` 为判断依据，其他类型一律走即时扣款。Stripe 预授权最长有效 7 天，超期自动失效需注意 |
| **部分退款** | 当前实现为全额退款。多张券的部分退款（如购买 2 张只退 1 张）需额外开发 |
| **推送通知** | 退款申请状态变更目前无推送，建议后续接入 Supabase Realtime 或 FCM |
| **用户端退款追踪** | `post_use_refund_screen.dart` 需要手动刷新；建议后续增加 Realtime 订阅 |
| **商家余额** | 退款从 `merchant_adjustments` 追踪欠款，需要对账结算功能配合使用 |
