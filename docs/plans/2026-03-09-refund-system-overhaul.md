# Refund System Overhaul Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 将现有的即时扣款+直接退款模式，改造为预授权扣款 + 三级退款审批（用户→商家→管理员）的完整退款体系。

**Architecture:**
- 支付层：Stripe `capture_method: 'manual'`（≤7天有效期 coupon）或 `automatic`（>7天），核销时执行 capture
- 退款层：未核销前取消预授权（秒级），核销后24小时内发起申请经商家审批，商家拒绝后升级管理员仲裁
- 数据层：新增 `refund_requests` 表追踪整个审批链路；`orders` 新增 `is_captured` 和 `authorized` 状态

**Tech Stack:** Supabase Edge Functions (Deno/TypeScript), Flutter/Dart (Riverpod), Stripe API (capture/cancel/refund), PostgreSQL

---

## 订单状态机（全局参考）

```
购买 ≤7天deal  → [authorized]  --核销--> [used]  --24h内申请退款--> [refund_pending_merchant]
购买 >7天deal  → [unused]      --核销--> [used]       (同上)
[authorized]   --用户取消-->   [refunded]  (取消预授权，无资金流动)
[unused]       --用户取消-->   [refunded]  (Stripe refund，5-10天)
[refund_pending_merchant] --商家同意--> [refunded]
[refund_pending_merchant] --商家拒绝--> [refund_pending_admin]
[refund_pending_admin]    --管理员同意--> [refunded]
[refund_pending_admin]    --管理员拒绝--> [refund_rejected]
```

---

## Phase 1: 数据库基础层

### Task 1: 扩展 orders 表

**Files:**
- Create: `deal_joy/supabase/migrations/20260310000001_orders_preauth_support.sql`

**Step 1: 写 migration**

```sql
-- 新增 is_captured 字段（true = 已扣款，false = 预授权未扣款）
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS is_captured BOOLEAN NOT NULL DEFAULT true;

-- 已有订单全部视为已扣款（保持现有行为）
UPDATE public.orders SET is_captured = true WHERE is_captured IS NULL OR is_captured = true;

-- 更新订单状态注释（方便后续排查）
COMMENT ON COLUMN public.orders.status IS
  'authorized | unused | used | refunded | refund_pending_merchant | refund_pending_admin | refund_rejected | refund_failed | expired';
```

**Step 2: 本地验证**

```bash
/opt/homebrew/bin/supabase db push --project-ref kqyolvmgrdekybjrwizx
```
期望输出：migration applied successfully

**Step 3: Commit**

```bash
git add deal_joy/supabase/migrations/20260310000001_orders_preauth_support.sql
git commit -m "db: add is_captured column to orders for pre-auth support"
```

---

### Task 2: 创建 refund_requests 表

**Files:**
- Create: `deal_joy/supabase/migrations/20260310000002_refund_requests_table.sql`

**Step 1: 写 migration**

```sql
-- =============================================================
-- refund_requests 表：追踪核销后的退款申请审批链路
-- 状态流: pending_merchant → approved/rejected_merchant
--                          → pending_admin → approved/rejected_admin → completed
-- =============================================================

CREATE TABLE IF NOT EXISTS public.refund_requests (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id            UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  user_id             UUID NOT NULL REFERENCES public.users(id),
  merchant_id         UUID NOT NULL REFERENCES public.merchants(id),

  -- 退款金额（可以是部分退款）
  refund_amount       NUMERIC(10,2) NOT NULL,

  -- 涉及的单品快照（来自 orders.selected_options 或 deals.dishes 解析）
  -- 格式: [{"name": "Grilled Salmon", "qty": 1, "unit_price": 28.00, "refund_amount": 25.20}]
  refund_items        JSONB,

  -- 状态
  status              TEXT NOT NULL DEFAULT 'pending_merchant'
    CHECK (status IN (
      'pending_merchant',   -- 等待商家审批
      'approved_merchant',  -- 商家已同意（触发退款）
      'rejected_merchant',  -- 商家已拒绝（升级至管理员）
      'pending_admin',      -- 等待管理员仲裁
      'approved_admin',     -- 管理员已同意（触发退款）
      'rejected_admin',     -- 管理员最终拒绝
      'completed',          -- 退款已完成
      'cancelled'           -- 用户主动撤回
    )),

  -- 用户填写的退款理由（必填）
  user_reason         TEXT NOT NULL,

  -- 商家决定
  merchant_decision   TEXT CHECK (merchant_decision IN ('approved', 'rejected')),
  merchant_reason     TEXT,            -- 拒绝时必填
  merchant_decided_at TIMESTAMPTZ,
  merchant_decided_by UUID REFERENCES public.users(id),

  -- 管理员决定
  admin_decision      TEXT CHECK (admin_decision IN ('approved', 'rejected')),
  admin_reason        TEXT,
  admin_decided_at    TIMESTAMPTZ,
  admin_decided_by    UUID REFERENCES public.users(id),

  -- 退款完成时间
  completed_at        TIMESTAMPTZ,

  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 索引
CREATE INDEX idx_refund_requests_order_id     ON public.refund_requests(order_id);
CREATE INDEX idx_refund_requests_merchant_id  ON public.refund_requests(merchant_id);
CREATE INDEX idx_refund_requests_user_id      ON public.refund_requests(user_id);
CREATE INDEX idx_refund_requests_status       ON public.refund_requests(status);

-- RLS
ALTER TABLE public.refund_requests ENABLE ROW LEVEL SECURITY;

-- 用户只能看自己的退款申请
CREATE POLICY "refund_requests_user_select" ON public.refund_requests
  FOR SELECT USING (auth.uid() = user_id);

-- 用户只能插入自己的退款申请
CREATE POLICY "refund_requests_user_insert" ON public.refund_requests
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- 商家可以查看自己商户的退款申请（通过 merchant_staff）
CREATE POLICY "refund_requests_merchant_select" ON public.refund_requests
  FOR SELECT USING (
    merchant_id IN (
      SELECT ms.merchant_id FROM public.merchant_staff ms WHERE ms.user_id = auth.uid()
    )
  );
```

**Step 2: 推送 migration**

```bash
/opt/homebrew/bin/supabase db push --project-ref kqyolvmgrdekybjrwizx
```

**Step 3: Commit**

```bash
git add deal_joy/supabase/migrations/20260310000002_refund_requests_table.sql
git commit -m "db: create refund_requests table with full approval workflow"
```

---

### Task 3: 商家调整记录表（替代"余额负数"方案）

> **架构说明：** 系统无持久化余额表，收益从 `orders` 实时计算，结算写入 `settlements`。
> 商家"欠款"通过 `merchant_adjustments` 表记录负向调整，earnings RPC 汇总时扣除。

