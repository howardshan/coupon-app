# 购买时门店快照功能 — 现状分析报告

## 一、orders 表完整结构

来源：`deal_joy/supabase/migrations/20260228000000_initial_schema.sql`

```sql
create table public.orders (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid not null references public.users(id),
  deal_id            uuid not null references public.deals(id),
  coupon_id          uuid,          -- nullable，由 on_order_created trigger 自动填充
  quantity           int not null default 1,
  unit_price         numeric(10,2) not null,
  total_amount       numeric(10,2) not null,
  status             order_status not null default 'unused',
  payment_intent_id  text not null,
  stripe_charge_id   text,
  refund_reason      text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
```

**注意**：checkout_repository.dart 在插入订单时使用了 `purchased_merchant_id` 字段，
但该字段不在初始 migration 文件中，推测已在后续 migration 中添加。

coupons 表完整结构：
```sql
create table public.coupons (
  id          uuid primary key default gen_random_uuid(),
  order_id    uuid not null references public.orders(id) on delete cascade,
  user_id     uuid not null references public.users(id),
  deal_id     uuid not null references public.deals(id),
  merchant_id uuid not null references public.merchants(id),
  qr_code     text not null unique,
  status      coupon_status not null default 'unused',  -- unused | used | expired | refunded
  expires_at  timestamptz not null,
  used_at     timestamptz,
  created_at  timestamptz not null default now()
);
```

merchant-scan index.ts 还在 coupons 上读写：
- `redeemed_at`（timestamptz）
- `redeemed_by_merchant_id`（uuid）
- `redeemed_at_merchant_id`（uuid）
- `reverted_at`（timestamptz）
- `gifted_from`（text，见 coupon_model.dart）
- `verified_by`（text，见 coupon_model.dart）

---

## 二、创建订单的完整流程

### 2.1 客户端触发路径

```
CheckoutScreen._pay(total)
  └── CheckoutRepository.checkout(userId, dealId, quantity, total, promoCode?, purchasedMerchantId?)
        ├── 1. _createPaymentIntent(amount, dealId, userId, promoCode?)
        │     └── supabase.functions.invoke('create-payment-intent', body: {...})
        ├── 2. _presentPaymentSheet(clientSecret)  -- Stripe Native Sheet
        └── 3. _createOrder(userId, dealId, quantity, total, paymentIntentId, purchasedMerchantId?)
              └── supabase.from('orders').insert({
                    user_id, deal_id, quantity, unit_price, total_amount,
                    status: 'unused', payment_intent_id,
                    purchased_merchant_id?   <-- brand deal 才会传
                  }).select('id').single()
```

### 2.2 create-payment-intent Edge Function

接收参数：`{ amount, currency, dealId, userId, promoCode? }`

当前逻辑极其简单，只做：
1. 创建 Stripe PaymentIntent（amount, currency, metadata: {deal_id, user_id}）
2. 返回 `{ clientSecret, paymentIntentId }`

**关键缺口**：
- 该函数不查询 `deal_applicable_stores`，也不记录任何门店快照。
- promoCode 参数被接收但 **没有实际验证逻辑**（当前版本完全忽略）。

### 2.3 orders 表插入

直接由客户端 Dart 代码调用 `supabase.from('orders').insert(...)` 写入，**不经过 Edge Function**。

`purchased_merchant_id` 仅在 brand deal（多门店）时才会出现在 insert payload 中，
普通单店 deal 不传该字段。

---

## 三、merchant-scan 核销逻辑

### 3.1 整体路由

| 路径 | 方法 | 功能 |
|------|------|------|
| `/merchant-scan/verify` | POST | 验证券码（只查询，不核销） |
| `/merchant-scan/redeem` | POST | 执行核销 |
| `/merchant-scan/revert` | POST | 撤销核销（10分钟内有效） |
| `/merchant-scan/history` | GET | 分页获取核销历史 |

### 3.2 checkStoreRedemptionEligibility() — 核心门店资格检查

