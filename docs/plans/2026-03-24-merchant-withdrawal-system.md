# 商家提现完整流程开发计划

> **日期：** 2026-03-24
> **状态：** ✅ 已完成
> **分支：** tianzuo-coupon1

---

## 背景

商家核销订单后，收益（订单金额 × 85%）进入结算池，T+7 天后变为可提现余额。商家需要在商家端 App 中通过提现功能将余额打款到银行账户。

**开发前状态：**
- 前端 UI（earnings/withdrawal/payment_account 等页面）已全部完成
- 数据库表（withdrawals、merchant_bank_accounts、merchant_withdrawal_settings）已存在
- 邮件模板 M14（申请通知）、M15（完成通知）已存在
- `merchant-withdrawal` Edge Function 路由框架存在，但 `handleWithdraw` 中有 TODO（实际 Stripe 转账未实现）
- `payment_account_page.dart` 的 Connect 按钮只弹 "coming soon"

**目标：** 实现完整的端到端提现流程：Stripe Connect 账户绑定 → 商家申请提现 → 系统自动调用 Stripe Transfer → 同步更新状态 → 邮件通知结果

**核心决策：**
- 触发方式：商家申请后**自动**调用 Stripe Transfer，无需管理员审批
- 账户绑定：**Stripe Connect Express**（Stripe 托管 onboarding 页面）

---

## ⚠️ 重要架构说明：Transfer 是同步操作

> **原计划** 设想通过监听 Stripe Webhook 的 `transfer.paid` / `transfer.failed` 事件来更新提现状态。
> **实际情况：** 这两个事件在 Stripe 中并不存在。

`stripe.transfers.create()` 是**同步**操作：
- 调用成功 → 转账立即完成，直接将状态更新为 `completed`
- 调用抛出异常 → 转账失败，在 catch 块中更新为 `failed`

因此，状态同步、FIFO 标记 `order_items.merchant_status`、M15/M18 邮件发送，**全部在 `handleWithdraw` 函数内同步或 fire-and-forget 处理**，不依赖任何 Webhook。Stripe Dashboard 无需额外配置 Webhook 事件。

---

## 阶段划分

```
阶段一：Stripe Connect 账户绑定（必须第一步，无 verified 账户无法提现）  ✅
    ↓
阶段二：Stripe Transfer 实际执行（替换 handleWithdraw 中的 TODO）        ✅
    ↓
阶段三：Transfer 结果同步 + 邮件通知（同步处理，非 Webhook）             ✅
    ↓
阶段四：M18 提现失败邮件模板                                             ✅
    ↓
阶段五（可选）：自动提现 Cron                                            ⬜ 待开发
```

---

## 阶段一：Stripe Connect Express 账户绑定 ✅

### 目标
商家通过 App 完成 Stripe Express 账户注册，绑定银行账户后才能提现。

### 后端修改
**文件：** `deal_joy/supabase/functions/merchant-withdrawal/index.ts`

新增 3 条路由：

1. **`POST /merchant-withdrawal/connect`** — 创建 Connect 账户 + 生成 onboarding URL
   - 若商家已有 `stripe_account_id`，直接生成新的 Account Link（续接 onboarding）
   - 若没有，调用 `stripe.accounts.create({ type: 'express', ... })` 先创建，存入 `merchants.stripe_account_id`
   - 调用 `stripe.accountLinks.create()` 生成链接（`return_url` / `refresh_url` 均指向深链 `dealjoymerchant://stripe-callback`）
   - 返回 `{ url: "https://connect.stripe.com/..." }`

2. **`POST /merchant-withdrawal/connect/refresh`** — onboarding 完成后同步账户状态
   - 调用 `stripe.accounts.retrieve(stripe_account_id)` 检查 `charges_enabled` / `payouts_enabled`
   - 更新 `merchants.stripe_account_status`（`'connected'` 或 `'restricted'`）
   - 更新 `merchant_bank_accounts.status`（`'verified'` 或 `'pending'`）
   - 若账户有 `external_accounts`，提取 `last4` 和 `bank_name` 写入 `merchant_bank_accounts`
   - 返回最新账户状态

3. **`GET /merchant-withdrawal/connect/dashboard`** — 生成 Stripe Express Dashboard 链接
   - 调用 `stripe.accounts.createLoginLink(stripe_account_id)`
   - 返回 `{ url: "..." }`（已连接商家点 "Manage on Stripe" 时使用）

### 前端修改
**文件：** `dealjoy_merchant/lib/features/earnings/services/earnings_service.dart`

新增方法：
- `fetchStripeConnectUrl()` — 调用 `POST /connect`，返回 onboarding URL
- `refreshStripeAccountStatus()` — 调用 `POST /connect/refresh`，返回 StripeAccountInfo
- `fetchStripeManageUrl()` — 调用 `GET /connect/dashboard`，返回 Stripe Dashboard URL

