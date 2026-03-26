# 商家可提现余额计算逻辑修复分析

> **日期：** 2026-03-26
> **状态：** ✅ 已修复（2026-03-26）
> **严重程度：** 高 — 当前计算结果对部分商家（免费期/专属费率）存在明显错误金额

---

## 一、背景：系统中存在两套并行的计算体系

商家端 App 有两处展示商家收入的地方，它们使用了完全不同的计算逻辑：

| 页面 | 入口 Edge Function | 核心计算 | 数据来源 |
|------|-------------------|---------|---------|
| Earnings（收益概览） | `merchant-earnings` | RPC `get_merchant_transactions` / `get_merchant_earnings_summary` | `order_items` 表 |
| Withdrawal（可提现余额） | `merchant-withdrawal` `/balance` | `handleGetBalance()` 内联逻辑 | `coupons` + `orders` 表 |

**这两套体系应该给出相同的数字，但实际上并不一致。** 本文分析差异的根源并提出修复方案。

---

## 二、与可提现金额计算相关的全部数据

### 2.1 核心数据表

**`order_items`**（权威数据源，应以此为准）

| 字段 | 含义 |
|------|------|
| `id` | 行 ID |
| `order_id` | 所属订单 |
| `deal_id` | 所属 deal |
| `unit_price` | 单件售价（商家净收入的计算基数） |
| `service_fee` | 预先计算的手续费（字段存在但当前 `/balance` 未使用） |
| `customer_status` | 客户侧状态（`used` / `refund_success` / `refund_pending` 等） |
| `merchant_status` | 商家侧状态（`unused` / `unpaid` / `paid` 等） |
| `redeemed_at` | 核销时间（T+7 判断的权威字段） |
| `redeemed_merchant_id` | 实际核销门店 ID（用于多门店归属） |
| `created_at` | 购买时间（用于判断是否在免费期内） |

**`coupons`**（`/balance` 当前正在使用，但不应该用这个）

| 字段 | 含义 |
|------|------|
| `order_id` | 所属订单 |
| `status` | `used` / `refunded` 等 |
| `used_at` | 核销时间（与 `order_items.redeemed_at` 含义相同，但字段不同） |
| `redeemed_at_merchant_id` | 实际核销门店 |
| `merchant_id` | 所属商家 |

**`orders`**（`/balance` 当前正在使用，但取的是整单金额）

| 字段 | 含义 |
|------|------|
| `total_amount` | 整笔订单总金额（含所有 items，不是单件价格） |

**`platform_commission_config`**（全局费率，只有一行）

| 字段 | 默认值 | 含义 |
|------|--------|------|
| `commission_rate` | 0.15 | 平台抽成比例（15%） |
| `stripe_processing_rate` | 0.03 | Stripe 手续费比例（3%） |
| `stripe_flat_fee` | 0.30 | Stripe 固定费（$0.30/笔） |

**`merchants`**（商家专属费率覆盖，NULL = 使用全局默认）

| 字段 | 含义 |
|------|------|
| `commission_rate` | 专属平台抽成比例（NULL = 用全局） |
| `commission_stripe_rate` | 专属 Stripe 比例（NULL = 用全局） |
| `commission_stripe_flat_fee` | 专属 Stripe 固定费（NULL = 用全局） |
| `commission_effective_from` | 专属费率生效开始日（NULL = 永久生效） |
| `commission_effective_to` | 专属费率失效日（NULL = 永久生效） |
| `commission_free_until` | **免费期截止日**（此日期当天及之前：平台抽成为 0，但 Stripe 手续费仍然收取） |

**`withdrawals`**（已提现记录）

| 字段 | 含义 |
|------|------|
| `amount` | 提现金额 |
| `status` | `pending` / `processing` / `completed` / `failed` |

### 2.2 费率优先级规则

> **权威依据：** 迁移文件 `20260324000003_commission_stripe_fee_split.sql`（最新版本，覆盖了 `20260320000005` 的旧逻辑）

```
判断 order_item 的商家净收入时，费率生效步骤：

Step 1：读取全局费率（platform_commission_config）
  v_commission_rate = commission_rate（默认 0.15）
  v_stripe_rate     = stripe_processing_rate（默认 0.03）
  v_stripe_flat_fee = stripe_flat_fee（默认 $0.30）

Step 2：读取商家专属费率（merchants），若在生效期内则覆盖全局
  IF merchants.commission_rate IS NOT NULL
     AND 今天在 commission_effective_from ~ commission_effective_to 之间（或无限期）
     → v_commission_rate = merchants.commission_rate
  （v_stripe_rate / v_stripe_flat_fee 同理）

Step 3：免费期判断（⚠️ 只免平台抽成，Stripe 费仍然收取）
  IF NOW() <= merchants.commission_free_until
     → v_commission_rate = 0
     （v_stripe_rate 和 v_stripe_flat_fee 不变，仍正常计算）

Step 4：计算 net_amount（对所有 order_item 统一使用同一公式）
  platform_fee = unit_price × v_commission_rate
  stripe_fee   = unit_price × v_stripe_rate + v_stripe_flat_fee
  net_amount   = unit_price - platform_fee - stripe_fee
```

