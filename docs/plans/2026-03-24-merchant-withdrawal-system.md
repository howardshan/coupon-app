# 商家提现完整流程开发计划

> **日期：** 2026-03-24
> **状态：** 待开发
> **分支：** tianzuo-coupon1

---

## 背景

商家核销订单后，收益（订单金额 × 85%）进入结算池，T+7 天后变为可提现余额。商家需要在商家端 App 中通过提现功能将余额打款到银行账户。

**当前状态：**
- 前端 UI（earnings/withdrawal/payment_account 等页面）已全部完成
- 数据库表（withdrawals、merchant_bank_accounts、merchant_withdrawal_settings）已存在
- 邮件模板 M14（申请通知）、M15（完成通知）已存在
- `merchant-withdrawal` Edge Function 路由框架存在，但 `handleWithdraw` 中有 TODO（实际 Stripe 转账未实现）
- `payment_account_page.dart` 的 Connect 按钮目前只弹 "coming soon"

**目标：** 实现完整的端到端提现流程：Stripe Connect 账户绑定 → 商家申请提现 → 系统自动调用 Stripe Transfer → Webhook 更新状态 → 邮件通知结果

**核心决策：**
- 触发方式：商家申请后**自动**调用 Stripe Transfer，无需管理员审批
- 账户绑定：**Stripe Connect Express**（Stripe 托管 onboarding 页面）

---

## 阶段划分（按依赖顺序）

```
阶段一：Stripe Connect 账户绑定（必须第一步，无 verified 账户无法提现）
    ↓
阶段二：Stripe Transfer 实际执行（替换 handleWithdraw 中的 TODO）
    ↓
阶段三：Stripe Webhook 状态同步（transfer.paid / transfer.failed）
    ↓
阶段四：M18 提现失败邮件（Webhook 触发失败通知所需）
    ↓
阶段五（可选）：自动提现 Cron
```

---

## 阶段一：Stripe Connect Express 账户绑定

### 目标
商家通过 App 完成 Stripe Express 账户注册，绑定银行账户后才能提现。

### 后端修改
**文件：** `deal_joy/supabase/functions/merchant-withdrawal/index.ts`

新增 3 条路由：

1. **`POST /merchant-withdrawal/connect`** — 创建 Connect 账户 + 生成 onboarding URL
   - 若商家已有 `stripe_account_id`，直接生成新的 Account Link（续接 onboarding）
   - 若没有，调用 `stripe.accounts.create({ type: 'express', ... })` 先创建，存入 `merchants.stripe_account_id`
   - 调用 `stripe.accountLinks.create()` 生成 `return_url` 和 `refresh_url`（均指向商家 App 深链 `dealjoymerchant://stripe-callback`）
   - 返回 `{ url: "https://connect.stripe.com/..." }`

2. **`POST /merchant-withdrawal/connect/refresh`** — onboarding 完成后同步账户状态
   - 调用 `stripe.accounts.retrieve(stripe_account_id)` 检查 `charges_enabled` / `payouts_enabled`
   - 更新 `merchants.stripe_account_status`（'connected' 或 'restricted'）
   - 更新 `merchant_bank_accounts` 记录的 `status`（'verified' 或 'pending'）
   - 若账户有银行账户信息（`external_accounts`），提取 `last4` 和 `bank_name` 写入 `merchant_bank_accounts`
   - 返回最新的账户状态

3. **`GET /merchant-withdrawal/connect/dashboard`** — 生成 Stripe Express Dashboard 链接
   - 调用 `stripe.accounts.createLoginLink(stripe_account_id)`
   - 返回 `{ url: "..." }`（用于已连接商家点 "Manage on Stripe"）

### 前端修改
**文件：** `dealjoy_merchant/lib/features/earnings/services/earnings_service.dart`