**文件：** `dealjoy_merchant/lib/features/earnings/pages/payment_account_page.dart`

修改：
- `_ActionButtons` 的 `onConnectTap` 从 `_showComingSoonTip` 改为调用 `fetchStripeConnectUrl()` + `launchUrl()`
- `_ActionButtons` 的 `onManageTap` 改为调用 `fetchStripeManageUrl()` + `launchUrl()`
- 新增 `_RefreshStatusButton`（商家完成 onboarding 后点击同步），调用 `refreshStripeAccountStatus()` 后 `ref.invalidate(stripeAccountProvider)`
- 页面从 `ConsumerWidget` 改为 `ConsumerStatefulWidget`，增加 `_isConnecting`、`_isRefreshing`、`_isOpeningDashboard` 加载状态

---

## 阶段二：Stripe Transfer 实际执行 ✅

### 目标
替换 `handleWithdraw` 中的 TODO，商家申请后立即调用 Stripe Transfer。

### 后端修改
**文件：** `deal_joy/supabase/functions/merchant-withdrawal/index.ts`

```typescript
const transfer = await stripe.transfers.create(
  {
    amount:      Math.round(amount * 100), // 转为分（cents）
    currency:    'usd',
    destination: bankAccount.stripe_account_id,
    metadata:    { withdrawal_id: withdrawal.id, merchant_id: merchantId },
  },
  { idempotencyKey: withdrawal.id }  // 防止网络重试导致重复打款
);
```

---

## 阶段三：Transfer 结果同步 + 邮件通知 ✅

### 重要说明
由于 `stripe.transfers.create()` 是同步操作，所有结果处理均在同一函数内完成，**不需要 Webhook，不需要配置 Stripe Dashboard**。

### 成功路径（try 块）

```
stripe.transfers.create() 成功
  → withdrawals.status = 'completed', completed_at = now()
  → FIFO 批量更新 order_items.merchant_status → 'paid'（fire-and-forget）
  → 发送 M15 提现完成邮件（fire-and-forget）
```

### 失败路径（catch 块）

```
stripe.transfers.create() 抛出异常
  → withdrawals.status = 'failed', failure_reason = error.message
  → 发送 M18 提现失败邮件（fire-and-forget）
  → 返回 502 错误给客户端
```

### FIFO 标记逻辑

当提现成功后，需将本次提现对应的已结算券批量标记为 `paid`：

1. 查询该商家所有 `merchant_status = 'unpaid'` 且 `redeemed_at < T-7` 的 `order_items`，按 `redeemed_at` 升序排列
2. 从最早的券开始累加商家净收入（`unit_price - service_fee`），直到累计金额 ≥ 提现金额（容差 $0.01）
3. 批量 `.update({ merchant_status: 'paid' })` 标记这批券
4. 非致命：此步骤失败不影响提现本身，仅记录 warn 日志

---

## 阶段四：M18 提现失败邮件 ✅

### 新增文件

**`deal_joy/supabase/functions/_shared/email-templates/merchant/withdrawal-failed.ts`**
- 接口：`M18WithdrawalFailedData`（merchantName, withdrawalId, amount, failedAt, failureReason?）
- 函数：`buildM18Email()`
- 邮件主题：`"Action required: Your withdrawal of $X could not be processed"`

**`deal_joy/supabase/migrations/20260324000002_email_type_m18.sql`**
```sql
INSERT INTO email_type_settings (email_code, email_name, recipient_type, user_configurable)
VALUES ('M18', 'Withdrawal Failed', 'merchant', FALSE)
ON CONFLICT (email_code) DO NOTHING;
```
> 注：因本地 migration 版本号冲突，此 migration 已通过 Supabase Dashboard → SQL Editor 手动执行。

---

## 阶段五（可选）：自动提现 Cron ⬜

### 目标
对启用了自动提现的商家，按设定周期自动触发提现。

### 文件修改

**新建：** `deal_joy/supabase/functions/auto-withdrawal/index.ts`
- 查询 `merchant_withdrawal_settings` 中 `auto_withdrawal_enabled = true` 的商家
- 判断今天是否为触发日期（按 frequency 和 auto_withdrawal_day）
- 幂等检查：当天已有 pending/processing/completed 记录则跳过
- 对满足条件的商家调用提现逻辑（余额 >= min_withdrawal_amount）

**新建 migration：** `deal_joy/supabase/migrations/YYYYMMDD_auto_withdrawal_cron.sql`
```sql
SELECT cron.schedule(
  'auto-withdrawal-daily',
  '0 10 * * *',  -- 每天 UTC 10:00（Dallas CST 05:00）
  $$ SELECT net.http_post(url := 'https://kqyolvmgrdekybjrwizx.supabase.co/functions/v1/auto-withdrawal', ...) $$
);
```

---

## 关键文件清单

