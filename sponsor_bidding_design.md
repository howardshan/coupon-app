# 竞价排名系统设计文档（Phase 2 完整版）

> **核心决策汇总**
> - ✅ 商家自助投放：在 Merchant App 内设预算、出价、时段
> - ✅ 预充值余额模式：先充值再投放，余额耗尽自动停投
> - ✅ 广告位：首页 Banner / 首页置顶 Deal / 首页置顶 Store / 分类页置顶
> - ✅ 排名公式：出价 × 质量系数（防止低质商家霸屏）
> - ✅ 计费：Banner = CPM，其余 = CPC
> - ✅ 与推荐算法集成：动态 sponsor_boost 替代固定值
> - ✅ 无关键词竞价

---

## Phase 0 · 侦察

```bash
# 1. 确认现有 sponsor 相关字段
grep -rn "is_sponsored\|sponsor_boost\|sponsor_priority" supabase/migrations/*.sql

# 2. 确认现有 Stripe Connect 账户结构
grep -rn "stripe_account\|connect" supabase/functions/ --include="*.ts" -l

# 3. 确认 recommendation_config 表结构
grep -A 20 "recommendation_config" supabase/migrations/*.sql

# 4. 确认 deals / merchants 表分类字段
grep -rn "category" supabase/migrations/*.sql | head -20

# 5. 确认 Admin 后台路由结构
find . -name "*.tsx" -path "*/admin/*" | grep -E "sponsor|ad|campaign" | sort
```

**侦察检查表：**
```
[ ] deals.is_sponsored 字段是否存在：是 / 否
[ ] recommendation_config.sponsor_boost 是否存在：是 / 否
[ ] Stripe Connect 是否已集成：是 / 否
[ ] merchants 表是否有 stripe_account_id：是 / 否
[ ] deals / merchants 是否有 category 字段：是 / 否
```

---

## 一、广告位体系

### 1.1 广告位定义

| 广告位 | 展示位置 | 展示对象 | 计费方式 | 参考日均消耗 |
|--------|---------|---------|---------|------------|
| `home_banner` | 首页 Banner 轮播 | Store / Deal 图片 | CPM（每千次展示）| $30-150 |
| `home_deal_top` | 首页推荐流前3位 | Deal 卡片 | CPC（每次点击）| $20-80 |
| `home_store_top` | 首页 Store 区前3位 | Store 卡片 | CPC | $15-60 |
| `category_store_top` | 分类页前3位 | Store 卡片 | CPC | $10-40 |
| `category_deal_top` | 分类页 Deal 流前3位 | Deal 卡片 | CPC | $8-30 |

### 1.2 排名公式

```
ad_score = bid_price × quality_score

quality_score =
  0.4 × ctr_score          (点击率：该广告历史点击率 / 平台平均点击率)
  + 0.3 × cvr_score         (转化率：点击后购买率)
  + 0.2 × rating_score      (商家评分 / 5.0)
  + 0.1 × budget_health     (日预算剩余比例，防止预算快耗尽时排名骤降)

新广告（无历史数据）：quality_score = 0.7（给新商家起步机会）
```

**与推荐算法的关系：**
```
现有推荐算法：sponsor_boost = 固定 100
升级为：      sponsor_boost = ad_score（动态值）

非 Sponsor 商家：sponsor_boost = 0
```

---

## 二、数据模型

### 2.1 广告账户（余额）

```sql
CREATE TABLE ad_accounts (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id    uuid NOT NULL UNIQUE REFERENCES merchants(id) ON DELETE CASCADE,
  balance        numeric(10,2) NOT NULL DEFAULT 0 CHECK (balance >= 0),
  total_recharged numeric(10,2) NOT NULL DEFAULT 0,
  total_spent    numeric(10,2) NOT NULL DEFAULT 0,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_ad_accounts_merchant_id ON ad_accounts(merchant_id);
```

### 2.2 充值记录

```sql
CREATE TABLE ad_recharges (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id        uuid NOT NULL REFERENCES merchants(id),
  ad_account_id      uuid NOT NULL REFERENCES ad_accounts(id),
  amount             numeric(10,2) NOT NULL,
  stripe_payment_intent_id text NOT NULL,
  status             text NOT NULL DEFAULT 'pending'
                       CHECK (status IN ('pending','succeeded','failed')),
  created_at         timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_ad_recharges_merchant_id ON ad_recharges(merchant_id);
```