新增方法：
- `fetchStripeConnectUrl()` — 调用 `POST /connect`，返回 onboarding URL
- `refreshStripeAccountStatus()` — 调用 `POST /connect/refresh`，返回 StripeAccountInfo
- `fetchStripeManageUrl()` — 调用 `GET /connect/dashboard`，返回 Stripe Dashboard URL

**文件：** `dealjoy_merchant/lib/features/earnings/pages/payment_account_page.dart`

修改：
- `_ActionButtons` 的 `onConnectTap` 从 `_showComingSoonTip` 改为：
  1. 调用 `earningsService.fetchStripeConnectUrl()`
  2. 使用 `launchUrl(Uri.parse(url))` 跳转到 Stripe onboarding 页面
- `_ActionButtons` 的 `onManageTap` 改为：
  1. 调用 `earningsService.fetchStripeManageUrl()`
  2. 使用 `launchUrl()` 打开 Stripe Express Dashboard
- 在按钮区域增加 "Refresh Status" 按钮（商家完成 onboarding 后点击同步状态），调用 `refreshStripeAccountStatus()` 后 `ref.invalidate(stripeAccountProvider)`

**pubspec.yaml 确认：** 检查 `dealjoy_merchant/pubspec.yaml` 是否已有 `url_launcher`，如无则添加。

### 验证方法
1. 点击 "Connect Stripe Account" → 跳转到 Stripe Test Mode 的 onboarding 页面
2. 完成测试 onboarding 后回到 App，点 "Refresh Status"
3. 检查 `merchants.stripe_account_status = 'connected'`，`merchant_bank_accounts.status = 'verified'`
4. 页面显示绿色 "Connected" badge 和账户邮箱

---

## 阶段二：Stripe Transfer 实际执行

### 目标
替换 `handleWithdraw` 中的 TODO，商家申请后立即调用 Stripe Transfer。

### 后端修改
**文件：** `deal_joy/supabase/functions/merchant-withdrawal/index.ts`

在文件顶部添加 Stripe 初始化（与 `stripe-webhook/index.ts` 相同的导入方式）：
```typescript
import Stripe from 'https://esm.sh/stripe@14?target=deno';
const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
  apiVersion: '2024-04-10',
  httpClient: Stripe.createFetchHttpClient(),
});
```

替换 `handleWithdraw` 中的 TODO 部分（第 295-296 行）：
```typescript
// 调用 Stripe Transfer API（从平台账户转账到商家 Connected Account）
const transfer = await stripe.transfers.create({
  amount: Math.round(amount * 100),  // 转为分
  currency: 'usd',
  destination: bankAccount.stripe_account_id,
  metadata: { withdrawal_id: withdrawal.id, merchant_id: merchantId },
}, { idempotencyKey: withdrawal.id });  // 幂等 Key 防重复

// 更新提现记录：写入 stripe_transfer_id，状态变为 processing
await admin.from('withdrawals').update({
  stripe_transfer_id: transfer.id,
  status: 'processing',
}).eq('id', withdrawal.id);
```

同时添加错误处理：若 Stripe 调用抛出异常，将 `withdrawals.status` 更新为 `'failed'`，并记录 `failure_reason`。

### 验证方法
1. 确保商家有 verified 的 Stripe 账户，且有 Available Balance
2. 在 App 中发起提现
3. 在 Stripe Test Dashboard → Balance → Transfers 看到一条 Transfer 记录
4. `withdrawals` 表：`stripe_transfer_id` 有值，`status = 'processing'`

---

## 阶段三：Stripe Webhook 状态同步

### 目标
通过 Stripe Webhook 事件自动更新提现状态，并触发邮件通知。

### 后端修改
**文件：** `deal_joy/supabase/functions/stripe-webhook/index.ts`

新增 import（阶段四完成后）：
```typescript
import { buildM15Email } from '../_shared/email-templates/merchant/withdrawal-completed.ts';
import { buildM18Email } from '../_shared/email-templates/merchant/withdrawal-failed.ts';
```