| 文件 | 变更类型 | 阶段 | 状态 |
|------|---------|------|------|
| `deal_joy/supabase/functions/merchant-withdrawal/index.ts` | 修改（新增 3 条 Connect 路由 + Transfer 调用 + 同步结果处理） | 一、二、三 | ✅ |
| `deal_joy/supabase/functions/_shared/email-templates/merchant/withdrawal-failed.ts` | 新建 M18 邮件模板 | 四 | ✅ |
| `deal_joy/supabase/migrations/20260324000002_email_type_m18.sql` | 新建 migration（手动执行） | 四 | ✅ |
| `dealjoy_merchant/lib/features/earnings/services/earnings_service.dart` | 修改（新增 3 个 Connect 方法） | 一 | ✅ |
| `dealjoy_merchant/lib/features/earnings/pages/payment_account_page.dart` | 修改（Connect/Manage/Refresh 按钮接真实逻辑） | 一 | ✅ |
| `deal_joy/supabase/functions/stripe-webhook/index.ts` | 清理（移除错误添加的 transfer 处理函数） | — | ✅ |
| `deal_joy/supabase/functions/auto-withdrawal/index.ts` | 新建 Edge Function | 五（可选） | ⬜ |

---

## 关键业务逻辑约束

### 一、T+7 结算锁定规则

**规则：** 核销后满 7 天的净收入才计入可提现余额，7 天内的核销收入属于 `pending_settlement`（待结算），不可提现。

**原因：** 平台承诺"随时退款"政策，用户在核销后仍可申请退款。7 天窗口期用于覆盖退款风险：
- `pending_settlement` 期间发生退款 → 该笔收入从未进入可提现池，无需扣回
- 满 7 天后才纳入可提现余额 → 商家资金安全有保障

**代码位置：** `merchant-withdrawal/index.ts` → `handleGetBalance()` → `settledCutoff = now - 7 days`

---

### 二、商家侧 Coupon 支付状态跟踪（merchant_status）

**背景：** `order_items.merchant_status` 字段使用 `merchant_item_status` 枚举，专门为商家视角设计，包含完整的支付生命周期：

| merchant_status 值 | 含义 | 显示给商家 |
|--------------------|------|-----------|
| `unused` | 未核销 | Unredeemed |
| `unpaid` | 已核销，待结算 | Pending Settlement |
| `pending` | T+7 已过，结算中 | Processing |
| `paid` | 已结算，已纳入提现 | Paid Out |
| `refund_request` | 用户申请退款 | Refund Requested |
| `refund_review` | 管理员审核中 | Under Review |
| `refund_reject` | 退款被拒 | Refund Rejected |
| `refund_success` | 退款成功 | Refunded |

**实现方式：** 提现成功后，在 `handleWithdraw` 的 try 块内通过 FIFO 逻辑批量将对应券的 `merchant_status` 更新为 `paid`（详见阶段三）。

---

## 邮件通知一览

| 邮件码 | 触发时机 | 收件方 | 触发位置 |
|--------|---------|--------|---------|
| M14 | 提现申请受理（已移除，改为直接发 M15） | 商家 | — |
| M15 | Transfer 成功，提现完成 | 商家 | `handleWithdraw` try 块 |
| M18 | Transfer 失败 | 商家 | `handleWithdraw` catch 块 |
| A7 | 商家发起提现（通知管理员） | 管理员 | `handleWithdraw` try 块 |

---

## 安全规范（必须遵守）

1. **Stripe 密钥只从环境变量读取**：`Deno.env.get('STRIPE_SECRET_KEY')`，不得硬编码
2. **Connect Account Link 回调 URL**：`STRIPE_CONNECT_RETURN_URL`、`STRIPE_CONNECT_REFRESH_URL` 必须为 **https**（Stripe 不接受 `dealjoymerchant://`）；可用静态页再跳回 App 深链，见 `docs/stripe-connect-redirect/redirect.html` 与测试文档「前置条件 0」
3. **Transfer 幂等 Key**：使用 `withdrawal.id` 作为 `idempotencyKey`，防止网络重试导致重复打款
4. **stripe_account_id 由后端创建**：不能接受客户端传入的 `stripe_account_id` 声称绑定完成
5. **Webhook 签名验证不可移除**：`stripe-webhook` 的 `stripe.webhooks.constructEventAsync()` 验证必须保留

---

## 部署记录

| 操作 | 命令 / 方式 | 状态 |
|------|------------|------|
| 部署 `merchant-withdrawal` | `supabase functions deploy merchant-withdrawal --no-verify-jwt` | ✅ 已完成 |
| 部署 `stripe-webhook` | `supabase functions deploy stripe-webhook --no-verify-jwt` | ✅ 已完成 |
| 推送 M18 migration | Supabase Dashboard → SQL Editor 手动执行 | ✅ 已完成 |
| Stripe Dashboard Webhook 配置 | 无需额外配置（Transfer 为同步操作） | ✅ 无需操作 |