### 2.3 广告投放计划

```sql
CREATE TABLE ad_campaigns (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id     uuid NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
  ad_account_id   uuid NOT NULL REFERENCES ad_accounts(id),

  -- 投放对象
  target_type     text NOT NULL CHECK (target_type IN ('deal', 'store')),
  target_id       uuid NOT NULL,   -- deal_id 或 merchant_id

  -- 广告位
  placement       text NOT NULL CHECK (placement IN (
                    'home_banner',
                    'home_deal_top',
                    'home_store_top',
                    'category_store_top',
                    'category_deal_top'
                  )),
  category        text,            -- 分类页投放时必填（category_* 类型）

  -- 出价
  bid_price       numeric(6,4) NOT NULL,  -- CPC 单价 或 CPM 单价（$）
  daily_budget    numeric(8,2) NOT NULL,  -- 日预算上限（$）

  -- 投放时段（可选，NULL = 全天）
  schedule_hours  int[],           -- [11,12,13,17,18,19,20] = 午饭 + 晚饭时段

  -- 状态
  status          text NOT NULL DEFAULT 'active'
                    CHECK (status IN ('active','paused','exhausted','ended')),

  -- 统计（冗余存储，实时更新）
  today_spend     numeric(8,2) NOT NULL DEFAULT 0,
  today_impressions int NOT NULL DEFAULT 0,
  today_clicks    int NOT NULL DEFAULT 0,
  total_spend     numeric(10,2) NOT NULL DEFAULT 0,
  total_impressions int NOT NULL DEFAULT 0,
  total_clicks    int NOT NULL DEFAULT 0,

  -- 质量分（每小时更新）
  quality_score   numeric(4,3) NOT NULL DEFAULT 0.7,
  ad_score        numeric(10,4) NOT NULL DEFAULT 0,  -- bid × quality，排名用

  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_ad_campaigns_merchant_id ON ad_campaigns(merchant_id);
CREATE INDEX idx_ad_campaigns_placement   ON ad_campaigns(placement)
  WHERE status = 'active';
CREATE INDEX idx_ad_campaigns_ad_score    ON ad_campaigns(placement, ad_score DESC)
  WHERE status = 'active';
```

### 2.4 广告事件日志

```sql
CREATE TABLE ad_events (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id uuid NOT NULL REFERENCES ad_campaigns(id),
  merchant_id uuid NOT NULL REFERENCES merchants(id),
  event_type  text NOT NULL CHECK (event_type IN ('impression', 'click', 'conversion')),
  cost        numeric(8,4) NOT NULL DEFAULT 0,  -- 本次事件扣费金额
  user_id     uuid REFERENCES users(id),        -- 触发用户（impression 可为 NULL）
  occurred_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_ad_events_campaign_id  ON ad_events(campaign_id, occurred_at DESC);
CREATE INDEX idx_ad_events_merchant_id  ON ad_events(merchant_id, occurred_at DESC);

-- 90天自动清理
```

### 2.5 每日统计汇总

```sql
CREATE TABLE ad_daily_stats (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id  uuid NOT NULL REFERENCES ad_campaigns(id),
  merchant_id  uuid NOT NULL REFERENCES merchants(id),
  date         date NOT NULL,
  impressions  int NOT NULL DEFAULT 0,
  clicks       int NOT NULL DEFAULT 0,
  conversions  int NOT NULL DEFAULT 0,
  spend        numeric(8,2) NOT NULL DEFAULT 0,
  avg_position numeric(4,2),   -- 平均排名位置
  UNIQUE(campaign_id, date)
);

CREATE INDEX idx_ad_daily_stats_merchant ON ad_daily_stats(merchant_id, date DESC);
```

---

## 三、核心业务逻辑

### 3.1 广告竞价排序（实时）