```typescript
async function checkStoreRedemptionEligibility(
  supabase, dealId, couponCreatedAt, merchantId
): Promise<{ allowed: boolean; message?: string }>
```

**逻辑流程**：
1. 查 `deal_applicable_stores` 表，条件：`deal_id = dealId AND store_id = merchantId`
2. 没有记录 → `{ allowed: false, message: 'This voucher is not valid at this location.' }`
3. status = `'active'` → `{ allowed: true }`
4. status = `'removed'` → 比较 `coupon.created_at` 与 `storeRecord.removed_at`：
   - 购买时间 < removed_at（退出前已购买） → `{ allowed: true }`（该门店仍有责任核销）
   - 购买时间 >= removed_at（退出后购买） → `{ allowed: false }`，附带 active 门店名称提示
5. status = `'declined'` 或 `'pending_store_confirmation'` → `{ allowed: false }`

**关键缺口（与「门店快照」功能相关）**：

当前 `checkStoreRedemptionEligibility` 使用 `coupon.created_at` 作为购买时间与 `removed_at` 比较。
但 **`coupon.created_at` 是券被创建的时间，并非用户付款时 deal_applicable_stores 快照时的门店状态**。

如果在用户付款瞬间到券写入数据库之间有延迟，`coupon.created_at` 仍然可以近似代表购买时间。
然而，如果需要严格记录「购买时哪些门店在 active」，则需要在下单时做快照。

### 3.3 verify 的额外行为

verify 查询 coupons 时使用 `qr_code` 作为查找条件（而非 coupon_id），
但调用 `checkStoreRedemptionEligibility` 时传入 `coupon.created_at`（存在 bug：
实际上第二个参数变量名写的是 `coupon.created_at`，但该字段在 select 语句中 **没有被选中**，
导致实际传入 `undefined`，时间比较逻辑失效）。

```typescript
// verify 的 select：
.select(`id, qr_code, status, expires_at, redeemed_at, reverted_at, merchant_id, deal_id,
         deals!inner(title), users!coupons_user_id_fkey(full_name)`)
// ↑ 没有选 created_at！

// 但 handleVerify 调用：
checkStoreRedemptionEligibility(supabase, coupon.deal_id, coupon.created_at, merchantId)
// coupon.created_at 是 undefined → removed 门店的时间判断不起作用
```

redeem 的 select 也没有 `created_at`，同样的 bug。

---

## 四、deal_applicable_stores 表结构

来源：`deal_joy/supabase/migrations/20260312000001_deal_applicable_stores.sql`

```sql
CREATE TABLE public.deal_applicable_stores (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  deal_id              UUID NOT NULL REFERENCES public.deals(id) ON DELETE CASCADE,
  store_id             UUID NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  menu_item_id         UUID REFERENCES public.menu_items(id) ON DELETE SET NULL,
  deal_scope           deal_store_scope NOT NULL,     -- 'store_only' | 'brand_multi_store'
  status               deal_store_status NOT NULL DEFAULT 'pending_store_confirmation',
  -- 'active' | 'pending_store_confirmation' | 'declined' | 'removed'
  store_original_price NUMERIC(10,2),

  created_by           UUID REFERENCES auth.users(id),
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),

  confirmed_by         UUID REFERENCES auth.users(id),
  confirmed_at         TIMESTAMPTZ,

  removed_by           UUID REFERENCES auth.users(id),
  removed_at           TIMESTAMPTZ,

  UNIQUE (deal_id, store_id)
);
```

**RLS 策略**：
- 门店用户：SELECT / UPDATE 自己门店的记录
- 品牌管理员：SELECT 自己品牌下所有门店记录
- 用户端：SELECT `status = 'active'` 的记录（Deal 详情页展示）

**现有查询方式**（merchant-scan）：
```typescript
.from('deal_applicable_stores')
.select('status, removed_at')
.eq('deal_id', dealId)
.eq('store_id', merchantId)
.maybeSingle()
```

---