**Files:**
- Create: `deal_joy/supabase/migrations/20260310000003_merchant_adjustments.sql`

**Step 1: 写 migration**

```sql
-- merchant_adjustments：记录超出已结算金额的退款扣除（即欠款）
CREATE TABLE IF NOT EXISTS public.merchant_adjustments (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id     UUID NOT NULL REFERENCES public.merchants(id) ON DELETE CASCADE,
  amount          NUMERIC(10,2) NOT NULL, -- 负数 = 欠款扣除，正数 = 欠款偿还
  reason          TEXT NOT NULL,          -- 说明，如 "Refund deduction: order DJ-XXXXXXXX"
  refund_request_id UUID REFERENCES public.refund_requests(id),
  created_by      UUID REFERENCES auth.users(id), -- 管理员操作人
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_merchant_adjustments_merchant_id ON public.merchant_adjustments(merchant_id);

ALTER TABLE public.merchant_adjustments ENABLE ROW LEVEL SECURITY;

-- 商家只能查看（不能自己创建）
CREATE POLICY "merchant_adjustments_select" ON public.merchant_adjustments
  FOR SELECT USING (
    merchant_id IN (SELECT id FROM public.merchants WHERE user_id = auth.uid())
  );

-- 只有 service_role 可以写入
CREATE POLICY "merchant_adjustments_service_all" ON public.merchant_adjustments
  FOR ALL USING (auth.role() = 'service_role');
```

**Step 2: 部署**

```bash
/opt/homebrew/bin/supabase db push --project-ref kqyolvmgrdekybjrwizx
```

**Step 3: Commit**

```bash
git add deal_joy/supabase/migrations/20260310000003_merchant_adjustments.sql
git commit -m "db: add merchant_adjustments table for debt tracking"
```

---

## Phase 2: 支付预授权层

### Task 4: 改造 create-payment-intent（支持预授权）

**Files:**
- Modify: `deal_joy/supabase/functions/create-payment-intent/index.ts`

**背景：**
当前代码在 `stripe.paymentIntents.create()` 时使用默认的 `capture_method: 'automatic'`（立即扣款）。
需要根据 deal 有效期决定：
- deal `expires_at` ≤ 当前时间 + 7天 → `capture_method: 'manual'`（预授权）
- deal `expires_at` > 当前时间 + 7天 → `capture_method: 'automatic'`（即时扣款）

**Step 1: 修改 Edge Function**

将 `create-payment-intent/index.ts` 完整替换为：

```typescript
import Stripe from 'https://esm.sh/stripe@14?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2?target=deno';

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
  apiVersion: '2024-04-10',
  httpClient: Stripe.createFetchHttpClient(),
});

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// 预授权有效期阈值（Stripe 最长 7 天）
const PREAUTH_THRESHOLD_DAYS = 7;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const { amount, currency = 'usd', dealId, userId } = await req.json();

    if (!amount || amount <= 0) {
      return new Response(
        JSON.stringify({ error: 'Invalid amount' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // 查询 deal 的 expires_at，决定扣款模式
    let captureMethod: 'automatic' | 'manual' = 'automatic';
    if (dealId) {
      const supabase = createClient(
        Deno.env.get('SUPABASE_URL') ?? '',
        Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      );
      const { data: deal } = await supabase
        .from('deals')
        .select('expires_at')
        .eq('id', dealId)
        .maybeSingle();

      if (deal?.expires_at) {
        const expiresAt = new Date(deal.expires_at);
        const thresholdDate = new Date();
        thresholdDate.setDate(thresholdDate.getDate() + PREAUTH_THRESHOLD_DAYS);
        // 有效期在 7 天内 → 预授权
        if (expiresAt <= thresholdDate) {
          captureMethod = 'manual';
        }
      }
    }

    const paymentIntent = await stripe.paymentIntents.create({
      amount: Math.round(amount * 100),
      currency,
      capture_method: captureMethod,
      automatic_payment_methods: { enabled: true },
      metadata: {
        deal_id: dealId ?? '',
        user_id: userId ?? '',
        capture_method: captureMethod,
      },
    });

    return new Response(
      JSON.stringify({
        clientSecret: paymentIntent.client_secret,
        paymentIntentId: paymentIntent.id,
        captureMethod,  // 告知客户端是预授权还是即时扣款，用于 UI 提示
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  } catch (err) {
    console.error('create-payment-intent error:', err);
    return new Response(
      JSON.stringify({ error: err instanceof Error ? err.message : 'Unknown error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  }
});
```

**Step 2: 部署**

```bash
/opt/homebrew/bin/supabase functions deploy create-payment-intent --no-verify-jwt --project-ref kqyolvmgrdekybjrwizx
```

**Step 3: Commit**

```bash
git add deal_joy/supabase/functions/create-payment-intent/index.ts
git commit -m "feat: support manual capture for deals with ≤7 day validity"
```

---

### Task 5: 创建 capture-payment Edge Function

**Files:**
- Create: `deal_joy/supabase/functions/capture-payment/index.ts`

**背景：** 当商家扫码核销 coupon 时，如果该笔支付是预授权（`is_captured = false`），则需要调用 Stripe capture API 完成扣款，同时更新商家余额。

**Step 1: 创建 Edge Function**

```typescript
// Edge Function: capture-payment
// 在 coupon 核销时执行 Stripe payment capture（仅预授权订单需要调用）
// 由 merchant-scan/redeem 在核销成功后内部调用

import Stripe from 'https://esm.sh/stripe@14?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2?target=deno';

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
  apiVersion: '2024-04-10',
  httpClient: Stripe.createFetchHttpClient(),
});

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// 平台抽成比例（10%，后续可改为从 DB 读取）
const PLATFORM_FEE_RATIO = 0.10;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const { orderId } = await req.json();
    if (!orderId) {
      return new Response(
        JSON.stringify({ error: 'orderId is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    );

    // 查询订单
    const { data: order, error: orderErr } = await supabase
      .from('orders')
      .select('id, payment_intent_id, total_amount, is_captured, status, deal_id')
      .eq('id', orderId)
      .single();

    if (orderErr || !order) {
      return new Response(
        JSON.stringify({ error: 'Order not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // 已扣款则跳过（幂等）
    if (order.is_captured) {
      console.log(`[capture-payment] order=${orderId} already captured, skip`);
      return new Response(
        JSON.stringify({ captured: false, reason: 'already_captured' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // 调用 Stripe capture
    const capturedIntent = await stripe.paymentIntents.capture(order.payment_intent_id);
    const chargeId = typeof capturedIntent.latest_charge === 'string'
      ? capturedIntent.latest_charge
      : capturedIntent.latest_charge?.id ?? null;

    const now = new Date().toISOString();

    // 更新订单 is_captured = true
    await supabase
      .from('orders')
      .update({ is_captured: true, stripe_charge_id: chargeId, updated_at: now })
      .eq('id', orderId);

    // 插入 payments 记录（已扣款）
    await supabase.from('payments').insert({
      order_id: order.id,
      amount: order.total_amount,
      currency: 'usd',
      payment_intent_id: order.payment_intent_id,
      stripe_charge_id: chargeId,
      status: 'succeeded',
    }).onConflict('payment_intent_id').ignore();

    // 查询 deal 所属 merchant_id，更新商家余额
    const { data: deal } = await supabase
      .from('deals')
      .select('merchant_id')
      .eq('id', order.deal_id)
      .maybeSingle();

    if (deal?.merchant_id) {
      const merchantAmount = Number(order.total_amount) * (1 - PLATFORM_FEE_RATIO);
      // 累加商家余额（使用 RPC 保证原子性）
      await supabase.rpc('increment_merchant_balance', {
        p_merchant_id: deal.merchant_id,
        p_amount: merchantAmount,
      });
    }

    console.log(`[capture-payment] captured order=${orderId} pi=${order.payment_intent_id}`);

    return new Response(
      JSON.stringify({ captured: true, chargeId }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  } catch (err) {
    console.error('capture-payment error:', err);
    return new Response(
      JSON.stringify({ error: err instanceof Error ? err.message : 'Unknown error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  }
});
```