```typescript
// 每次首页/分类页加载时调用
async function getTopAds(placement: string, category?: string, limit = 3) {
  const now = new Date();
  const currentHour = now.getHours();

  // 查询当前时段有效的投放计划（按 ad_score 排序）
  let query = supabase
    .from('ad_campaigns')
    .select(`
      id, target_type, target_id, placement, bid_price,
      daily_budget, today_spend, quality_score, ad_score,
      schedule_hours,
      ad_accounts!inner(balance)
    `)
    .eq('placement', placement)
    .eq('status', 'active')
    .gt('ad_accounts.balance', 0)           // 余额 > 0
    .lt('today_spend', 'daily_budget')       // 未超日预算
    .order('ad_score', { ascending: false })
    .limit(limit * 3);                       // 多取一些，过滤时段后再截取

  if (category) query = query.eq('category', category);

  const campaigns = await query;

  // 过滤投放时段
  const eligible = campaigns.filter(c => {
    if (!c.schedule_hours || c.schedule_hours.length === 0) return true;
    return c.schedule_hours.includes(currentHour);
  });

  return eligible.slice(0, limit);
}
```

### 3.2 扣费逻辑

```typescript
// impression 事件（Banner CPM）
async function recordImpression(campaignId: string, userId?: string) {
  const campaign = await getCampaign(campaignId);

  // CPM：每1000次展示扣一次
  // 实际实现：每次展示扣 bid_price / 1000
  const cost = campaign.bid_price / 1000;

  await chargeAdAccount(campaign, cost, 'impression', userId);
}

// click 事件（CPC）
async function recordClick(campaignId: string, userId: string) {
  const campaign = await getCampaign(campaignId);

  // CPC：每次点击扣 bid_price
  const cost = campaign.bid_price;

  await chargeAdAccount(campaign, cost, 'click', userId);
}

async function chargeAdAccount(
  campaign: AdCampaign,
  cost: number,
  eventType: string,
  userId?: string
) {
  // 事务：扣余额 + 记录事件 + 更新统计
  const { error } = await supabase.rpc('charge_ad_account', {
    p_campaign_id:  campaign.id,
    p_merchant_id:  campaign.merchant_id,
    p_cost:         cost,
    p_event_type:   eventType,
    p_user_id:      userId,
  });

  if (error) console.error('Charge failed:', error);
}
```

### 3.3 `charge_ad_account` SQL 函数（事务保证）

```sql
CREATE OR REPLACE FUNCTION charge_ad_account(
  p_campaign_id  uuid,
  p_merchant_id  uuid,
  p_cost         numeric,
  p_event_type   text,
  p_user_id      uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_balance     numeric;
  v_today_spend numeric;
  v_daily_budget numeric;
BEGIN
  -- 锁定账户行
  SELECT balance INTO v_balance
  FROM ad_accounts
  WHERE merchant_id = p_merchant_id
  FOR UPDATE;

  SELECT today_spend, daily_budget INTO v_today_spend, v_daily_budget
  FROM ad_campaigns
  WHERE id = p_campaign_id
  FOR UPDATE;

  -- 检查：余额和日预算是否足够
  IF v_balance < p_cost THEN RETURN; END IF;
  IF v_today_spend + p_cost > v_daily_budget THEN
    -- 超日预算，暂停投放
    UPDATE ad_campaigns SET status = 'exhausted' WHERE id = p_campaign_id;
    RETURN;
  END IF;

  -- 扣余额
  UPDATE ad_accounts
  SET balance      = balance - p_cost,
      total_spent  = total_spent + p_cost,
      updated_at   = now()
  WHERE merchant_id = p_merchant_id;

  -- 更新 campaign 统计
  UPDATE ad_campaigns SET
    today_spend        = today_spend + p_cost,
    total_spend        = total_spend + p_cost,
    today_impressions  = today_impressions + CASE WHEN p_event_type = 'impression' THEN 1 ELSE 0 END,
    today_clicks       = today_clicks      + CASE WHEN p_event_type = 'click'      THEN 1 ELSE 0 END,
    total_impressions  = total_impressions + CASE WHEN p_event_type = 'impression' THEN 1 ELSE 0 END,
    total_clicks       = total_clicks      + CASE WHEN p_event_type = 'click'      THEN 1 ELSE 0 END,
    updated_at         = now()
  WHERE id = p_campaign_id;

  -- 写事件日志
  INSERT INTO ad_events (campaign_id, merchant_id, event_type, cost, user_id)
  VALUES (p_campaign_id, p_merchant_id, p_event_type, p_cost, p_user_id);

END;
$$;
```