新增两个处理函数：

**`handleTransferPaid(transfer)`**
- 通过 `transfer.metadata.withdrawal_id` 找到 `withdrawals` 记录
- 更新 `status = 'completed'`，`completed_at = now()`
- 查询商家信息 → 发送 M15 邮件（提现完成通知）

**`handleTransferFailed(transfer)`**
- 通过 `transfer.metadata.withdrawal_id` 找到 `withdrawals` 记录
- 更新 `status = 'failed'`，`failure_reason = transfer.failure_message`
- 查询商家信息 → 发送 M18 邮件（提现失败通知）

在主 `switch (event.type)` 中注册：
```typescript
case 'transfer.paid': await handleTransferPaid(event.data.object); break;
case 'transfer.failed': await handleTransferFailed(event.data.object); break;
```

### Stripe Dashboard 配置
在 Stripe Dashboard → Webhooks → 当前 endpoint，添加监听事件：
- `transfer.paid`
- `transfer.failed`

### 验证方法
使用 Stripe CLI 触发测试事件：
```bash
stripe trigger transfer.paid
stripe trigger transfer.failed
```
检查 `withdrawals.status` 更新正确，商家收到对应邮件。

---

## 阶段四：M18 提现失败邮件

### 目标
创建提现失败通知邮件模板，注册新邮件类型代码 M18。

### 文件修改

**新建：** `deal_joy/supabase/functions/_shared/email-templates/merchant/withdrawal-failed.ts`

参照 `withdrawal-completed.ts`（M15）的结构，实现：
- 接口：`M18WithdrawalFailedData`（含 merchantName, withdrawalId, amount, failureReason?）
- 函数：`buildM18Email()` — 主题 `"We couldn't process your withdrawal of $X"`
- 内容：说明失败原因（若有），提示联系支持

**新建 migration：** `deal_joy/supabase/migrations/20260324000002_email_type_m18.sql`
```sql
INSERT INTO email_type_settings (email_code, email_name, recipient_type, user_configurable)
VALUES ('M18', 'Withdrawal Failed', 'merchant', FALSE)
ON CONFLICT (email_code) DO NOTHING;
```

---

## 阶段五（可选）：自动提现 Cron

### 目标
对启用了自动提现的商家，按设定周期自动触发提现（复用阶段二的 Stripe Transfer 逻辑）。

### 文件修改

**新建：** `deal_joy/supabase/functions/auto-withdrawal/index.ts`
- 查询 `merchant_withdrawal_settings` 中 `auto_withdrawal_enabled = true` 的商家
- 判断今天是否为触发日期（按 frequency 和 auto_withdrawal_day）
- 幂等检查：当天已有 pending/processing 记录则跳过
- 对满足条件的商家触发提现（余额 >= min_withdrawal_amount）

**新建 migration：** `deal_joy/supabase/migrations/YYYYMMDD_auto_withdrawal_cron.sql`
```sql
SELECT cron.schedule(
  'auto-withdrawal-daily',
  '0 10 * * *',  -- 每天 UTC 10:00（对应 Dallas CST 05:00）
  $$ SELECT net.http_post(url := 'https://kqyolvmgrdekybjrwizx.supabase.co/functions/v1/auto-withdrawal', ...) $$
);
```

---

## 关键文件清单