**免费期示例（$40 订单，全局费率）：**
```
v_commission_rate = 0（免费期覆盖）
v_stripe_rate     = 0.03
v_stripe_flat_fee = 0.30

platform_fee = $40 × 0    = $0.00
stripe_fee   = $40 × 0.03 + $0.30 = $1.50
net_amount   = $40 - $0 - $1.50   = $38.50
```

### 2.3 T+7 结算锁定规则

只有核销时间超过 7 天的订单才进入可提现池：
```
settledCutoff = NOW() - INTERVAL '7 days'
可结算条件：order_items.redeemed_at < settledCutoff
```

---

## 三、当前错误的计算方法（`/balance` 现状）

**文件：** `deal_joy/supabase/functions/merchant-withdrawal/index.ts` → `handleGetBalance()`

### 3.1 当前计算公式

```
totalSettled          = SUM(orders.total_amount × 0.85)    ← 查 coupons → 关联 orders
totalWithdrawn        = SUM(withdrawals.amount)            ← 已提现
totalRefundDeductions = SUM(退款订单的 total_amount × 0.85) ← 退款扣除
availableBalance      = totalSettled - totalWithdrawn - totalRefundDeductions
```

### 3.2 错误点清单

| # | 错误描述 | 影响 |
|---|---------|------|
| **E1** | 使用 `orders.total_amount × 0.85` 固定比例，不读取数据库中的实际费率配置 | 全局费率改变时，/balance 仍用旧的 15% |
| **E2** | **完全忽略免费期**（`commission_free_until`）| 免费期内的商家被错误扣除 15% 平台抽成，导致显示金额偏低（Stripe 费本应仍然扣除） |
| **E3** | **完全忽略商家专属费率**（`commission_rate` 等）| 有专属费率优惠的商家计算金额不正确 |
| **E4** | **未扣除 Stripe 手续费**，只扣了平台 15%，实际上还有 3% + $0.30 | 显示金额偏高（Stripe 费用未体现） |
| **E5** | 数据来源是 `coupons` 表，而正确来源应为 `order_items` 表 | 两套数据可能出现不一致 |
| **E6** | 使用 `coupons.used_at` 做 T+7 判断，而 FIFO 更新用的是 `order_items.redeemed_at` | 同一个业务概念用了两个不同字段，口径不一致 |
| **E7** | 以 `orders.total_amount` 作为单件计算基数，若一笔订单含多张券，会**重复计算** | 多券订单的商家收入被 N 倍放大 |

### 3.3 具体案例：当前测试商家的错误金额

测试商家 "volien company2"（id: `92b67299-a166-4043-9294-ea272a8956d4`）：

| 字段 | 值 |
|------|---|
| `commission_free_until` | `2026-06-21`（**今天 2026-03-26 仍在免费期内**） |
| `commission_rate` | NULL（用全局 15%） |

**当前 `/balance` 显示：$34.84**（按 `total_amount × 0.85` 计算）

**正确金额应为：`unit_price × 已结算条数 - Stripe 费合计 - 已提现`**

以该商家的某笔 $40 已结算订单为例：
```
正确计算（免费期，v_commission_rate = 0）：
  net_amount = $40 - $0 - ($40 × 0.03 + $0.30) = $40 - $1.50 = $38.50

当前错误计算：
  net_amount = $40 × 0.85 = $34.00（错误扣除了 15% 平台抽成）

差额：+$4.00（商家少显示了 15% 平台抽成的金额）
```

> ⚠️ **重要更正（2026-03-26）：** 免费期并非"全额，零抽成零 Stripe 费"。
> 正确规则是：**免费期 = 平台抽成为 0，Stripe 手续费仍然收取**。
> 依据：迁移文件 `20260324000003` 中明确注释 `-- 免费期内 commission = 0（Stripe 费仍需支付）`。

---

## 四、正确的计算方法

应与最新版 RPC（`20260324000003_commission_stripe_fee_split.sql`）保持完全一致。

### 4.1 正确公式