### 3.4 每日重置（pg_cron 0:00）

```sql
-- 每天凌晨重置 today_spend / today_impressions / today_clicks
-- 并将 exhausted 状态恢复为 active（新的一天新的预算）
CREATE OR REPLACE FUNCTION reset_daily_ad_stats() RETURNS void AS $$
BEGIN
  -- 汇总昨天数据到 ad_daily_stats
  INSERT INTO ad_daily_stats (campaign_id, merchant_id, date,
    impressions, clicks, spend)
  SELECT id, merchant_id, CURRENT_DATE - 1,
    today_impressions, today_clicks, today_spend
  FROM ad_campaigns
  WHERE today_spend > 0
  ON CONFLICT (campaign_id, date) DO UPDATE
    SET impressions = EXCLUDED.impressions,
        clicks      = EXCLUDED.clicks,
        spend       = EXCLUDED.spend;

  -- 重置今日统计
  UPDATE ad_campaigns SET
    today_spend       = 0,
    today_impressions = 0,
    today_clicks      = 0,
    status = CASE WHEN status = 'exhausted' THEN 'active' ELSE status END;
END;
$$ LANGUAGE plpgsql;

SELECT cron.schedule('reset-daily-ad-stats', '0 0 * * *',
  $$ SELECT reset_daily_ad_stats(); $$);
```

### 3.5 质量分更新（pg_cron 每小时）

```sql
CREATE OR REPLACE FUNCTION update_ad_quality_scores() RETURNS void AS $$
BEGIN
  -- 平台平均 CTR（点击率）
  WITH platform_avg AS (
    SELECT
      AVG(CASE WHEN total_impressions > 0
          THEN total_clicks::numeric / total_impressions
          ELSE 0 END) AS avg_ctr,
      AVG(CASE WHEN total_clicks > 0
          THEN (SELECT COUNT(*) FROM ad_events ae2
                WHERE ae2.campaign_id = ac.id
                  AND ae2.event_type = 'conversion')::numeric / total_clicks
          ELSE 0 END) AS avg_cvr
    FROM ad_campaigns ac
    WHERE total_impressions > 100  -- 有足够数据才算
  )
  UPDATE ad_campaigns ac SET
    quality_score = GREATEST(0.1, LEAST(2.0,
      0.4 * COALESCE(
        NULLIF(ac.total_impressions, 0)::numeric,
        CASE WHEN ac.total_impressions = 0 THEN 0.7 ELSE NULL END
      ) / NULLIF((SELECT avg_ctr FROM platform_avg), 0)
      + 0.3 * 0.7   -- cvr 暂时用默认值，后期接真实转化数据
      + 0.2 * (
        SELECT COALESCE(avg_rating, 0) / 5.0
        FROM merchants WHERE id = ac.merchant_id
      )
      + 0.1 * GREATEST(0, 1 - ac.today_spend / NULLIF(ac.daily_budget, 0))
    )),
    ad_score = bid_price * quality_score,
    updated_at = now()
  FROM platform_avg;
END;
$$ LANGUAGE plpgsql;

SELECT cron.schedule('update-ad-quality-scores', '0 * * * *',
  $$ SELECT update_ad_quality_scores(); $$);
```

---

## 四、充值流程

### 4.1 充值 Edge Function

```typescript
// create-ad-recharge：商家充值
// 入参：merchant_id, amount（最低 $20，最高 $5000）

// 1. 创建 Stripe PaymentIntent（直接 charge 商家的 payment method）
const pi = await stripe.paymentIntents.create({
  amount:   Math.round(amount * 100),
  currency: 'usd',
  customer: merchant.stripe_customer_id,
  metadata: { merchant_id, type: 'ad_recharge' },
  description: `Crunchy Plum Ad Credit Recharge - ${merchant.name}`,
});

// 2. 记录充值申请
await supabase.from('ad_recharges').insert({
  merchant_id,
  ad_account_id:             account.id,
  amount,
  stripe_payment_intent_id:  pi.id,
  status:                    'pending',
});

return { clientSecret: pi.client_secret };
```

### 4.2 充值 Webhook