| 文件 | 变更类型 | 阶段 |
|------|---------|------|
| `deal_joy/supabase/functions/merchant-withdrawal/index.ts` | 修改（新增 3 条 Connect 路由 + 替换 TODO Transfer 调用） | 一、二 |
| `deal_joy/supabase/functions/stripe-webhook/index.ts` | 修改（新增 transfer.paid/failed 事件处理） | 三 |
| `deal_joy/supabase/functions/_shared/email-templates/merchant/withdrawal-failed.ts` | 新建 M18 邮件模板 | 四 |
| `deal_joy/supabase/migrations/20260324000002_email_type_m18.sql` | 新建 migration | 四 |
| `dealjoy_merchant/lib/features/earnings/services/earnings_service.dart` | 修改（新增 fetchStripeConnectUrl / refreshStripeAccountStatus / fetchStripeManageUrl） | 一 |
| `dealjoy_merchant/lib/features/earnings/pages/payment_account_page.dart` | 修改（Connect / Manage 按钮接真实逻辑，新增 Refresh Status 按钮） | 一 |
| `deal_joy/supabase/functions/auto-withdrawal/index.ts` | 新建 Edge Function | 五（可选） |

---

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

**背景：** 数据库中 `order_items.merchant_status` 字段使用 `merchant_item_status` 枚举，专门为商家视角设计，包含完整的支付生命周期：

| merchant_status 值 | 含义 | 显示给商家 |
|--------------------|------|-----------|
| `unused` | 未核销（所有适用门店可见） | Unredeemed |
| `unpaid` | 已核销，T+7 内待结算 | Pending Settlement |
| `pending` | T+7 已过，结算处理中 | Processing |
| `paid` | 已结算，已纳入提现 | Paid Out |
| `refund_request` | 用户申请退款 | Refund Requested |
| `refund_review` | 管理员审核中 | Under Review |
| `refund_reject` | 退款被拒 | Refund Rejected |
| `refund_success` | 退款成功 | Refunded |

**当前缺口：** 提现系统目前使用"总已结算 - 总已提现"减法计算可用余额，**但当提现完成时，对应券的 `merchant_status` 并未被更新为 `paid`**。这导致：
1. 商家在订单页看到的券状态始终是 `unpaid`，无法判断该笔收入是否已被提现
2. 缺乏逐条券级别的 payout 追溯能力

**需要实现的逻辑：**
- 当 Stripe Transfer 完成（`transfer.paid` Webhook 触发）时，需要根据该次提现金额，将对应的已结算券（`merchant_status = 'unpaid'`，`used_at < T-7`）按时间顺序批量更新为 `paid`
- **注意：** 提现金额可能覆盖多张不同订单的券（FIFO 原则：优先标记最早核销的券为 paid）
- 这个逻辑应在阶段三（Stripe Webhook 处理）的 `handleTransferPaid()` 函数中实现

**涉及文件：**
- `deal_joy/supabase/functions/stripe-webhook/index.ts` — `handleTransferPaid()` 中追加 `order_items.merchant_status` 批量更新逻辑
- 商家端 `merchant-orders` Edge Function 已返回 `merchant_status` 字段，前端 `OrderItem` 模型已有对应字段，**显示层无需额外修改**

---

## 安全规范（必须遵守）

1. **Stripe 密钥只从环境变量读取**：`Deno.env.get('STRIPE_SECRET_KEY')`，不得硬编码
2. **Transfer 幂等 Key**：使用 `withdrawal.id` 作为 `idempotencyKey`，防止网络重试导致重复打款
3. **Transfer metadata 必须含 withdrawal_id**：Webhook 处理函数通过此字段关联提现记录
4. **Webhook 签名验证不可移除**：`stripe-webhook` 的 `stripe.webhooks.constructEventAsync()` 验证必须保留
5. **stripe_account_id 由后端创建**：不能接受客户端传入的 `stripe_account_id` 声称绑定完成

---

## 部署命令

```bash
# 部署 Edge Functions
supabase functions deploy merchant-withdrawal --no-verify-jwt --project-ref kqyolvmgrdekybjrwizx
supabase functions deploy stripe-webhook --no-verify-jwt --project-ref kqyolvmgrdekybjrwizx
supabase functions deploy auto-withdrawal --no-verify-jwt --project-ref kqyolvmgrdekybjrwizx  # 阶段五

# 推送数据库 migration
supabase db push --project-ref kqyolvmgrdekybjrwizx
```