**Step 2: 同时创建 `increment_merchant_balance` RPC（数据库原子操作）**

新建 migration `20260310000004_merchant_balance_rpc.sql`：

```sql
-- 原子增加商家余额（支持负数，即欠款）
CREATE OR REPLACE FUNCTION public.increment_merchant_balance(
  p_merchant_id UUID,
  p_amount      NUMERIC
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- 使用 INSERT ... ON CONFLICT DO UPDATE 保证幂等
  INSERT INTO public.merchant_earnings (merchant_id, available_balance, total_earned, updated_at)
  VALUES (p_merchant_id, p_amount, GREATEST(p_amount, 0), now())
  ON CONFLICT (merchant_id) DO UPDATE
    SET available_balance = merchant_earnings.available_balance + EXCLUDED.available_balance,
        total_earned      = merchant_earnings.total_earned + GREATEST(p_amount, 0),
        updated_at        = now();
END;
$$;
```

> **注意：** `merchant_earnings` 表的实际列名需根据 Task 3 Step 1 的查询结果调整。

**Step 3: 部署**

```bash
/opt/homebrew/bin/supabase functions deploy capture-payment --no-verify-jwt --project-ref kqyolvmgrdekybjrwizx
/opt/homebrew/bin/supabase db push --project-ref kqyolvmgrdekybjrwizx
```

**Step 4: Commit**

```bash
git add deal_joy/supabase/functions/capture-payment/index.ts
git add deal_joy/supabase/migrations/20260310000004_merchant_balance_rpc.sql
git commit -m "feat: create capture-payment function and merchant balance RPC"
```

---

### Task 6: 改造 merchant-scan/redeem（核销时触发 capture）

**Files:**
- Modify: `deal_joy/supabase/functions/merchant-scan/index.ts`

**Step 1: 找到 redeem 处理函数的位置**

在 `merchant-scan/index.ts` 中搜索 `handleRedeem` 或 `redeem` 路由部分。

**Step 2: 在核销成功后，内部调用 capture-payment**

在 `handleRedeem` 函数中，核销成功更新 DB 之后，添加以下代码：

```typescript
// 核销成功后，如果是预授权订单，触发扣款
if (!order.is_captured) {
  const captureUrl = `${Deno.env.get('SUPABASE_URL')}/functions/v1/capture-payment`;
  await fetch(captureUrl, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`,
    },
    body: JSON.stringify({ orderId: order.id }),
  }).catch((e) => {
    // capture 失败不应中断核销流程，记录日志待人工处理
    console.error('[merchant-scan/redeem] capture-payment failed:', e);
  });
}
```

> **注意：** 需要先从 orders 表查询 `is_captured` 字段（在已有的 order 查询 SELECT 里加上 `is_captured`）。

**Step 3: 部署**

```bash
/opt/homebrew/bin/supabase functions deploy merchant-scan --no-verify-jwt --project-ref kqyolvmgrdekybjrwizx
```

**Step 4: Commit**

```bash
git add deal_joy/supabase/functions/merchant-scan/index.ts
git commit -m "feat: trigger payment capture on coupon redemption"
```

---

### Task 7: 改造 create-refund（区分取消预授权 vs Stripe 退款）

**Files:**
- Modify: `deal_joy/supabase/functions/create-refund/index.ts`

**背景：**
- 未核销订单（`is_captured = false`）→ 取消预授权：`stripe.paymentIntents.cancel()`（秒级）
- 未核销订单（`is_captured = true`，即时扣款 deal）→ Stripe 退款：`stripe.refunds.create()`（5-10天）
- 已核销订单 → 不走此接口，走 `submit-refund-request`

在现有的 `create-refund/index.ts` 中，找到 Stripe 退款部分，修改为：

```typescript
// 判断是取消预授权还是发起退款
let refundOrCancelResult: { id: string; status: string };

if (!order.is_captured) {
  // 预授权未扣款 → 取消授权（秒级，无资金流动）
  const cancelled = await stripe.paymentIntents.cancel(order.payment_intent_id);
  refundOrCancelResult = { id: cancelled.id, status: cancelled.status };
} else {
  // 已扣款 → 标准退款（5-10个工作日）
  const refund = await stripe.refunds.create({
    payment_intent: order.payment_intent_id,
    reason: 'requested_by_customer',
  });
  refundOrCancelResult = { id: refund.id, status: refund.status };
}
```

同时，在查询 order 时加上 `is_captured` 字段：
```typescript
.select('payment_intent_id, total_amount, status, refund_requested_at, is_captured')
```

**Step 2: 部署**

```bash
/opt/homebrew/bin/supabase functions deploy create-refund --no-verify-jwt --project-ref kqyolvmgrdekybjrwizx
```

**Step 3: Commit**

```bash
git add deal_joy/supabase/functions/create-refund/index.ts
git commit -m "feat: cancel pre-auth instead of refund for uncaptured orders"
```

---

### Task 8: 更新 stripe-webhook（处理预授权相关事件）

**Files:**
- Modify: `deal_joy/supabase/functions/stripe-webhook/index.ts`

**Step 1: 添加 `payment_intent.amount_capturable_updated` 事件处理**

在 `stripe-webhook/index.ts` 的 switch 中新增：

```typescript
case 'payment_intent.amount_capturable_updated':
  // 预授权成功：更新订单状态为 authorized，is_captured = false
  await handleAmountCapturableUpdated(event.data.object as Stripe.PaymentIntent);
  break;