## 五、券详情页（coupon_screen.dart）— 可用门店展示

### 5.1 当前展示逻辑

`_MerchantInfoSection` 只展示单个商户信息（来自 `coupon.merchantName/Address/Phone`）。

多门店提示只显示数量，**不显示具体门店名称和地址**：
```dart
if (coupon.applicableMerchantIds != null &&
    coupon.applicableMerchantIds!.length > 1)
  // 显示 "Valid at N locations"（只有数字，没有列表）
```

### 5.2 数据来源

`CouponModel.applicableMerchantIds` 来自：
```dart
applicableMerchantIds: (deals?['applicable_merchant_ids'] as List?)
    ?.map((e) => e?.toString() ?? '')
    .where((s) => s.isNotEmpty)
    .toList(),
```

即读取 `deals.applicable_merchant_ids` 数组字段（旧字段，已被 `deal_applicable_stores` 表替代，
但两者并行存在）。

### 5.3 Repository 查询（_couponSelect）

```dart
const _couponSelect =
    'id, order_id, user_id, deal_id, merchant_id, qr_code, status, '
    'expires_at, used_at, created_at, gifted_from, verified_by, '
    'deals(id, title, description, image_urls, refund_policy, '
    'merchants(name, logo_url, address, phone))';
```

**关键缺口**：
- 没有 join `deal_applicable_stores` 表
- 没有查询「购买时有哪些门店」的快照信息
- `deals.applicable_merchant_ids` 是旧字段，可能已废弃

---

## 六、现有系统的核心 Gap（为门店快照功能做准备）

### Gap 1：orders 表没有「购买时门店列表快照」字段

当前 orders 表只有 `purchased_merchant_id`（brand deal 用户选择的主门店），
但没有记录「下单时哪些门店是 active 的」。

这意味着如果一个门店在用户购买后退出（removed），
现在的核销验证只能依靠时间比较（购买时间 vs removed_at），
没有直接的「白名单快照」。

### Gap 2：merchant-scan 的 verify/redeem 都没有在 select 中包含 `created_at`

`checkStoreRedemptionEligibility` 接收 `couponCreatedAt` 参数，
但 verify 和 redeem 的 coupons select 语句都 **没有选取 `created_at` 字段**，
导致该参数实际传入 `undefined`，时间比较逻辑形同虚设。

### Gap 3：coupon_screen.dart 仅展示购买时刻的单个商户，没有展示完整可用门店列表

`_MerchantInfoSection` 只展示 `coupon.merchantName` 和地址，
多门店只显示「Valid at N locations」数量，用户无法知道具体可在哪些门店使用。

### Gap 4：CouponsRepository 查询不包含 deal_applicable_stores

`_couponSelect` 没有关联 `deal_applicable_stores`，
无法在券详情页展示当时购买时快照的门店列表。

---

## 七、「购买时门店快照」功能实现所需的改动范围

根据以上分析，实现「购买时门店快照」功能需要：

1. **DB 层**：
   - 新增迁移：在 `coupons` 表（或 `orders` 表）添加 `snapshot_store_ids uuid[]` 字段，
     记录下单时所有 active 门店的 ID 列表

2. **后端创建订单逻辑**（CheckoutRepository._createOrder 或新 Edge Function）：
   - 下单时查询 `deal_applicable_stores` 获取当前 active 门店列表
   - 将快照写入 `coupons.snapshot_store_ids`

3. **merchant-scan**：
   - 修复 verify/redeem select 语句，补充 `created_at` 字段
   - 优化 `checkStoreRedemptionEligibility`：优先用快照列表判断，
     降级才用时间比较法

4. **客户端券详情页**：
   - `CouponsRepository._couponSelect` 补充快照门店 ID 列表
   - `CouponModel` 新增 `snapshotStoreIds` 字段
   - `coupon_screen.dart _MerchantInfoSection` 展示完整可用门店列表（名称+地址）

5. **可选优化**：
   - 在 checkout 前端选门店流程中展示实时 active 门店列表