```
Step 1：读取费率（与 get_merchant_earnings_summary 完全相同的逻辑）
  a. 从 platform_commission_config 读取全局费率
  b. 从 merchants 读取专属费率，若在生效期内则覆盖全局
  c. 若 NOW() <= commission_free_until：v_commission_rate = 0（只免平台费，Stripe 费不变）

Step 2：查询已结算的 order_items（T+7 已解锁）
  查询条件：
  - COALESCE(redeemed_merchant_id, purchased_merchant_id) = 当前商家
  - customer_status NOT IN ('refund_success', 'refund_pending')
  - redeemed_at < NOW() - INTERVAL '7 days'（T+7 已过）
  - redeemed_at IS NOT NULL

Step 3：对每条 order_item 计算 net_amount（统一公式，无 IF 分支）
  platform_fee = unit_price × v_commission_rate   ← 免费期时此项为 0
  stripe_fee   = unit_price × v_stripe_rate + v_stripe_flat_fee
  net_amount   = unit_price - platform_fee - stripe_fee

Step 4：汇总
  totalSettled     = SUM(net_amount)
  totalWithdrawn   = SUM(withdrawals.amount WHERE status IN ('completed','processing','pending'))
  availableBalance = MAX(0, totalSettled - totalWithdrawn)

注：退款通过 customer_status 过滤排除，无需单独的退款扣除项
```

### 4.2 与 Earnings 页面数据的对应关系

```
Earnings 页 Pending  = 已核销且 redeemed_at > NOW()-7天 的 net_amount 之和（锁定中）
Withdrawal 页余额    = 已核销且 redeemed_at < NOW()-7天 的 net_amount 之和 − 已提现（可提现）

两者使用完全相同的 net_amount 公式，差别仅在 T+7 的过滤方向。
修复后两个页面的数字加在一起 = 商家当前所有未退款核销收入的净值。
```

---

## 五、修复内容（✅ 已于 2026-03-26 完成并部署）

### 5.1 主要修复：`handleGetBalance()` 完全重写

**文件：** `deal_joy/supabase/functions/merchant-withdrawal/index.ts`

| 对比项 | 修复前 | 修复后 |
|--------|--------|--------|
| 数据来源 | `coupons` + `orders` 两张表 | `order_items` 一张表 |
| T+7 判断字段 | `coupons.used_at` | `order_items.redeemed_at` |
| 费率来源 | 固定 `× 0.85` 硬编码 | 动态读取 `platform_commission_config` + `merchants` |
| 免费期 | 完全忽略 | `v_commission_rate = 0`，Stripe 费仍收取 |
| 商家专属费率 | 完全忽略 | 按生效期判断后覆盖全局费率 |
| 退款处理 | 单独查 `refunded` coupons 再手动扣除 | `customer_status NOT IN ('refund_success','refund_pending')` 直接过滤 |
| 响应字段 | `total_refund_deductions`（已删除） | 新增 `effective_commission_rate`、`effective_stripe_rate`、`effective_stripe_flat_fee`（方便前端调试） |

修复后的核心逻辑与 `get_merchant_earnings_summary` RPC 完全对齐：
```typescript
// 读取全局费率 → 读取商家专属费率 → 判断专属费率生效期 → 免费期置 commission = 0
// 查 order_items WHERE redeemed_at < T-7 AND customer_status NOT IN (refund_*)
// net = unit_price - unit_price * vCommissionRate - (unit_price * vStripeRate + vStripeFlatFee)
// availableBalance = SUM(net) - totalWithdrawn
```

### 5.2 次要修复：FIFO 净值计算同步更新

**文件：** `deal_joy/supabase/functions/merchant-withdrawal/index.ts`
**函数：** `handleWithdraw()` → FIFO 更新逻辑

修复内容：
- 在 FIFO 执行前读取相同的费率配置（`fifoCommRate` / `fifoStrRate` / `fifoStrFlat`）
- 将净值计算从 `unit_price - service_fee`（字段含义不明）改为：
  ```typescript
  const net = unitPrice - unitPrice * fifoCommRate - (unitPrice * fifoStrRate + fifoStrFlat);
  ```
- 确保"提现了多少钱"与"标记了多少 order_items 为 paid"使用同一套公式，口径一致

### 5.3 未修改的位置（确认无需改动）

- `merchant-earnings` Edge Function — 已使用正确逻辑
- `get_merchant_transactions` RPC — 正确，作为本次修复的参考标准
- `get_merchant_earnings_summary` RPC — 正确，作为本次修复的参考标准
- 前端代码（Withdrawal 页面）— 仅展示后端返回值，无需改动
- 管理后台 Commission Config 页面 — 功能正常，无需改动

### 5.4 部署记录

```
部署时间：2026-03-26
部署命令：supabase functions deploy merchant-withdrawal --no-verify-jwt --project-ref kqyolvmgrdekybjrwizx
部署结果：成功
```

---

## 六、修复后验证方法