case 'payment_intent.canceled':
  // 预授权取消（未核销退款）：更新订单为 refunded
  await handlePaymentIntentCanceled(event.data.object as Stripe.PaymentIntent);
  break;
```

新增处理函数：

```typescript
async function handleAmountCapturableUpdated(pi: Stripe.PaymentIntent): Promise<void> {
  const { data: order } = await supabase
    .from('orders')
    .select('id, status')
    .eq('payment_intent_id', pi.id)
    .maybeSingle();

  if (!order) {
    console.warn(`[amount_capturable_updated] 未找到订单 pi=${pi.id}`);
    return;
  }

  await supabase
    .from('orders')
    .update({ status: 'authorized', is_captured: false, updated_at: new Date().toISOString() })
    .eq('id', order.id);

  // 同时更新 coupons 状态为 active（可用）
  await supabase
    .from('coupons')
    .update({ status: 'active' })
    .eq('order_id', order.id);

  console.log(`[amount_capturable_updated] order=${order.id} marked as authorized`);
}

async function handlePaymentIntentCanceled(pi: Stripe.PaymentIntent): Promise<void> {
  const { data: order } = await supabase
    .from('orders')
    .select('id')
    .eq('payment_intent_id', pi.id)
    .maybeSingle();

  if (!order) return;

  const now = new Date().toISOString();
  await supabase
    .from('orders')
    .update({ status: 'refunded', refunded_at: now, updated_at: now })
    .eq('id', order.id);

  await supabase
    .from('coupons')
    .update({ status: 'refunded' })
    .eq('order_id', order.id);

  console.log(`[payment_intent.canceled] order=${order.id} refunded via cancel`);
}
```

**Step 2: 部署**

```bash
/opt/homebrew/bin/supabase functions deploy stripe-webhook --no-verify-jwt --project-ref kqyolvmgrdekybjrwizx
```

> **同时在 Stripe Dashboard → Webhooks 中添加新的监听事件：**
> - `payment_intent.amount_capturable_updated`
> - `payment_intent.canceled`

**Step 3: Commit**

```bash
git add deal_joy/supabase/functions/stripe-webhook/index.ts
git commit -m "feat: handle pre-auth webhook events (capturable_updated, canceled)"
```

---

## Phase 3: 退款申请审批链路

### Task 9: 创建 submit-refund-request Edge Function

**Files:**
- Create: `deal_joy/supabase/functions/submit-refund-request/index.ts`

**背景：** 用户在 coupon 核销后 24 小时内，在用户端发起退款申请时调用。此时订单状态为 `used`。

**Step 1: 创建 Edge Function**

```typescript
// Edge Function: submit-refund-request
// 用户提交核销后退款申请（仅限核销后 24 小时内）
// 创建 refund_requests 记录，更新订单状态为 refund_pending_merchant

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2?target=deno';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