```typescript
// stripe-webhook 新增处理
case 'payment_intent.succeeded':
  if (pi.metadata.type === 'ad_recharge') {
    const merchantId = pi.metadata.merchant_id;
    const amount     = pi.amount / 100;

    // 更新充值记录
    await supabase.from('ad_recharges')
      .update({ status: 'succeeded' })
      .eq('stripe_payment_intent_id', pi.id);

    // 增加广告账户余额
    await supabase.from('ad_accounts')
      .update({
        balance:        supabase.rpc('increment', { amount }),
        total_recharged: supabase.rpc('increment', { amount }),
      })
      .eq('merchant_id', merchantId);

    // 发通知给商家
    await sendNotification({
      userId: merchant.owner_user_id,
      type:   'transaction',
      title:  'Ad Credit Added',
      body:   `$${amount} has been added to your ad account.`,
    });
  }
  break;
```

---

## 五、UI 设计

### 5.1 商家端：广告管理主页

```
┌─────────────────────────────────────────────┐
│  📢 Promotions                              │
│                                             │
│  Ad Balance: $127.50          [Recharge]    │
│                                             │
│  ── Active Campaigns ──────────────────    │
│  ┌─────────────────────────────────────┐   │
│  │ 🏠 Home Featured Deal              │   │
│  │ Deal A · $0.80/click               │   │
│  │ Today: 234 views · 18 clicks · $14.40│  │
│  │ Budget: $50/day  ████████░░ $35.60 left│ │
│  │ [Pause]  [Edit]                    │   │
│  └─────────────────────────────────────┘   │
│                                             │
│  ┌─────────────────────────────────────┐   │
│  │ 📂 Restaurant Category Top         │   │
│  │ Store · $0.50/click                │   │
│  │ Today: 89 views · 5 clicks · $2.50  │   │
│  │ Budget: $20/day  ██░░░░░░░░ $17.50 left│ │
│  │ [Pause]  [Edit]                    │   │
│  └─────────────────────────────────────┘   │
│                                             │
│  [+ New Campaign]                           │
└─────────────────────────────────────────────┘
```

### 5.2 创建 Campaign 页面

```
┌─────────────────────────────────────────────┐
│  ← Create Campaign                          │
│                                             │
│  What do you want to promote?               │
│  ○ A Deal                                   │
│  ● My Store                                 │
│                                             │
│  Select Store                               │
│  [Crunchy Plum Dallas ▼]                   │
│                                             │
│  Ad Placement                               │
│  ○ Home Page Featured           ~$50-150/day│
│  ● Home Page Store Top          ~$15-60/day │
│  ○ Restaurant Category Top      ~$10-40/day │
│                                             │
│  Bid (per click)                            │
│  [$] [0.80]                                 │
│  Suggested: $0.50 - $1.20                   │
│  Estimated daily clicks: 15-30              │
│                                             │
│  Daily Budget                               │
│  [$] [30.00]                                │
│  Min: $10 · Balance: $127.50               │
│                                             │
│  Schedule (optional)                        │
│  ☑ Lunch (11am-2pm)                        │
│  ☑ Dinner (5pm-9pm)                        │
│  ☐ All day                                  │
│                                             │
│  Estimated reach: 200-500 people/day        │
│                                             │
│  [Launch Campaign]                          │
└─────────────────────────────────────────────┘
```

### 5.3 充值页面

```
┌─────────────────────────────────────────────┐
│  ← Recharge Ad Account                      │
│                                             │
│  Current Balance: $27.50                    │
│                                             │
│  Select Amount                              │
│  [  $50  ]  [  $100  ]  [  $200  ]         │
│  [  $500  ]  [ Custom ]                     │
│                                             │
│  Custom: [$] [___]                          │
│  Min $20 · Max $5,000                       │
│                                             │
│  Payment Method                             │
│  💳 Visa ending 4242  [Change]             │
│                                             │
│  [Recharge $100]                            │
│  Funds available immediately after payment  │
└─────────────────────────────────────────────┘
```

### 5.4 数据报告页

```
┌─────────────────────────────────────────────┐
│  ← Campaign Report                          │
│  Home Featured Deal · Deal A                │
│                                             │
│  [7 Days ▼]  Mar 24 – Mar 30               │
│                                             │
│  Total Spend    Total Clicks   CTR          │
│  $89.60         112            4.8%         │
│                                             │
│  [折线图：每日消耗和点击量]                    │
│                                             │
│  ── Daily Breakdown ───────────────────    │
│  Date       Views  Clicks  Spend   CTR     │
│  Mar 30     234    18      $14.40  7.7%    │
│  Mar 29     198    11      $8.80   5.6%    │
│  Mar 28     220    14      $11.20  6.4%    │
│  ...                                        │
└─────────────────────────────────────────────┘
```