### 6.1 测试数据准备（重要）

由于 `/balance` 现在统一使用 `order_items.redeemed_at` 做 T+7 判断，测试时需同时更新两张表：

```sql
-- Step 1：查出目标 order_item
SELECT oi.id, oi.redeemed_at, c.used_at
FROM order_items oi
JOIN coupons c ON c.order_id = oi.order_id
WHERE c.merchant_id = '<merchant_id>'
  AND c.status = 'used'
ORDER BY c.used_at DESC LIMIT 5;

-- Step 2：同时将两张表的时间字段回拨至 8 天前
UPDATE order_items SET redeemed_at = NOW() - INTERVAL '8 days' WHERE id = '<order_item_id>';
UPDATE coupons       SET used_at   = NOW() - INTERVAL '8 days' WHERE order_id = '<order_id>';
```

### 6.2 交叉验证 SQL

```sql
-- 1. 验证免费期商家（commission_free_until 未过期）
--    免费期规则：平台抽成 = 0，Stripe 费仍收取
--    修复后 available_balance 应 ≈ SUM(unit_price - stripe_fee) - 已提现
SELECT
  m.name,
  m.commission_free_until,
  SUM(oi.unit_price) AS gross_settled,
  SUM(oi.unit_price * 0.03 + 0.30) AS total_stripe_fee,
  SUM(oi.unit_price - (oi.unit_price * 0.03 + 0.30)) AS expected_net
FROM merchants m
JOIN order_items oi ON COALESCE(oi.redeemed_merchant_id, oi.purchased_merchant_id) = m.id
WHERE NOW() <= m.commission_free_until
  AND oi.redeemed_at < NOW() - INTERVAL '7 days'
  AND oi.customer_status NOT IN ('refund_success', 'refund_pending')
  AND oi.redeemed_at IS NOT NULL
GROUP BY m.id, m.name, m.commission_free_until;

-- 2. 验证普通商家
--    修复后 available_balance ≈ SUM(unit_price × (1 - rate - stripe_rate) - stripe_flat)
SELECT
  m.name,
  COALESCE(m.commission_rate, p.commission_rate) AS v_rate,
  COALESCE(m.commission_stripe_rate, p.stripe_processing_rate) AS v_stripe_rate,
  COALESCE(m.commission_stripe_flat_fee, p.stripe_flat_fee) AS v_flat
FROM merchants m
CROSS JOIN platform_commission_config p
WHERE m.id = '<your_merchant_id>';
```

---

### 6.3 已发现并修复的附加问题

**"同一笔交易既可提现又在 Pending"的矛盾现象（2026-03-26 发现）**

原因：测试时只回拨了 `coupons.used_at`，未同步更新 `order_items.redeemed_at`。
- `/balance`（旧）读 `coupons.used_at` → 认为 T+7 已过 → 计入可提现
- Earnings RPC 读 `order_items.redeemed_at` → 认为在 T+7 内 → 计入 Pending

**修复后两个系统统一使用 `order_items.redeemed_at`，矛盾消除。**

---

## 七、风险与注意事项

| 风险 | 说明 |
|------|------|
| **可能导致可提现余额变高** | 免费期商家修复后平台抽成归零，余额会升高（这是正确的）。但 Stripe 费仍会扣除，余额不会等于原始金额全额 |
| **可能导致可提现余额变低** | Stripe 费之前未计入，修复后会被扣除，余额会略有下降（这也是正确的） |
| **需同步更新测试文档** | `docs/plans/2026-03-24-merchant-withdrawal-testing.md` 中的验证 SQL 需要相应更新 |
| **FIFO 一致性** | 修复 `/balance` 后，FIFO 标记的金额也需要与新公式一致，否则 `merchant_status = paid` 的标记数量会出现偏差 |

---

## 八、相关文件索引

| 文件 | 角色 |
|------|------|
| `deal_joy/supabase/functions/merchant-withdrawal/index.ts` | **待修复**：`handleGetBalance()` |
| `deal_joy/supabase/functions/merchant-earnings/index.ts` | 参考：费率读取逻辑 |
| `deal_joy/supabase/migrations/20260324000003_commission_stripe_fee_split.sql` | **权威参考**：最新版 RPC，明确了免费期只免平台抽成、Stripe 费仍收取的规则 |
| `deal_joy/supabase/migrations/20260320000005_unified_commission_rate.sql` | 历史参考：旧版 RPC（已被 20260324000003 覆盖，免费期逻辑有差异，勿混用） |
| `admin/components/merchant-commission-form.tsx` | 管理后台：配置免费期和专属费率的入口 |
| `admin/app/actions/admin.ts` → `updateMerchantCommission()` | 管理后台：写入 merchants 表的 Server Action |