// 核销后退款窗口期（24 小时）
const REFUND_WINDOW_HOURS = 24;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return jsonResponse({ error: 'Unauthorized' }, 401);

  try {
    const { orderId, reason, refundItems } = await req.json();

    if (!orderId || !reason?.trim()) {
      return jsonResponse({ error: 'orderId and reason are required' }, 400);
    }
    if (reason.trim().length < 10) {
      return jsonResponse({ error: 'Reason must be at least 10 characters' }, 400);
    }

    // 用用户 JWT 客户端验证身份
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: authHeader } } },
    );

    const { data: { user }, error: authErr } = await supabase.auth.getUser();
    if (authErr || !user) return jsonResponse({ error: 'Unauthorized' }, 401);

    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    );

    // 查询订单
    const { data: order } = await supabaseAdmin
      .from('orders')
      .select(`
        id, user_id, status, total_amount, deal_id,
        coupons!coupons_order_id_fkey ( redeemed_at )
      `)
      .eq('id', orderId)
      .eq('user_id', user.id)
      .single();

    if (!order) return jsonResponse({ error: 'Order not found' }, 404);

    if (order.status !== 'used') {
      return jsonResponse({
        error: order.status === 'refund_pending_merchant' || order.status === 'refund_pending_admin'
          ? 'Refund request already submitted'
          : `Cannot request refund for order with status: ${order.status}`,
      }, 400);
    }

    // 检查 24 小时窗口
    const coupon = Array.isArray(order.coupons) ? order.coupons[0] : order.coupons;
    const redeemedAt = coupon?.redeemed_at ? new Date(coupon.redeemed_at) : null;
    if (!redeemedAt) {
      return jsonResponse({ error: 'Cannot find redemption time' }, 400);
    }
    const hoursSinceRedeem = (Date.now() - redeemedAt.getTime()) / 3600000;
    if (hoursSinceRedeem > REFUND_WINDOW_HOURS) {
      return jsonResponse({ error: 'Refund window has expired (24 hours after redemption)' }, 400);
    }

    // 查询 deal 的 merchant_id
    const { data: deal } = await supabaseAdmin
      .from('deals')
      .select('merchant_id')
      .eq('id', order.deal_id)
      .single();

    if (!deal) return jsonResponse({ error: 'Deal not found' }, 404);

    // 计算退款金额
    // refundItems 格式: [{ name, qty, unit_price, refund_amount }]
    // 如果没有传 refundItems（全额退款），则 refund_amount = total_amount
    let refundAmount = Number(order.total_amount);
    if (refundItems && Array.isArray(refundItems) && refundItems.length > 0) {
      refundAmount = refundItems.reduce((sum: number, item: { refund_amount: number }) =>
        sum + Number(item.refund_amount), 0);
      // 安全校验：不能超过实付金额
      if (refundAmount > Number(order.total_amount)) {
        return jsonResponse({ error: 'Refund amount exceeds paid amount' }, 400);
      }
    }

    const now = new Date().toISOString();

    // 创建退款申请
    const { data: refundRequest, error: insertErr } = await supabaseAdmin
      .from('refund_requests')
      .insert({
        order_id: orderId,
        user_id: user.id,
        merchant_id: deal.merchant_id,
        refund_amount: refundAmount,
        refund_items: refundItems ?? null,
        status: 'pending_merchant',
        user_reason: reason.trim(),
      })
      .select('id')
      .single();

    if (insertErr) {
      console.error('insert refund_request failed:', insertErr);
      return jsonResponse({ error: 'Failed to submit refund request' }, 500);
    }

    // 更新订单状态
    await supabaseAdmin
      .from('orders')
      .update({ status: 'refund_pending_merchant', updated_at: now })
      .eq('id', orderId);

    // 冻结商家对应余额（防止在退款审批期间被提现）
    await supabaseAdmin.rpc('freeze_merchant_balance', {
      p_merchant_id: deal.merchant_id,
      p_amount: refundAmount,
    }).maybeSingle();

    return jsonResponse({ refundRequestId: refundRequest.id }, 201);
  } catch (err) {
    console.error('submit-refund-request error:', err);
    return jsonResponse({ error: err instanceof Error ? err.message : 'Unknown error' }, 500);
  }
});
```

**Step 2: 新增 `freeze_merchant_balance` RPC**

在 migration `20260310000004_merchant_balance_rpc.sql` 追加（或新建 migration）：

```sql
-- 冻结商家余额（退款审批期间不可提现）
CREATE OR REPLACE FUNCTION public.freeze_merchant_balance(
  p_merchant_id UUID,
  p_amount      NUMERIC
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE public.merchant_earnings
  SET frozen_amount = frozen_amount + p_amount,
      updated_at    = now()
  WHERE merchant_id = p_merchant_id;
END;
$$;

-- 解冻商家余额（退款完成或拒绝后调用）
CREATE OR REPLACE FUNCTION public.unfreeze_merchant_balance(
  p_merchant_id UUID,
  p_amount      NUMERIC
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE public.merchant_earnings
  SET frozen_amount = GREATEST(0, frozen_amount - p_amount),
      updated_at    = now()
  WHERE merchant_id = p_merchant_id;
END;
$$;

-- 从商家余额扣除退款（余额可降至负数，即欠款）
CREATE OR REPLACE FUNCTION public.deduct_merchant_balance(
  p_merchant_id UUID,
  p_amount      NUMERIC
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE public.merchant_earnings
  SET available_balance = available_balance - p_amount,
      frozen_amount     = GREATEST(0, frozen_amount - p_amount),
      updated_at        = now()
  WHERE merchant_id = p_merchant_id;
END;
$$;
```

**Step 3: 部署**

```bash
/opt/homebrew/bin/supabase functions deploy submit-refund-request --no-verify-jwt --project-ref kqyolvmgrdekybjrwizx
/opt/homebrew/bin/supabase db push --project-ref kqyolvmgrdekybjrwizx
```

**Step 4: Commit**

```bash
git add deal_joy/supabase/functions/submit-refund-request/index.ts
git commit -m "feat: submit-refund-request edge function with 24h window validation"
```

---

### Task 10: 扩展 merchant-orders（商家退款审批端点）

**Files:**
- Modify: `deal_joy/supabase/functions/merchant-orders/index.ts`

**Step 1: 在路由分发中新增退款相关路由**

在 `merchant-orders/index.ts` 的路由分发部分添加：

```typescript
// 退款申请列表：GET /merchant-orders/refund-requests
if (subPath === 'refund-requests' && req.method === 'GET') {
  return await handleRefundRequestsList(serviceClient, merchantId, url.searchParams);
}

// 退款申请处理：PATCH /merchant-orders/refund-requests/:id
if (subPath === 'refund-requests' && pathParts[1] && req.method === 'PATCH') {
  return await handleRefundRequestDecision(req, serviceClient, merchantId, pathParts[1]);
}
```

**Step 2: 实现 handleRefundRequestsList**

```typescript
async function handleRefundRequestsList(
  client: ReturnType<typeof createClient>,
  merchantId: string,
  params: URLSearchParams,
): Promise<Response> {
  const status = params.get('status') ?? null;
  const page = Math.max(parseInt(params.get('page') ?? '1', 10), 1);
  const perPage = Math.min(parseInt(params.get('per_page') ?? '20', 10), 100);
  const offset = (page - 1) * perPage;

  let query = client
    .from('refund_requests')
    .select(`
      id, order_id, refund_amount, refund_items, status, user_reason,
      created_at, updated_at,
      orders!inner ( order_number, total_amount, created_at,
        deals!inner ( title )
      )
    `, { count: 'exact' })
    .eq('merchant_id', merchantId)
    .order('created_at', { ascending: false })
    .range(offset, offset + perPage - 1);

  if (status) query = query.eq('status', status);

  const { data, error, count } = await query;
  if (error) return errorResponse(error.message, 'db_error', 500);

  return jsonResponse({ data: data ?? [], total: count ?? 0, page, per_page: perPage });
}
```

**Step 3: 实现 handleRefundRequestDecision**

```typescript
async function handleRefundRequestDecision(
  req: Request,
  client: ReturnType<typeof createClient>,
  merchantId: string,
  refundRequestId: string,
): Promise<Response> {
  const body = await req.json().catch(() => ({}));
  const { action, reason } = body; // action: 'approve' | 'reject'

  if (!['approve', 'reject'].includes(action)) {
    return errorResponse('action must be approve or reject', 'validation_error');
  }
  if (action === 'reject' && !reason?.trim()) {
    return errorResponse('reason is required when rejecting', 'validation_error');
  }

  // 查询退款申请（校验归属）
  const { data: rr } = await client
    .from('refund_requests')
    .select('id, order_id, status, refund_amount, merchant_id')
    .eq('id', refundRequestId)
    .eq('merchant_id', merchantId)
    .eq('status', 'pending_merchant')
    .single();

  if (!rr) return errorResponse('Refund request not found or already processed', 'not_found', 404);

  const now = new Date().toISOString();

  if (action === 'approve') {
    // 商家同意 → 触发 Stripe 退款
    const captureUrl = `${Deno.env.get('SUPABASE_URL')}/functions/v1/execute-refund`;
    const refundRes = await fetch(captureUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`,
      },
      body: JSON.stringify({ orderId: rr.order_id, refundAmount: rr.refund_amount, refundRequestId: rr.id }),
    });

    if (!refundRes.ok) {
      return errorResponse('Failed to process refund', 'refund_error', 502);
    }

    await client.from('refund_requests').update({
      status: 'approved_merchant',
      merchant_decision: 'approved',
      merchant_decided_at: now,
    }).eq('id', refundRequestId);

  } else {
    // 商家拒绝 → 升级至管理员
    await client.from('refund_requests').update({
      status: 'pending_admin',
      merchant_decision: 'rejected',
      merchant_reason: reason.trim(),
      merchant_decided_at: now,
    }).eq('id', refundRequestId);

    await client.from('orders').update({
      status: 'refund_pending_admin',
      updated_at: now,
    }).eq('id', rr.order_id);
  }

  return jsonResponse({ success: true });
}
```

**Step 4: 部署**

```bash
/opt/homebrew/bin/supabase functions deploy merchant-orders --no-verify-jwt --project-ref kqyolvmgrdekybjrwizx
```

**Step 5: Commit**

```bash
git add deal_joy/supabase/functions/merchant-orders/index.ts
git commit -m "feat: merchant refund request list and approve/reject endpoints"
```

---

### Task 11: 创建 execute-refund + admin-refund Edge Functions

**Files:**
- Create: `deal_joy/supabase/functions/execute-refund/index.ts`
- Create: `deal_joy/supabase/functions/admin-refund/index.ts`

**Step 1: execute-refund（通用退款执行器，内部调用）**

```typescript
// execute-refund: 执行实际的 Stripe 退款 + 更新 DB
// 内部服务间调用，不对外暴露

import Stripe from 'https://esm.sh/stripe@14?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2?target=deno';

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
  apiVersion: '2024-04-10',
  httpClient: Stripe.createFetchHttpClient(),
});

const corsHeaders = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type' };

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  const { orderId, refundAmount, refundRequestId } = await req.json();
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  );

  const { data: order } = await supabase
    .from('orders')
    .select('payment_intent_id, total_amount, deal_id')
    .eq('id', orderId)
    .single();

  if (!order) return new Response(JSON.stringify({ error: 'Order not found' }), { status: 404 });

  const now = new Date().toISOString();
  const amountToRefund = refundAmount ?? Number(order.total_amount);

  try {
    // 执行 Stripe 退款
    await stripe.refunds.create({
      payment_intent: order.payment_intent_id,
      amount: Math.round(amountToRefund * 100),
      reason: 'requested_by_customer',
    });

    // 更新订单状态
    await supabase.from('orders').update({
      status: 'refunded',
      refunded_at: now,
      updated_at: now,
    }).eq('id', orderId);

    // 更新退款申请状态
    if (refundRequestId) {
      await supabase.from('refund_requests').update({
        status: 'completed',
        completed_at: now,
        updated_at: now,
      }).eq('id', refundRequestId);
    }

    // 从商家余额扣除退款金额（可能变负数）
    const { data: deal } = await supabase.from('deals').select('merchant_id').eq('id', order.deal_id).maybeSingle();
    if (deal?.merchant_id) {
      const platformFee = amountToRefund * 0.10; // 平台退还手续费
      const merchantDeduction = amountToRefund - platformFee;
      await supabase.rpc('deduct_merchant_balance', {
        p_merchant_id: deal.merchant_id,
        p_amount: merchantDeduction,
      });
    }

    return new Response(JSON.stringify({ success: true }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  } catch (err) {
    console.error('execute-refund error:', err);
    return new Response(JSON.stringify({ error: err instanceof Error ? err.message : 'Unknown' }), { status: 502 });
  }
});
```

**Step 2: admin-refund（管理员仲裁接口）**

```typescript
// admin-refund: 管理员最终仲裁退款申请
// POST /admin-refund  body: { refundRequestId, action: 'approve'|'reject', reason? }

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2?target=deno';

const corsHeaders = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type' };

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return new Response(JSON.stringify({ error: 'Unauthorized' }), { status: 401 });

  const { refundRequestId, action, reason } = await req.json();
  if (!['approve', 'reject'].includes(action)) {
    return new Response(JSON.stringify({ error: 'Invalid action' }), { status: 400 });
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  );

  // TODO: 验证管理员身份（检查 admin_users 表）
  const userClient = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_ANON_KEY') ?? '',
    { global: { headers: { Authorization: authHeader } } },
  );
  const { data: { user } } = await userClient.auth.getUser();
  if (!user) return new Response(JSON.stringify({ error: 'Unauthorized' }), { status: 401 });

  const { data: rr } = await supabase
    .from('refund_requests')
    .select('id, order_id, refund_amount, status, merchant_id')
    .eq('id', refundRequestId)
    .eq('status', 'pending_admin')
    .single();

  if (!rr) return new Response(JSON.stringify({ error: 'Not found' }), { status: 404 });

  const now = new Date().toISOString();

  if (action === 'approve') {
    // 调用 execute-refund
    await fetch(`${Deno.env.get('SUPABASE_URL')}/functions/v1/execute-refund`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}` },
      body: JSON.stringify({ orderId: rr.order_id, refundAmount: rr.refund_amount, refundRequestId: rr.id }),
    });

    await supabase.from('refund_requests').update({
      status: 'approved_admin',
      admin_decision: 'approved',
      admin_decided_at: now,
      admin_decided_by: user.id,
    }).eq('id', refundRequestId);

  } else {
    // 管理员拒绝 → 最终拒绝，解冻商家余额
    await supabase.from('refund_requests').update({
      status: 'rejected_admin',
      admin_decision: 'rejected',
      admin_reason: reason ?? '',
      admin_decided_at: now,
      admin_decided_by: user.id,
    }).eq('id', refundRequestId);

    await supabase.from('orders').update({
      status: 'refund_rejected',
      updated_at: now,
    }).eq('id', rr.order_id);

    // 解冻商家余额
    await supabase.rpc('unfreeze_merchant_balance', {
      p_merchant_id: rr.merchant_id,
      p_amount: rr.refund_amount,
    });
  }

  return new Response(JSON.stringify({ success: true }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
});
```

**Step 3: 部署**

```bash
/opt/homebrew/bin/supabase functions deploy execute-refund --no-verify-jwt --project-ref kqyolvmgrdekybjrwizx
/opt/homebrew/bin/supabase functions deploy admin-refund --no-verify-jwt --project-ref kqyolvmgrdekybjrwizx
```

**Step 4: Commit**

```bash
git add deal_joy/supabase/functions/execute-refund/index.ts
git add deal_joy/supabase/functions/admin-refund/index.ts
git commit -m "feat: execute-refund and admin-refund arbitration edge functions"
```

---

## Phase 4: 用户端（deal_joy Flutter）

### Task 12: 更新 OrderModel（新状态支持）

**Files:**
- Modify: `deal_joy/lib/features/orders/data/models/order_model.dart`

**Step 1: 添加新状态和 canRequestRefund 逻辑**

在 `order_model.dart` 中修改：

```dart
// 在 status 注释中添加新状态
final String status; // authorized | unused | used | refunded
                     // refund_pending_merchant | refund_pending_admin
                     // refund_rejected | refund_failed | expired

// 在 fromJson 中添加 is_captured 字段（可选，用于 UI 提示）
final bool isCaptured;

// 新增 getter
bool get isAuthorized => status == 'authorized';
bool get isRefundPendingMerchant => status == 'refund_pending_merchant';
bool get isRefundPendingAdmin => status == 'refund_pending_admin';
bool get isRefundRejectedFinal => status == 'refund_rejected';

/// 未核销订单可直接退款（无需审批）
/// is_captured=false → 取消预授权（秒级）
/// is_captured=true → Stripe 退款（5-10天）
bool get canRefund => isUnused || isAuthorized;

/// 核销后 24 小时内可发起退款申请（需要商家审批）
bool get canRequestPostUseRefund {
  if (status != 'used') return false;
  // couponRedeemedAt 需要从 coupon 数据传入，此处用 createdAt fallback
  // 实际在 UI 层结合 coupon.redeemed_at 判断
  return true;
}
```

**Step 2: 更新 fromJson，加入 `is_captured`**

```dart
isCaptured: json['is_captured'] as bool? ?? true,
```

**Step 3: Commit**

```bash
git add deal_joy/lib/features/orders/data/models/order_model.dart
git commit -m "feat: add new order statuses and canRequestPostUseRefund logic"
```

---

### Task 13: 添加核销后退款申请 UI

**Files:**
- Create: `deal_joy/lib/features/orders/presentation/screens/post_use_refund_screen.dart`
- Modify: `deal_joy/lib/features/orders/presentation/screens/order_detail_screen.dart`
- Modify: `deal_joy/lib/features/orders/presentation/screens/coupon_screen.dart`
- Modify: `deal_joy/lib/features/orders/data/repositories/orders_repository.dart`

**Step 1: 新建 post_use_refund_screen.dart**

```dart
// 核销后退款申请页面
// 用户填写退款理由，可选择部分退款项目

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../orders/data/repositories/orders_repository.dart';
import '../../../../shared/providers/supabase_provider.dart';

class PostUseRefundScreen extends ConsumerStatefulWidget {
  final String orderId;
  final String orderNumber;
  final double totalAmount;
  final List<Map<String, dynamic>>? refundableItems; // 来自 dishes 字段解析

  const PostUseRefundScreen({
    super.key,
    required this.orderId,
    required this.orderNumber,
    required this.totalAmount,
    this.refundableItems,
  });

  @override
  ConsumerState<PostUseRefundScreen> createState() => _PostUseRefundScreenState();
}

class _PostUseRefundScreenState extends ConsumerState<PostUseRefundScreen> {
  final _reasonController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isSubmitting = false;
  Set<int> _selectedItemIndices = {};  // 部分退款选中的商品索引
  bool _isFullRefund = true;

  double get _refundAmount {
    if (_isFullRefund || widget.refundableItems == null) return widget.totalAmount;
    return widget.refundableItems!
        .asMap()
        .entries
        .where((e) => _selectedItemIndices.contains(e.key))
        .fold(0.0, (sum, e) => sum + (e.value['refund_amount'] as double));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);

    try {
      final repo = ref.read(ordersRepositoryProvider);
      await repo.submitPostUseRefundRequest(
        orderId: widget.orderId,
        reason: _reasonController.text.trim(),
        refundItems: _isFullRefund ? null : widget.refundableItems!
            .asMap()
            .entries
            .where((e) => _selectedItemIndices.contains(e.key))
            .map((e) => e.value)
            .toList(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Refund request submitted. The merchant will review it.')),
        );
        Navigator.pop(context, true); // true = 已提交，上一页需刷新
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Request Refund')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 订单信息卡片
            Card(
              child: ListTile(
                title: Text('Order ${widget.orderNumber}'),
                subtitle: Text('Total: \$${widget.totalAmount.toStringAsFixed(2)}'),
              ),
            ),
            const SizedBox(height: 16),

            // 部分退款选择（如果有 refundableItems）
            if (widget.refundableItems != null && widget.refundableItems!.isNotEmpty) ...[
              const Text('Select items to refund:', style: TextStyle(fontWeight: FontWeight.bold)),
              SwitchListTile(
                title: const Text('Full refund'),
                value: _isFullRefund,
                onChanged: (v) => setState(() => _isFullRefund = v),
              ),
              if (!_isFullRefund)
                ...widget.refundableItems!.asMap().entries.map((entry) => CheckboxListTile(
                  title: Text(entry.value['name'] as String),
                  subtitle: Text('\$${(entry.value['refund_amount'] as double).toStringAsFixed(2)}'),
                  value: _selectedItemIndices.contains(entry.key),
                  onChanged: (checked) => setState(() {
                    if (checked == true) _selectedItemIndices.add(entry.key);
                    else _selectedItemIndices.remove(entry.key);
                  }),
                )),
              const SizedBox(height: 8),
            ],

            // 退款金额显示
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Refund amount: \$${_refundAmount.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            const SizedBox(height: 16),

            // 退款理由（必填）
            TextFormField(
              controller: _reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason for refund *',
                hintText: 'Please describe why you are requesting a refund (min. 10 characters)',
                border: OutlineInputBorder(),
              ),
              maxLines: 4,
              maxLength: 500,
              validator: (v) {
                if (v == null || v.trim().length < 10) return 'Please provide a reason (at least 10 characters)';
                return null;
              },
            ),

            // 提示说明
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Your request will be sent to the merchant for review. '
                'If rejected, it will be escalated to our support team.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),

            const SizedBox(height: 16),

            // 提交按钮
            ElevatedButton(
              onPressed: _isSubmitting ? null : _submit,
              child: _isSubmitting
                  ? const CircularProgressIndicator()
                  : const Text('Submit Refund Request'),
            ),
          ],
        ),
      ),
    );
  }
}
```

**Step 2: 在 orders_repository.dart 新增方法**

```dart
/// 提交核销后退款申请
Future<void> submitPostUseRefundRequest({
  required String orderId,
  required String reason,
  List<Map<String, dynamic>>? refundItems,
}) async {
  final response = await _client.functions.invoke(
    'submit-refund-request',
    body: {
      'orderId': orderId,
      'reason': reason,
      if (refundItems != null) 'refundItems': refundItems,
    },
  );
  if (response.status != 201) {
    throw Exception(response.data?['error'] ?? 'Failed to submit refund request');
  }
}
```

**Step 3: 在 order_detail_screen.dart 和 coupon_screen.dart 添加入口按钮**

在订单详情/Coupon 详情中，当 `order.status == 'used'` 且在 24 小时内时，显示按钮：

```dart
// 核销后退款入口
if (order.status == 'used' && _isWithin24Hours(couponRedeemedAt))
  OutlinedButton(
    onPressed: () => Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PostUseRefundScreen(
          orderId: order.id,
          orderNumber: order.orderNumber ?? '',
          totalAmount: order.totalAmount,
          refundableItems: _parseRefundableItems(order),
        ),
      ),
    ),
    child: const Text('Request Refund'),
  ),