### 5.5 用户端：Sponsored 标识

```
┌──────────────────────────────────────────┐
│  [Deal 图片]                              │
│  Deal A · Crunchy Plum Dallas            │
│  ★ 4.3  $8.99  Sponsored ←── 小标签    │
└──────────────────────────────────────────┘
```

---

## 六、Admin 后台

### 6.1 Admin 广告管理页

```
/admin/ads                    → 所有 Campaign 列表
/admin/ads/[id]               → 单个 Campaign 详情
/admin/ads/accounts           → 商家广告账户余额总览
/admin/ads/revenue            → 平台广告收入报表
```

**功能：**
- 查看所有商家的投放状态
- 强制暂停违规 Campaign
- 查看平台今日广告收入
- 设置各广告位的最低出价（防止恶意低价）
- 调整质量分权重参数

### 6.2 平台广告收入看板

```
┌─────────────────────────────────────────────┐
│  Ad Revenue Dashboard                       │
│                                             │
│  Today's Revenue        This Month          │
│  $342.80                $8,920.50           │
│                                             │
│  Active Campaigns       Active Merchants    │
│  47                     23                  │
│                                             │
│  Top Spending Merchants (Today)             │
│  1. Crunchy Plum Dallas    $89.60           │
│  2. Beauty Plus            $67.20           │
│  3. Spa Garden             $45.00           │
└─────────────────────────────────────────────┘
```

---

## 七、与推荐算法的集成

### 7.1 修改 get-recommendations Edge Function

```typescript
// 在推荐算法里，用动态 ad_score 替代固定 sponsor_boost

async function getTopSponsoredAds(placement: string) {
  const now = new Date();
  const currentHour = now.getHours();

  const ads = await supabase
    .from('ad_campaigns')
    .select('target_id, target_type, ad_score, schedule_hours')
    .eq('placement', placement)
    .eq('status', 'active')
    .order('ad_score', { ascending: false })
    .limit(5);

  return ads.filter(ad => {
    if (!ad.schedule_hours?.length) return true;
    return ad.schedule_hours.includes(currentHour);
  });
}

// 在推荐排序时：
const deals = allDeals.map(deal => {
  const sponsoredAd = sponsoredAds.find(
    ad => ad.target_type === 'deal' && ad.target_id === deal.id
  );

  const sponsorBoost = sponsoredAd ? sponsoredAd.ad_score : 0;

  const score = computeBaseScore(deal, userTag, config)
              + sponsorBoost;

  return { ...deal, score, isSponsored: !!sponsoredAd };
});
```

### 7.2 记录广告曝光（推荐列表返回时）

```typescript
// 返回推荐列表的同时，异步记录曝光
for (const deal of result.filter(d => d.isSponsored)) {
  recordImpression(deal.campaignId, userId);  // 不阻塞主流程
}
```

---

## 八、Migration 文件

### 文件名：`[timestamp]_sponsor_bidding.sql`

