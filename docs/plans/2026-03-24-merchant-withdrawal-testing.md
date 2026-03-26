# 商家提现系统 — 测试流程文档

> **日期：** 2026-03-24
> **关联计划书：** [2026-03-24-merchant-withdrawal-system.md](./2026-03-24-merchant-withdrawal-system.md)
> **测试环境：** Stripe Test Mode + Supabase 生产环境（kqyolvmgrdekybjrwizx）

---

## 测试前置条件

开始测试前，请确认以下项已就绪：

### ✅ 前置条件 0 — Connect onboarding 回调 URL（HTTPS，必填）

Stripe 创建 **Account Link** 时，`return_url` / `refresh_url` **不能**使用 `dealjoymerchant://` 等自定义 scheme，否则会报错 **`Not a valid URL`**。

请在 **Supabase Dashboard → Project Settings → Edge Functions → Secrets** 为 `merchant-withdrawal` 配置（或通过 CLI `supabase secrets set`）：

| Secret | 说明 |
|--------|------|
| `STRIPE_CONNECT_RETURN_URL` | 完整 **https** URL，用户完成 onboarding 后由 Stripe 打开 |
| `STRIPE_CONNECT_REFRESH_URL` | 完整 **https** URL，链接过期需刷新流程时由 Stripe 打开 |

**推荐做法：** 将仓库内静态页 `docs/stripe-connect-redirect/redirect.html` 部署到任意 HTTPS 静态托管，例如：

- `STRIPE_CONNECT_RETURN_URL` = `https://<你的域名>/redirect.html?result=success`
- `STRIPE_CONNECT_REFRESH_URL` = `https://<你的域名>/redirect.html?result=refresh`

该页面会立即跳转到 App 深链 `dealjoymerchant://stripe-callback?result=...`（请确认商家端已配置对应 Android/iOS 深链）。

配置后需 **重新部署** `merchant-withdrawal` Edge Function 使运行时读取到新 Secrets。

---

### ✅ 前置条件 1 — 平台 Stripe 账户有测试余额

`stripe.transfers.create()` 从平台账户向商家转账，平台账户必须有足够余额。

**操作：** Stripe Dashboard（Test Mode）→ Balance → 点击 **"Add to balance"** 充入测试资金（建议 ≥ $100）

---

### ✅ 前置条件 2 — 测试商家有可提现余额

可提现余额 = 核销时间 > 7 天的订单净收入。如果没有真实数据，执行以下 SQL：

```sql
-- 将测试商家的已核销订单时间改为 8 天前，使其进入可结算状态
UPDATE order_items
SET redeemed_at = NOW() - INTERVAL '8 days',
    merchant_status = 'unpaid'
WHERE merchant_id = '<your_merchant_id>'
  AND merchant_status = 'unpaid'
  AND redeemed_at IS NOT NULL
LIMIT 5;
```

执行后在 App → Earnings 页面刷新，确认 **Available Balance** 有可用金额。

---

### ✅ 前置条件 3 — Stripe Test Mode 测试数据

Stripe onboarding 过程中使用以下测试数据：

| 字段 | 测试值 |
|------|--------|
| 手机号 | `000 000 0000` |
| 短信验证码 | `000000` |
| SSN 末四位 | `0000` |
| 银行路由号（Routing Number） | `110000000` |
| 银行账号（Account Number） | `000123456789` |

---

## 测试流程

### Step 1 — 绑定 Stripe Connect 账户

| # | 操作步骤 | 预期结果 |
|---|---------|---------|
| 1 | 打开商家端 App → Earnings → Payment Account | 页面正常加载，显示未连接状态 |
| 2 | 点击 **"Connect Stripe Account"** 按钮 | 跳转到 Stripe 托管的 onboarding 页面 |
| 3 | 按前置条件 3 的测试数据完成 onboarding | Stripe 显示 onboarding 完成 |
| 4 | 返回 App，点击 **"Refresh Status"** 按钮 | 页面显示绿色 "Connected" badge，显示银行账户末四位 |

**数据库验证：**
```sql
SELECT stripe_account_id, stripe_account_status
FROM merchants
WHERE id = '<your_merchant_id>';

SELECT status, last4, bank_name
FROM merchant_bank_accounts
WHERE merchant_id = '<your_merchant_id>';
```
预期：`stripe_account_status = 'connected'`，`status = 'verified'`

---

### Step 2 — 验证可提现余额显示

| # | 操作步骤 | 预期结果 |
|---|---------|---------|
| 1 | App → Earnings 主页面 | Available Balance 显示正确金额（仅含 T+7 已结算部分） |
| 2 | 检查 Pending Settlement 金额 | 7 天内核销的金额显示在待结算区域，不计入可提现 |

---

### Step 3 — 正常提现流程（核心测试）