```

辅助方法：

```dart
bool _isWithin24Hours(DateTime? redeemedAt) {
  if (redeemedAt == null) return false;
  return DateTime.now().difference(redeemedAt).inHours < 24;
}

/// 解析 dishes 字段为可退款商品列表（带折扣后退款金额）
List<Map<String, dynamic>> _parseRefundableItems(OrderModel order) {
  // dishes 格式: "name::qty::subtotal"
  // 实际实现需从 order.deal 数据中获取 dishes 和 discount_percent
  // 退款金额 = subtotal × (1 - discount_percent/100)
  return []; // Task 内完善实现
}
```

**Step 4: Commit**

```bash
git add deal_joy/lib/features/orders/
git commit -m "feat: post-use refund request UI with partial refund support"
```

---

## Phase 5: 商家端（dealjoy_merchant Flutter）

### Task 14: 新增退款申请列表页

**Files:**
- Create: `dealjoy_merchant/lib/features/orders/pages/refund_requests_page.dart`
- Modify: `dealjoy_merchant/lib/features/orders/pages/orders_list_page.dart`
- Modify: `dealjoy_merchant/lib/features/orders/services/orders_service.dart`

**Step 1: 在 orders_service.dart 新增方法**

```dart
/// 获取退款申请列表
Future<Map<String, dynamic>> fetchRefundRequests({
  String? status,
  int page = 1,
  int perPage = 20,
}) async {
  final response = await _supabase.functions.invoke(
    'merchant-orders',
    method: HttpMethod.get,
    headers: {'Authorization': 'Bearer ${_supabase.auth.currentSession?.accessToken}'},
    // 路径: /merchant-orders/refund-requests?status=pending_merchant&page=1
  );
  // 实现细节参考现有 fetchOrders 方法
  return response.data as Map<String, dynamic>;
}