```sql
-- ============================================================
-- Step 1: ad_accounts 表
-- ============================================================
CREATE TABLE IF NOT EXISTS ad_accounts (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id     uuid NOT NULL UNIQUE REFERENCES merchants(id) ON DELETE CASCADE,
  balance         numeric(10,2) NOT NULL DEFAULT 0 CHECK (balance >= 0),
  total_recharged numeric(10,2) NOT NULL DEFAULT 0,
  total_spent     numeric(10,2) NOT NULL DEFAULT 0,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE ad_accounts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "merchant_view_own_ad_account" ON ad_accounts
  FOR SELECT USING (
    merchant_id IN (
      SELECT merchant_id FROM merchant_staff WHERE user_id = auth.uid()
    )
  );

-- ============================================================
-- Step 2: ad_recharges 表
-- ============================================================
CREATE TABLE IF NOT EXISTS ad_recharges (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id              uuid NOT NULL REFERENCES merchants(id),
  ad_account_id            uuid NOT NULL REFERENCES ad_accounts(id),
  amount                   numeric(10,2) NOT NULL CHECK (amount >= 20),
  stripe_payment_intent_id text NOT NULL UNIQUE,
  status                   text NOT NULL DEFAULT 'pending'
                             CHECK (status IN ('pending','succeeded','failed')),
  created_at               timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ad_recharges_merchant
  ON ad_recharges(merchant_id, created_at DESC);

-- ============================================================
-- Step 3: ad_campaigns 表
-- ============================================================
CREATE TABLE IF NOT EXISTS ad_campaigns (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id     uuid NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
  ad_account_id   uuid NOT NULL REFERENCES ad_accounts(id),
  target_type     text NOT NULL CHECK (target_type IN ('deal','store')),
  target_id       uuid NOT NULL,
  placement       text NOT NULL CHECK (placement IN (
                    'home_banner','home_deal_top','home_store_top',
                    'category_store_top','category_deal_top'
                  )),
  category        text,
  bid_price       numeric(6,4) NOT NULL CHECK (bid_price > 0),
  daily_budget    numeric(8,2) NOT NULL CHECK (daily_budget >= 10),
  schedule_hours  int[],
  status          text NOT NULL DEFAULT 'active'
                    CHECK (status IN ('active','paused','exhausted','ended')),
  today_spend     numeric(8,2) NOT NULL DEFAULT 0,
  today_impressions int NOT NULL DEFAULT 0,
  today_clicks    int NOT NULL DEFAULT 0,
  total_spend     numeric(10,2) NOT NULL DEFAULT 0,
  total_impressions int NOT NULL DEFAULT 0,
  total_clicks    int NOT NULL DEFAULT 0,
  quality_score   numeric(4,3) NOT NULL DEFAULT 0.7,
  ad_score        numeric(10,4) NOT NULL DEFAULT 0,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ad_campaigns_placement_score
  ON ad_campaigns(placement, ad_score DESC)
  WHERE status = 'active';

ALTER TABLE ad_campaigns ENABLE ROW LEVEL SECURITY;
CREATE POLICY "merchant_manage_own_campaigns" ON ad_campaigns
  FOR ALL USING (
    merchant_id IN (
      SELECT merchant_id FROM merchant_staff WHERE user_id = auth.uid()
    )
  );

CREATE TRIGGER set_ad_campaigns_updated_at
  BEFORE UPDATE ON ad_campaigns
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================
-- Step 4: ad_events 表
-- ============================================================
CREATE TABLE IF NOT EXISTS ad_events (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id uuid NOT NULL REFERENCES ad_campaigns(id),
  merchant_id uuid NOT NULL REFERENCES merchants(id),
  event_type  text NOT NULL CHECK (event_type IN ('impression','click','conversion')),
  cost        numeric(8,4) NOT NULL DEFAULT 0,
  user_id     uuid REFERENCES users(id),
  occurred_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ad_events_campaign
  ON ad_events(campaign_id, occurred_at DESC);

-- ============================================================
-- Step 5: ad_daily_stats 表
-- ============================================================
CREATE TABLE IF NOT EXISTS ad_daily_stats (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id  uuid NOT NULL REFERENCES ad_campaigns(id),
  merchant_id  uuid NOT NULL REFERENCES merchants(id),
  date         date NOT NULL,
  impressions  int NOT NULL DEFAULT 0,
  clicks       int NOT NULL DEFAULT 0,
  conversions  int NOT NULL DEFAULT 0,
  spend        numeric(8,2) NOT NULL DEFAULT 0,
  avg_position numeric(4,2),
  UNIQUE(campaign_id, date)
);

CREATE INDEX IF NOT EXISTS idx_ad_daily_stats_merchant
  ON ad_daily_stats(merchant_id, date DESC);

-- ============================================================
-- Step 6: charge_ad_account 函数
-- ============================================================
CREATE OR REPLACE FUNCTION charge_ad_account(
  p_campaign_id uuid,
  p_merchant_id uuid,
  p_cost        numeric,
  p_event_type  text,
  p_user_id     uuid DEFAULT NULL
)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  v_balance      numeric;
  v_today_spend  numeric;
  v_daily_budget numeric;
BEGIN
  SELECT balance INTO v_balance FROM ad_accounts
  WHERE merchant_id = p_merchant_id FOR UPDATE;

  SELECT today_spend, daily_budget INTO v_today_spend, v_daily_budget
  FROM ad_campaigns WHERE id = p_campaign_id FOR UPDATE;

  IF v_balance < p_cost THEN RETURN; END IF;
  IF v_today_spend + p_cost > v_daily_budget THEN
    UPDATE ad_campaigns SET status = 'exhausted' WHERE id = p_campaign_id;
    RETURN;
  END IF;

  UPDATE ad_accounts SET
    balance      = balance - p_cost,
    total_spent  = total_spent + p_cost,
    updated_at   = now()
  WHERE merchant_id = p_merchant_id;

  UPDATE ad_campaigns SET
    today_spend       = today_spend + p_cost,
    total_spend       = total_spend + p_cost,
    today_impressions = today_impressions + CASE WHEN p_event_type='impression' THEN 1 ELSE 0 END,
    today_clicks      = today_clicks      + CASE WHEN p_event_type='click'      THEN 1 ELSE 0 END,
    total_impressions = total_impressions + CASE WHEN p_event_type='impression' THEN 1 ELSE 0 END,
    total_clicks      = total_clicks      + CASE WHEN p_event_type='click'      THEN 1 ELSE 0 END,
    updated_at        = now()
  WHERE id = p_campaign_id;

  INSERT INTO ad_events (campaign_id, merchant_id, event_type, cost, user_id)
  VALUES (p_campaign_id, p_merchant_id, p_event_type, p_cost, p_user_id);
END;
$$;

-- ============================================================
-- Step 7: pg_cron 定时任务
-- ============================================================
-- 每天凌晨重置日统计
SELECT cron.schedule('reset-daily-ad-stats', '0 0 * * *',
  $$ SELECT reset_daily_ad_stats(); $$);

-- 每小时更新质量分
SELECT cron.schedule('update-ad-quality-scores', '0 * * * *',
  $$ SELECT update_ad_quality_scores(); $$);

-- ============================================================
-- Step 8: 为已有商家自动创建广告账户
-- ============================================================
INSERT INTO ad_accounts (merchant_id)
SELECT id FROM merchants
WHERE id NOT IN (SELECT merchant_id FROM ad_accounts)
ON CONFLICT DO NOTHING;
```