| # | 操作步骤 | 预期结果 |
|---|---------|---------|
| 1 | App → Earnings → 点击 **"Withdraw"** | 进入提现页面 |
| 2 | 输入提现金额（≥ $10，≤ Available Balance） | 金额输入正常 |
| 3 | 确认提交 | 请求成功，跳转至提现历史页面 |
| 4 | 查看提现记录状态 | 状态显示 **"Completed"** |

**数据库验证：**
```sql
SELECT id, amount, status, stripe_transfer_id, completed_at
FROM withdrawals
WHERE merchant_id = '<your_merchant_id>'
ORDER BY created_at DESC
LIMIT 1;
```
预期：`status = 'completed'`，`stripe_transfer_id` 有值，`completed_at` 有时间戳

**Stripe Dashboard 验证：**
前往 Stripe Dashboard（Test Mode）→ Balance → Transfers，应看到对应金额的 Transfer 记录。

**order_items 验证：**
```sql
SELECT id, merchant_status, redeemed_at
FROM order_items
WHERE merchant_id = '<your_merchant_id>'
  AND merchant_status = 'paid'
ORDER BY redeemed_at ASC;
```
预期：最早核销的若干条记录已被标记为 `paid`（FIFO 逻辑）

**邮件验证：**
检查商家注册邮箱，应收到 **M15 提现完成邮件**（主题含提现金额）。

---

### Step 4 — 提现失败场景测试

| # | 操作步骤 | 预期结果 |
|---|---------|---------|
| 1 | 在 Stripe Dashboard → Connected Accounts → 找到测试账户 → 撤销/Reject | 账户变为受限状态 |
| 2 | 回到 App 发起提现 | App 收到错误提示，请求失败 |
| 3 | 检查数据库提现记录 | `status = 'failed'`，`failure_reason` 有 Stripe 错误信息 |
| 4 | 检查商家邮箱 | 收到 **M18 提现失败邮件** |

**数据库验证：**
```sql
SELECT status, failure_reason
FROM withdrawals
WHERE merchant_id = '<your_merchant_id>'
ORDER BY created_at DESC
LIMIT 1;
```

---

### Step 5 — 边界条件测试

| # | 测试场景 | 操作 | 预期结果 |
|---|---------|------|---------|
| 1 | 金额低于最低限制 | 输入 $5 提交 | 报错：Minimum withdrawal amount is $10.00 |
| 2 | 金额超过可提现余额 | 输入超额金额提交 | 报错：Insufficient balance |
| 3 | 重复提现拦截 | 提现进行中时再次提交 | 报错：You already have a pending withdrawal |
| 4 | 未绑定银行账户时提现 | 断开账户后尝试提现 | 报错：No verified bank account found |

---

### Step 6 — Stripe Express Dashboard 入口测试

| # | 操作步骤 | 预期结果 |
|---|---------|---------|
| 1 | Payment Account 页面（已连接状态） | 显示 "Manage on Stripe" 按钮 |
| 2 | 点击 **"Manage on Stripe"** | 跳转到 Stripe Express Dashboard（商家可查看余额、银行账户） |

---

## 完整测试检查清单

完成测试后逐项打勾：

| 测试项 | 预期结果 | 测试状态 |
|--------|---------|---------|
| Connect 按钮跳转 Stripe onboarding | 成功打开 Stripe 页面 | ⬜ |
| Refresh Status 同步账户状态 | 显示 Connected + 银行末四位 | ⬜ |
| Available Balance 显示正确 | 仅含 T+7 已结算金额 | ⬜ |
| 正常提现流程 | `status = completed`，Transfer 出现在 Stripe | ⬜ |
| M15 邮件送达 | 商家邮箱收到完成通知 | ⬜ |
| order_items FIFO 标记 | 对应券 `merchant_status = paid` | ⬜ |
| 提现失败场景 | `status = failed`，M18 邮件送达 | ⬜ |
| Manage on Stripe 按钮 | 跳转 Express Dashboard | ⬜ |
| 重复提现拦截 | 有进行中记录时报错 | ⬜ |
| 低于最低金额拦截 | 金额 < $10 时报错 | ⬜ |
| 超出可提现余额拦截 | 超额时报错 | ⬜ |
| 未绑定账户拦截 | 无 verified 账户时报错 | ⬜ |

---

## 常见问题排查

### 提现后状态仍为 "pending" 而非 "completed"
- 检查 Edge Function 是否已部署最新版本：`supabase functions deploy merchant-withdrawal`
- 查看 Supabase Dashboard → Edge Functions → merchant-withdrawal → Logs

### Stripe Transfer 报错 "Insufficient funds"
- 平台 Stripe 账户余额不足，前往 Stripe Dashboard → Balance 充值

### Refresh Status 后仍显示未连接
- 检查商家是否真正完成了 Stripe onboarding（Stripe Dashboard → Connected Accounts 中确认状态）
- 查看 `/connect/refresh` 接口返回值

### M15 / M18 邮件未收到
- 检查 `email_logs` 表中是否有对应记录
- 确认商家账户邮箱地址正确
- 检查垃圾邮件文件夹