/// 审批退款申请
Future<void> decideRefundRequest({
  required String refundRequestId,
  required String action, // 'approve' | 'reject'
  String? reason,
}) async {
  // PATCH /merchant-orders/refund-requests/:id
}
```

**Step 2: 新建 refund_requests_page.dart**

参考现有 `orders_list_page.dart` 的结构，展示退款申请列表：
- 每条显示：订单号、Deal 名称、退款金额、申请时间、状态
- 点击进入退款申请详情页
- 顶部 Tab：Pending / All

**Step 3: 在订单列表页（orders_list_page.dart）添加入口**

在 AppBar 或底部导航增加"Refund Requests"入口，带未读数量徽章。

**Step 4: Commit**

```bash
git add dealjoy_merchant/lib/features/orders/
git commit -m "feat: merchant refund requests list page"
```

---

### Task 15: 新增退款申请详情页（审批操作）

**Files:**
- Create: `dealjoy_merchant/lib/features/orders/pages/refund_request_detail_page.dart`

**Step 1: 创建详情页**

页面需要展示：
- 订单详细信息（来自 order）
- 用户申请退款的理由
- 申请退款的商品明细和金额
- 核销信息（时间、核销门店）

操作按钮：
- **Approve Refund**（绿色）→ 确认弹窗 → 调用 `decideRefundRequest(action: 'approve')`
- **Reject & Escalate**（红色）→ 弹出填写拒绝理由的对话框 → 调用 `decideRefundRequest(action: 'reject', reason: ...)`

```dart
// 拒绝退款时的理由填写弹窗
Future<String?> _showRejectDialog() async {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Reason for Rejection'),
      content: TextField(
        controller: controller,
        decoration: const InputDecoration(
          hintText: 'Explain why you are rejecting this refund request...',
          border: OutlineInputBorder(),
        ),
        maxLines: 4,
        maxLength: 500,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            if (controller.text.trim().length >= 10) Navigator.pop(ctx, controller.text.trim());
          },
          child: const Text('Submit'),
        ),
      ],
    ),
  );
}
```

**Step 2: Commit**

```bash
git add dealjoy_merchant/lib/features/orders/pages/refund_request_detail_page.dart
git commit -m "feat: merchant refund request detail page with approve/reject"
```

---

## Phase 6: 管理后台退款仲裁

### Task 16: 管理后台退款仲裁页面

> **说明：** 这里假设管理后台也是 Flutter（dealjoy_merchant 的管理员 role）。如果是 Web 后台，实现方式类似但用不同框架。

**Files:**
- Create: `dealjoy_merchant/lib/features/orders/pages/admin_refund_arbitration_page.dart`
- Create: `dealjoy_merchant/lib/features/orders/pages/admin_refund_detail_page.dart`

**Step 1: admin_refund_arbitration_page.dart**

仅管理员 role 可见的页面，显示所有 `status = 'pending_admin'` 的退款申请。

**Step 2: admin_refund_detail_page.dart**

完整信息展示：
- 订单详细信息（含 payment_intent_id 掩码）
- 用户信息（姓名、邮箱，便于联系）
- 用户退款理由
- 商家拒绝理由
- 核销信息

操作按钮：
- **Approve Refund** → 调用 `admin-refund` edge function（action: 'approve'）
- **Reject Request** → 填写拒绝理由 → 调用 `admin-refund`（action: 'reject'）

**Step 3: 在订单列表页面增加管理员视角的仲裁入口**

参考 CLAUDE.md 中管理后台的实现方式。

**Step 4: Commit**

```bash
git add dealjoy_merchant/lib/features/orders/pages/admin_refund_arbitration_page.dart
git add dealjoy_merchant/lib/features/orders/pages/admin_refund_detail_page.dart
git commit -m "feat: admin refund arbitration pages"
```

---

## 全局 Checklist（每个 Phase 完成后验证）

### Phase 1 完成标志
- [ ] `orders.is_captured` 字段存在，现有订单默认 `true`
- [ ] `refund_requests` 表创建成功，RLS 策略生效
- [ ] `merchant_earnings.frozen_amount` 字段存在

### Phase 2 完成标志
- [ ] 创建 ≤7天有效期的 Deal 订单时，Stripe PI 的 `capture_method = 'manual'`
- [ ] 核销时，`is_captured = false` 的订单会自动触发 `capture-payment`
- [ ] 取消 `authorized` 状态订单时，调用的是 `paymentIntents.cancel()` 而非 `refunds.create()`
- [ ] Stripe webhook 能正确处理 `amount_capturable_updated` 和 `canceled` 事件

### Phase 3 完成标志
- [ ] 核销后 24 小时内可以提交退款申请
- [ ] 超过 24 小时返回 400 错误
- [ ] 商家同意后 Stripe 退款执行成功，订单变为 `refunded`
- [ ] 商家拒绝后订单变为 `refund_pending_admin`
- [ ] 管理员同意后退款完成；拒绝后通知用户被拒绝

### Phase 4-6 完成标志
- [ ] 用户端在 `used` 订单上能看到退款入口（24h内）
- [ ] 商家端能看到 pending 退款申请数量徽章
- [ ] 商家端审批后 UI 状态实时更新
- [ ] 管理后台能看到所有 `pending_admin` 申请

---

## 需要人工确认的事项（开始前确认）

1. **`merchant_earnings` 表的实际列名**：Task 3 Step 1 查询后确认，再写 RPC
2. **Stripe Webhook 新事件**：部署 stripe-webhook 后，需要在 Stripe Dashboard 手动勾选 `payment_intent.amount_capturable_updated` 和 `payment_intent.canceled`
3. **管理后台形态**：管理员操作是在 `dealjoy_merchant` App 的管理员 role 中，还是独立的 Web 后台？