---

## 九、执行顺序

```
Phase 0: 侦察 → 填检查表
    ↓
Phase 1: Migration（按 Step 1-8）
    ↓ supabase db push（staging 验证）
Phase 2: Edge Functions
         - create-ad-recharge（充值发起）
         - stripe-webhook 新增 ad_recharge 处理
         - record-ad-event（impression / click）
         - get-top-ads（广告位竞价排序）
    ↓
Phase 3: pg_cron 定时任务
         - reset-daily-ad-stats（每天 0:00）
         - update-ad-quality-scores（每小时）
    ↓
Phase 4: 推荐算法集成
         - get-recommendations 改为动态 ad_score
         - 返回推荐列表时异步记录 impression
    ↓
Phase 5: 商家端 App
         - 广告账户余额展示
         - 充值流程（Stripe）
         - Campaign 创建/编辑/暂停
         - 数据报告页（每日统计折线图）
    ↓
Phase 6: Admin 后台
         - 所有 Campaign 列表
         - 平台广告收入看板
         - 强制暂停 / 最低出价设置
    ↓
Phase 7: 用户端
         - Deal/Store 卡片加 Sponsored 标签
         - 点击广告时记录 click 事件
    ↓
Phase 8: 验证
         - 充值 → 余额到账
         - 创建 Campaign → 出现在对应广告位
         - 点击扣费 → 余额减少 → 统计更新
         - 日预算耗尽 → 自动停投 → 次日恢复
         - 出价高的 Campaign 排名靠前
         - 质量分影响排名（高 CTR 商家出价低仍能靠前）
    ↓
Phase 9: Maestro 测试
```

---

## progress.md 规范

```markdown
## [YYYY-MM-DD HH:mm] Phase X 完成
- 实际操作：...
- 差异：...
- 跳过：...
- 下一步：...

## [YYYY-MM-DD HH:mm] Phase X 阻塞
- 原因：...
- 需要人工确认：...
```
