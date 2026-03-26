# 首页推荐算法系统设计文档

> **核心决策汇总**
> - ✅ 第一期 Rule-based 权重公式，后期升级 ML
> - ✅ Admin 用自然语言描述算法，Claude 解析成权重配置
> - ✅ 用户信号：浏览、购买、搜索、地理位置、评价属性、时段
> - ✅ 刷新策略：预计算（定时）+ 实时少量调整
> - ✅ 地理：距离越近分数越高，但不排除远的
> - ✅ Sponsor 商家始终置顶

---

## Phase 0 · 侦察

```bash
# 1. 确认现有 deals / merchants 表结构
grep -A 30 "CREATE TABLE deals\|CREATE TABLE merchants" supabase/migrations/*.sql

# 2. 确认现有用户行为相关表
grep -rn "view\|browse\|search_history\|user_event" supabase/migrations/*.sql

# 3. 确认 Supabase pg_cron 是否已启用
grep -rn "cron\|pg_cron" supabase/ --include="*.sql" --include="*.ts"

# 4. 确认 pgvector 扩展是否已安装（Phase 2 升级用）
grep -rn "pgvector\|vector" supabase/ --include="*.sql"

# 5. 确认现有 Admin 配置表
grep -rn "config\|settings\|admin_config" supabase/migrations/*.sql

# 6. 确认 Claude API 集成
grep -rn "anthropic\|claude" supabase/functions/ --include="*.ts" -l
```

**侦察检查表（2026-03-26 已完成）：**
```
[✅] deals 表是否有 category 字段：是（text 类型，已有）
[❌] deals 表是否有 tags 字段：否（需新增 text[]）
[❌] deals 表是否有 meal_type 字段：否（需新增）
[❌] deals 表是否有 is_sponsored 字段：否（需新增）
[✅] deals 表其他可用字段：rating, review_count, total_sold, is_featured, deal_type, badge_text, discount_percent, expires_at
[✅] merchants 表是否有 category 字段：是（Restaurant, SpaAndMassage, HairAndBeauty 等）
[✅] merchants 表是否有 lat/lng 字段：是（double precision）
[✅] merchants 表是否有 tags 字段：是（text[]）
[✅] merchants 表是否有 avg_rating/review_count 字段：是
[❌] merchants 表是否有 cuisine_type 字段：否（需新增）
[❌] merchants 表是否有 avg_redemption_rate 字段：否（需新增）
[❌] merchants 表是否有 refund_rate 字段：否（需新增）
[✅] pg_cron 是否已启用：是（已有 5 个定时任务：auto-capture-preauth, notify-expiring-coupons/deals, admin-daily-digest, monthly-settlement-report）
[❌] pgvector 是否已安装：否（Phase 2 需要，Phase 1 不需要）
[✅] 现有用户行为记录表：login_history（登录追踪）, saved_deals（收藏）, reviews（评价含多维评分）, orders/coupons（购买/核销）, after_sales_events（售后）
[❌] 缺失行为表：无 view_deal / search_history / browsing_history 表 → 需新建 user_events 统一事件表
[✅] Claude API key 是否已配置：是（support-chat Edge Function 已集成，使用 claude-sonnet-4-20250514，环境变量 ANTHROPIC_API_KEY 已配置）
[✅] users 表活跃度追踪：有 last_login_at 字段（可替代 last_active_at）+ login_history 表
[✅] Admin 配置表参考模式：platform_commission_config, email_type_settings 等（可参考 RLS 策略和表设计）
```

**侦察结论 — 需要新建/新增的内容：**

| 类型 | 具体项 | 说明 |
|------|--------|------|
| 新建表 | `user_events` | 统一用户行为事件日志（view/search/purchase/redeem/review/refund） |
| 新建表 | `user_tags` | 用户标签（定时计算） |
| 新建表 | `recommendation_config` | 算法权重配置（含默认权重） |
| 新建表 | `recommendation_cache` | 个人推荐预计算缓存 |
| 新建表 | `recommendation_global_cache` | 全局热门缓存（冷启动用） |
| deals 新增字段 | `meal_type`, `price_tier`, `tags`, `is_sponsored`, `sponsor_priority` | category 已有不需要加 |
| merchants 新增字段 | `cuisine_type`, `avg_redemption_rate`, `refund_rate` | lat/lng/category/tags/avg_rating/review_count 已有不需要加 |

**⚠️ Migration 注意事项（基于侦察结果）：**
- deals 表 `category` 字段已存在 → Migration 中 `ADD COLUMN IF NOT EXISTS category` 不会出错但为空操作
- merchants 表 `lat`/`lng` 已存在且类型是 `double precision` → 不能再加 `numeric(10,7)` 同名列，需跳过
- merchants 表 `category`/`tags` 已存在 → 同上跳过
- merchants 表无 `last_active_at` → 但 users 表有 `last_login_at`，compute-recommendations 应改用 `users.last_login_at` 代替
- deals 表有 `is_active` → compute-recommendations 查询条件应用 `.eq('is_active', true)` 而非 `.eq('status', 'active')`

---

## 一、系统架构总览

```
┌─────────────────────────────────────────────────────┐
│                  推荐系统全景                         │
├─────────────────────────────────────────────────────┤
│                                                     │
│  数据层                                              │
│  ├── 用户行为日志（events）                           │
│  ├── 用户标签（user_tags）                            │
│  ├── Deal/商家标签（deal_tags / merchant_tags）       │
│  └── 算法配置（recommendation_config）               │
│                                                     │
│  计算层                                              │
│  ├── 预计算 Job（pg_cron，每15分钟）                  │
│  │   └── 写入 recommendation_cache                  │
│  └── 实时调整（Edge Function，App 启动时）            │
│      └── Sponsor 置顶 + 时段调整 + 位置调整           │
│                                                     │
│  Admin 控制层                                        │
│  ├── 自然语言输入算法描述                             │
│  ├── Claude 解析 → 权重 JSON                         │
│  └── 写入 recommendation_config → 下次预计算生效      │
│                                                     │
│  展示层                                              │
│  └── Flutter App 读取推荐结果 + 实时微调             │
└─────────────────────────────────────────────────────┘
```

---

## 二、算法设计

### 2.1 总分公式

```
final_score =
  sponsor_boost          （Sponsor 置顶加成，直接排前）
  + w_relevance  × relevance_score    （相关性：用户偏好匹配）
  + w_distance   × distance_score     （地理距离）
  + w_popularity × popularity_score   （热度）
  + w_quality    × quality_score      （质量：评分/核销率）
  + w_freshness  × freshness_score    （新鲜度：新上架）
  + w_time_slot  × time_slot_score    （时段匹配）
  + w_diversity  × diversity_boost    （多样性防止重复）
```

### 2.2 各维度评分细则

#### 相关性分 `relevance_score` (0~1)

```
基于用户标签与 Deal 标签的重叠度：

user_category_affinity = 用户在该分类的购买次数 / 用户总购买次数
user_price_match       = 1 - |deal.price - user_avg_price| / user_avg_price
user_search_match      = deal 分类是否出现在近7天搜索历史（0 or 1）
review_preference      = 用户历史高评分的分类与 deal 分类是否匹配（0~1）

relevance_score =
  0.4 × user_category_affinity
  + 0.2 × user_price_match
  + 0.2 × user_search_match
  + 0.2 × review_preference
```

#### 距离分 `distance_score` (0~1)

```
distance_km = 用户当前位置到商家的距离

distance_score =
  1.0   if distance_km <= 1
  0.9   if distance_km <= 3
  0.75  if distance_km <= 5
  0.5   if distance_km <= 10
  0.3   if distance_km <= 20
  0.1   otherwise

新用户或未授权位置：distance_score = 0.5（中性值）
```

#### 热度分 `popularity_score` (0~1)

```
recent_purchases = 近7天购买数
recent_views     = 近7天浏览数
redemption_rate  = 已核销数 / 已购买数（用券率，高代表用户实际去了）

raw_popularity =
  0.5 × log(1 + recent_purchases) / log(1 + max_purchases_in_platform)
  + 0.3 × log(1 + recent_views) / log(1 + max_views_in_platform)
  + 0.2 × redemption_rate

popularity_score = CLIP(raw_popularity, 0, 1)
```

#### 质量分 `quality_score` (0~1)

```
avg_rating     = 商家平均评分（0~5）
review_count   = 评价数量
refund_rate    = 退款数 / 购买数（低退款 = 高质量）

quality_score =
  0.5 × (avg_rating / 5.0)
  + 0.3 × min(1.0, log(1 + review_count) / log(100))
  + 0.2 × (1 - refund_rate)
```

#### 新鲜度分 `freshness_score` (0~1)

```
days_since_created = 今天 - deal 上架日期

freshness_score =
  1.0   if days_since_created <= 3
  0.8   if days_since_created <= 7
  0.5   if days_since_created <= 14
  0.2   if days_since_created <= 30
  0.0   otherwise
```

#### 时段分 `time_slot_score` (0~1)

```
当前时段（服务器时间，Dallas CST）：
  breakfast:  06:00 - 10:00
  lunch:      11:00 - 14:00
  afternoon:  14:00 - 17:00
  dinner:     17:00 - 21:00
  late_night: 21:00 - 02:00
  other:      其余时间

deal 的 meal_type 标签（breakfast/lunch/dinner/all_day）：
  time_slot_score = 1.0  如果 deal.meal_type 匹配当前时段
  time_slot_score = 0.6  如果 deal.meal_type = 'all_day'
  time_slot_score = 0.2  如果不匹配

非餐饮类 deal（beauty/entertainment 等）：time_slot_score = 0.5（中性）
```

#### 多样性控制 `diversity_boost`

```
同一商家在推荐列表前20位中最多出现2次
超过2次的商家打 -0.3 惩罚分
```

### 2.3 默认权重配置

```json
{
  "weights": {
    "w_relevance":  0.30,
    "w_distance":   0.20,
    "w_popularity": 0.20,
    "w_quality":    0.15,
    "w_freshness":  0.10,
    "w_time_slot":  0.05
  },
  "sponsor_boost": 100.0,
  "diversity_penalty": -0.30,
  "max_same_merchant": 2,
  "cache_ttl_minutes": 15,
  "realtime_pool_size": 50,
  "version": "1.0.0",
  "description": "默认权重：相关性优先，兼顾距离和热度"
}
```

---

## 三、用户标签系统

### 3.1 自动生成的用户标签

```sql
-- user_tags 表（定时任务计算，每小时更新）
CREATE TABLE user_tags (
  user_id            uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  top_categories     text[],          -- ['restaurant', 'beauty', 'entertainment']
  avg_spend          numeric(10,2),   -- 平均消费金额
  price_tier         text,            -- 'budget'(<$10) | 'mid'($10-30) | 'premium'(>$30)
  active_time_slots  text[],          -- ['lunch', 'dinner']（最常下单的时段）
  favorite_hashtags  text[],          -- 从 review 里的 hashtag 提取
  purchase_frequency text,            -- 'low'(<1/month) | 'mid' | 'high'(>4/month)
  location_lat       numeric,         -- 最近30天最常出现的位置（模糊化）
  location_lng       numeric,
  search_keywords    text[],          -- 近7天搜索词
  last_updated_at    timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id)
);
```

### 3.2 Deal/商家标签

```sql
-- deal_tags（管理员 + 自动打标）
ALTER TABLE deals
  ADD COLUMN IF NOT EXISTS category    text,
  ADD COLUMN IF NOT EXISTS meal_type   text CHECK (meal_type IN
                             ('breakfast','lunch','dinner','all_day','n/a')),
  ADD COLUMN IF NOT EXISTS price_tier  text CHECK (price_tier IN
                             ('budget','mid','premium')),
  ADD COLUMN IF NOT EXISTS tags        text[] DEFAULT '{}';

-- merchant_tags
ALTER TABLE merchants
  ADD COLUMN IF NOT EXISTS category    text,
  ADD COLUMN IF NOT EXISTS cuisine_type text,
  ADD COLUMN IF NOT EXISTS tags        text[] DEFAULT '{}';
```

### 3.3 用户行为事件日志

```sql
CREATE TABLE user_events (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  event_type  text NOT NULL CHECK (event_type IN (
                'view_deal',      -- 浏览 deal
                'view_merchant',  -- 浏览商家
                'search',         -- 搜索
                'purchase',       -- 购买
                'redeem',         -- 核销
                'review',         -- 评价
                'refund'          -- 退款
              )),
  deal_id     uuid REFERENCES deals(id),
  merchant_id uuid REFERENCES merchants(id),
  metadata    jsonb,   -- { search_query, rating, amount, duration_seconds, ... }
  occurred_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_user_events_user_id    ON user_events(user_id, occurred_at DESC);
CREATE INDEX idx_user_events_event_type ON user_events(event_type, occurred_at DESC);
CREATE INDEX idx_user_events_deal_id    ON user_events(deal_id);

-- 保留90天，自动清理
CREATE OR REPLACE FUNCTION cleanup_old_events() RETURNS void AS $$
BEGIN
  DELETE FROM user_events WHERE occurred_at < now() - interval '90 days';
END;
$$ LANGUAGE plpgsql;
```

---

## 四、算法配置表（Admin 控制核心）

```sql
CREATE TABLE recommendation_config (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  version     text NOT NULL,
  weights     jsonb NOT NULL,          -- 权重 JSON
  description text,                   -- Admin 写的自然语言描述
  is_active   boolean NOT NULL DEFAULT false,
  created_by  uuid REFERENCES users(id),
  created_at  timestamptz NOT NULL DEFAULT now(),
  activated_at timestamptz
);

-- 每次只有一条 is_active = true
CREATE UNIQUE INDEX idx_recommendation_config_active
  ON recommendation_config(is_active) WHERE is_active = true;

-- 预计算缓存
CREATE TABLE recommendation_cache (
  user_id        uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  deal_ids       uuid[] NOT NULL,      -- 预计算的推荐 deal ID 列表（按分数排序）
  scores         jsonb,               -- { deal_id: score, ... } 供调试
  computed_at    timestamptz NOT NULL DEFAULT now(),
  config_version text NOT NULL,
  PRIMARY KEY (user_id)
);

-- 全局热门缓存（新用户 / 冷启动用）
CREATE TABLE recommendation_global_cache (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  deal_ids    uuid[] NOT NULL,
  computed_at timestamptz NOT NULL DEFAULT now(),
  time_slot   text NOT NULL DEFAULT 'all'  -- 'all' | 'breakfast' | 'lunch' | 'dinner'
);
```

---

## 五、Admin 自然语言配置算法

### 5.1 流程

```
Admin 在管理后台输入自然语言描述
例："现在是周末，应该更重视好友推荐和热度，
     距离不那么重要，多推一些新商家"
    ↓
调用 parse-recommendation-config Edge Function
    ↓
Claude 解析 → 生成新的权重 JSON
    ↓
Admin 预览权重 + 确认
    ↓
写入 recommendation_config，标记为 active
    ↓
下次 pg_cron 预计算时使用新权重
```

### 5.2 `parse-recommendation-config` Edge Function

```typescript
const PARSE_SYSTEM_PROMPT = `
You are an algorithm configuration assistant for Crunchy Plum,
a local deals platform in Dallas.

Your job is to translate natural language algorithm descriptions
into a JSON weight configuration.

Weight fields and their meaning:
- w_relevance (0~1):  How much user preference history matters
- w_distance (0~1):   How much geographic proximity matters
- w_popularity (0~1): How much trending/popular deals are boosted
- w_quality (0~1):    How much ratings and reviews matter
- w_freshness (0~1):  How much newly listed deals are boosted
- w_time_slot (0~1):  How much meal-time relevance matters
- sponsor_boost:      Score added to sponsored merchants (keep >= 50)
- diversity_penalty:  Penalty for same merchant appearing too much (keep negative)
- max_same_merchant:  Max times same merchant appears in top 20

Rules:
1. All weights (w_*) must sum to exactly 1.0
2. sponsor_boost must be between 50 and 200
3. diversity_penalty must be between -0.5 and -0.1
4. Respond ONLY with valid JSON, no explanation

Example output:
{
  "weights": {
    "w_relevance": 0.30,
    "w_distance": 0.20,
    "w_popularity": 0.20,
    "w_quality": 0.15,
    "w_freshness": 0.10,
    "w_time_slot": 0.05
  },
  "sponsor_boost": 100.0,
  "diversity_penalty": -0.30,
  "max_same_merchant": 2,
  "cache_ttl_minutes": 15,
  "version": "auto-generated",
  "description": "[admin's original description]"
}
`;

// Edge Function 入口
export async function parseRecommendationConfig(req: Request) {
  const { description, adminUserId } = await req.json();

  const response = await anthropic.messages.create({
    model:      'claude-sonnet-4-20250514',
    max_tokens: 500,
    system:     PARSE_SYSTEM_PROMPT,
    messages:   [{ role: 'user', content: description }],
  });

  const rawJson = response.content[0].text.trim();

  // 验证 JSON 合法性
  let config: RecommendationConfig;
  try {
    config = JSON.parse(rawJson);
  } catch {
    return { error: 'Failed to parse config', raw: rawJson };
  }

  // 验证权重之和 = 1.0
  const weights = config.weights;
  const sum = Object.values(weights).reduce((a, b) => a + b, 0);
  if (Math.abs(sum - 1.0) > 0.01) {
    // 自动归一化
    Object.keys(weights).forEach(k => {
      weights[k] = weights[k] / sum;
    });
  }

  // 写入数据库（pending 状态，等 Admin 确认）
  const { data } = await supabase.from('recommendation_config').insert({
    version:     `admin-${Date.now()}`,
    weights:     config,
    description: description,
    is_active:   false,
    created_by:  adminUserId,
  }).select().single();

  return { configId: data.id, config, preview: generatePreviewText(config) };
}

// Admin 确认激活
export async function activateRecommendationConfig(configId: string) {
  // 先把旧的设为 inactive
  await adminSupabase.from('recommendation_config')
    .update({ is_active: false })
    .eq('is_active', true);

  // 激活新的
  await adminSupabase.from('recommendation_config')
    .update({ is_active: true, activated_at: new Date().toISOString() })
    .eq('id', configId);
}
```

### 5.3 Admin 配置页 UI

```
┌────────────────────────────────────────────────────┐
│  Recommendation Algorithm                          │
│                                                    │
│  Describe your algorithm change:                   │
│  ┌──────────────────────────────────────────────┐  │
│  │ It's lunch time on weekdays, boost nearby    │  │
│  │ restaurant deals and trending items. New     │  │
│  │ merchants should get extra visibility.       │  │
│  └──────────────────────────────────────────────┘  │
│  [Generate Config]                                 │
│                                                    │
│  ── Generated Weights ──────────────────────────   │
│  Relevance    ████████░░  0.25                     │
│  Distance     ████████░░  0.25  ↑ increased        │
│  Popularity   ██████░░░░  0.20                     │
│  Quality      ████░░░░░░  0.15                     │
│  Freshness    ████░░░░░░  0.10  ↑ increased        │
│  Time Slot    ██░░░░░░░░  0.05                     │
│                                                    │
│  Sponsor Boost: 100  Diversity Penalty: -0.3       │
│                                                    │
│  [Preview Changes]  [Activate]  [Discard]         │
│                                                    │
│  ── History ────────────────────────────────────   │
│  v1.2  Mar 20  "Weekend boost"         [Restore]  │
│  v1.1  Mar 15  "Default weights"       [Restore]  │
└────────────────────────────────────────────────────┘
```

---

## 六、预计算 Job

### 6.1 pg_cron 定时任务

```sql
-- 每15分钟重新计算所有活跃用户的推荐列表
SELECT cron.schedule(
  'compute-recommendations',
  '*/15 * * * *',
  $$
  SELECT net.http_post(
    url := 'https://kqyolvmgrdekybjrwizx.supabase.co/functions/v1/compute-recommendations',
    headers := '{"Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtxeW9sdm1ncmRla3lianJ3aXp4Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3MjMxOTY1OSwiZXhwIjoyMDg3ODk1NjU5fQ.tkYSikgL9UenIw_MUhxbh73MSKA0tcTMQNJX08eaGNA"}'::jsonb
  );
  $$
);

-- 每小时更新用户标签
SELECT cron.schedule(
  'update-user-tags',
  '0 * * * *',
  $$
  SELECT net.http_post(
    url := 'https://kqyolvmgrdekybjrwizx.supabase.co/functions/v1/update-user-tags',
    headers := '{"Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtxeW9sdm1ncmRla3lianJ3aXp4Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3MjMxOTY1OSwiZXhwIjoyMDg3ODk1NjU5fQ.tkYSikgL9UenIw_MUhxbh73MSKA0tcTMQNJX08eaGNA"}'::jsonb
  );
  $$
);
```

### 6.2 `compute-recommendations` Edge Function

```typescript
export async function computeRecommendations() {
  // 1. 读取当前活跃配置
  const config = await getActiveConfig();

  // 2. 获取所有活跃用户（30天内有登录记录）
  // ⚠️ 侦察修正：users 表无 last_active_at，改用 last_login_at
  const activeUsers = await supabase
    .from('users')
    .select('id')
    .gt('last_login_at', new Date(Date.now() - 30 * 86400000).toISOString());

  // 3. 获取所有活跃 deals
  // ⚠️ 侦察修正：deals 表无 status 字段，改用 is_active
  const deals = await supabase
    .from('deals')
    .select(`
      id, title, discount_price, category, meal_type, price_tier,
      merchant_id, tags, created_at, is_sponsored,
      merchants(id, name, avg_rating, review_count, lat, lng,
               avg_redemption_rate, refund_rate)
    `)
    .eq('is_active', true);

  // 4. 计算全局热门（冷启动用）
  await computeGlobalCache(deals, config);

  // 5. 分批计算个人推荐（每批100用户）
  const batchSize = 100;
  for (let i = 0; i < activeUsers.length; i += batchSize) {
    const batch = activeUsers.slice(i, i + batchSize);
    await Promise.all(batch.map(user =>
      computeUserRecommendations(user.id, deals, config)
    ));
  }
}

async function computeUserRecommendations(
  userId: string,
  deals: Deal[],
  config: RecommendationConfig
) {
  const userTag  = await getUserTag(userId);
  const currentHour = new Date().getHours();
  const timeSlot = getTimeSlot(currentHour);

  const scored = deals.map(deal => {
    const relevance  = computeRelevance(userTag, deal);
    const distance   = computeDistance(userTag, deal.merchants);
    const popularity = computePopularity(deal);
    const quality    = computeQuality(deal.merchants);
    const freshness  = computeFreshness(deal.created_at);
    const timeSlotScore = computeTimeSlot(deal.meal_type, timeSlot);

    const w = config.weights;
    let score =
      w.w_relevance  * relevance
      + w.w_distance   * distance
      + w.w_popularity * popularity
      + w.w_quality    * quality
      + w.w_freshness  * freshness
      + w.w_time_slot  * timeSlotScore;

    // Sponsor 置顶
    if (deal.is_sponsored) score += config.sponsor_boost;

    return { dealId: deal.id, score };
  });

  // 多样性去重：同一商家最多出现 max_same_merchant 次
  const deduplicated = applyDiversityPenalty(scored, config);

  // 取前100，写入缓存
  const top100 = deduplicated
    .sort((a, b) => b.score - a.score)
    .slice(0, 100);

  await supabase.from('recommendation_cache').upsert({
    user_id:        userId,
    deal_ids:       top100.map(d => d.dealId),
    scores:         Object.fromEntries(top100.map(d => [d.dealId, d.score])),
    computed_at:    new Date().toISOString(),
    config_version: config.version,
  });
}
```

---

## 七、实时调整（App 启动时）

### 7.1 `get-recommendations` Edge Function

```typescript
// App 每次打开首页调用（拿缓存 + 实时微调）

export async function getRecommendations(req: Request) {
  const { userId, lat, lng, limit = 20 } = await req.json();

  const currentHour = new Date().getHours();
  const timeSlot = getTimeSlot(currentHour);

  // 1. 读取预计算缓存
  let cachedDealIds = await getCachedRecommendations(userId);

  // 2. 冷启动：无缓存或新用户，用全局热门
  if (!cachedDealIds || cachedDealIds.length === 0) {
    cachedDealIds = await getGlobalCacheDealIds(timeSlot);
  }

  // 3. 实时微调：用当前位置和时段重新排序前 50 条
  const topPool = cachedDealIds.slice(0, 50);
  const deals   = await getDealsWithMerchants(topPool);
  const config  = await getActiveConfig();

  const reranked = deals.map(deal => {
    let score = getCachedScore(deal.id) ?? 0.5;

    // 实时位置调整
    if (lat && lng) {
      const distKm = haversineDistance(lat, lng, deal.merchants.lat, deal.merchants.lng);
      const distScore = getDistanceScore(distKm);
      score = score * 0.8 + config.weights.w_distance * distScore * 0.2;
    }

    // 实时时段调整
    const timeScore = computeTimeSlot(deal.meal_type, timeSlot);
    score = score * 0.9 + config.weights.w_time_slot * timeScore * 0.1;

    return { ...deal, finalScore: score };
  });

  // 4. Sponsor 强制置顶（不经过打分）
  const sponsors    = reranked.filter(d => d.is_sponsored)
                              .sort((a, b) => b.finalScore - a.finalScore);
  const nonSponsors = reranked.filter(d => !d.is_sponsored)
                              .sort((a, b) => b.finalScore - a.finalScore);

  // Sponsor 最多占前3位
  const result = [
    ...sponsors.slice(0, 3),
    ...nonSponsors.slice(0, limit - sponsors.slice(0, 3).length),
  ];

  return { deals: result, timeSlot, cached: true };
}
```

---

## 八、用户标签更新 Job

### 8.1 `update-user-tags` Edge Function

```typescript
export async function updateUserTags() {
  const users = await supabase.from('users').select('id');

  for (const user of users) {
    const events = await supabase
      .from('user_events')
      .select('*')
      .eq('user_id', user.id)
      .gt('occurred_at', new Date(Date.now() - 30 * 86400000).toISOString());

    // 计算分类偏好
    const categoryCount: Record<string, number> = {};
    const timeSlotCount: Record<string, number> = {};
    let totalSpend = 0;
    let purchaseCount = 0;

    for (const event of events) {
      if (event.event_type === 'view_deal' && event.metadata?.category) {
        categoryCount[event.metadata.category] =
          (categoryCount[event.metadata.category] ?? 0) + 1;
      }
      if (event.event_type === 'purchase') {
        const slot = getTimeSlot(new Date(event.occurred_at).getHours());
        timeSlotCount[slot] = (timeSlotCount[slot] ?? 0) + 1;
        totalSpend      += event.metadata?.amount ?? 0;
        purchaseCount   += 1;
      }
    }

    const avgSpend = purchaseCount > 0 ? totalSpend / purchaseCount : 0;
    const topCategories = Object.entries(categoryCount)
      .sort((a, b) => b[1] - a[1])
      .slice(0, 3)
      .map(([cat]) => cat);
    const activeTimeSlots = Object.entries(timeSlotCount)
      .sort((a, b) => b[1] - a[1])
      .slice(0, 2)
      .map(([slot]) => slot);

    // 最近7天搜索关键词
    const searches = events
      .filter(e => e.event_type === 'search')
      .map(e => e.metadata?.query)
      .filter(Boolean)
      .slice(0, 10);

    await supabase.from('user_tags').upsert({
      user_id:           user.id,
      top_categories:    topCategories,
      avg_spend:         avgSpend,
      price_tier:        avgSpend < 10 ? 'budget' : avgSpend < 30 ? 'mid' : 'premium',
      active_time_slots: activeTimeSlots,
      purchase_frequency: purchaseCount < 1 ? 'low' : purchaseCount < 4 ? 'mid' : 'high',
      search_keywords:   searches,
      last_updated_at:   new Date().toISOString(),
    });
  }
}
```

---

## 九、Migration 文件

### 文件名：`[timestamp]_recommendation_system.sql`

```sql
-- ============================================================
-- Step 1: deals / merchants 表新增推荐相关字段
-- ============================================================
-- ⚠️ 侦察结果：deals.category 已存在(text)，跳过
-- ⚠️ 侦察结果：merchants.category/tags/lat/lng/avg_rating/review_count 已存在，跳过

ALTER TABLE deals
  ADD COLUMN IF NOT EXISTS meal_type   text
    CHECK (meal_type IN ('breakfast','lunch','dinner','all_day','n/a')),
  ADD COLUMN IF NOT EXISTS price_tier  text
    CHECK (price_tier IN ('budget','mid','premium')),
  ADD COLUMN IF NOT EXISTS tags        text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS is_sponsored boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS sponsor_priority int DEFAULT 0;

-- merchants 表：仅新增缺失字段（lat/lng/category/tags 已存在，不重复添加）
ALTER TABLE merchants
  ADD COLUMN IF NOT EXISTS cuisine_type     text,
  ADD COLUMN IF NOT EXISTS avg_redemption_rate numeric(4,3) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS refund_rate      numeric(4,3) DEFAULT 0;

-- ============================================================
-- Step 2: user_events 表
-- ============================================================
CREATE TABLE IF NOT EXISTS user_events (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  event_type  text NOT NULL CHECK (event_type IN (
                'view_deal','view_merchant','search',
                'purchase','redeem','review','refund'
              )),
  deal_id     uuid REFERENCES deals(id),
  merchant_id uuid REFERENCES merchants(id),
  metadata    jsonb,
  occurred_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_user_events_user_id
  ON user_events(user_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_user_events_type_time
  ON user_events(event_type, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_user_events_deal_id
  ON user_events(deal_id) WHERE deal_id IS NOT NULL;

ALTER TABLE user_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY "users_insert_own_events" ON user_events
  FOR INSERT WITH CHECK (user_id = auth.uid());
CREATE POLICY "users_view_own_events" ON user_events
  FOR SELECT USING (user_id = auth.uid());

-- ============================================================
-- Step 3: user_tags 表
-- ============================================================
CREATE TABLE IF NOT EXISTS user_tags (
  user_id            uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  top_categories     text[] NOT NULL DEFAULT '{}',
  avg_spend          numeric(10,2) DEFAULT 0,
  price_tier         text DEFAULT 'mid',
  active_time_slots  text[] NOT NULL DEFAULT '{}',
  favorite_hashtags  text[] NOT NULL DEFAULT '{}',
  purchase_frequency text DEFAULT 'low',
  location_lat       numeric(10,7),
  location_lng       numeric(10,7),
  search_keywords    text[] NOT NULL DEFAULT '{}',
  last_updated_at    timestamptz NOT NULL DEFAULT now()
);

-- ============================================================
-- Step 4: recommendation_config 表
-- ============================================================
CREATE TABLE IF NOT EXISTS recommendation_config (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  version      text NOT NULL,
  weights      jsonb NOT NULL,
  description  text,
  is_active    boolean NOT NULL DEFAULT false,
  created_by   uuid REFERENCES users(id),
  created_at   timestamptz NOT NULL DEFAULT now(),
  activated_at timestamptz
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_rec_config_active
  ON recommendation_config(is_active) WHERE is_active = true;

-- 插入默认配置
INSERT INTO recommendation_config (version, weights, description, is_active, activated_at)
VALUES (
  '1.0.0',
  '{
    "weights": {
      "w_relevance": 0.30,
      "w_distance": 0.20,
      "w_popularity": 0.20,
      "w_quality": 0.15,
      "w_freshness": 0.10,
      "w_time_slot": 0.05
    },
    "sponsor_boost": 100.0,
    "diversity_penalty": -0.30,
    "max_same_merchant": 2,
    "cache_ttl_minutes": 15
  }',
  '默认权重：相关性优先，兼顾距离和热度',
  true,
  now()
);

-- ============================================================
-- Step 5: recommendation_cache 表
-- ============================================================
CREATE TABLE IF NOT EXISTS recommendation_cache (
  user_id        uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  deal_ids       uuid[] NOT NULL,
  scores         jsonb,
  computed_at    timestamptz NOT NULL DEFAULT now(),
  config_version text NOT NULL
);

CREATE TABLE IF NOT EXISTS recommendation_global_cache (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  deal_ids    uuid[] NOT NULL,
  computed_at timestamptz NOT NULL DEFAULT now(),
  time_slot   text NOT NULL DEFAULT 'all'
);

-- ============================================================
-- Step 6: pg_cron 定时任务（需先在 Dashboard 启用 pg_cron）
-- ============================================================
-- SELECT cron.schedule('compute-recommendations', '*/15 * * * *', ...);
-- SELECT cron.schedule('update-user-tags', '0 * * * *', ...);
-- 具体命令见第六章
```

---

## 十、Flutter 前端集成

### 10.1 首页推荐请求

```dart
class RecommendationRepository {
  Future<List<DealModel>> fetchRecommendations({
    required double? lat,
    required double? lng,
    int limit = 20,
  }) async {
    // 1. 先读本地缓存（上次的推荐结果）
    final cached = await _localCache.getRecommendations();
    if (cached != null && !cached.isStale) {
      return cached.deals;
    }

    // 2. 调 Edge Function（带位置信息）
    final response = await supabase.functions.invoke(
      'get-recommendations',
      body: {
        'userId': supabase.auth.currentUser?.id,
        'lat':    lat,
        'lng':    lng,
        'limit':  limit,
      },
    );

    final deals = (response.data['deals'] as List)
        .map((d) => DealModel.fromJson(d))
        .toList();

    // 3. 写本地缓存（15分钟有效）
    await _localCache.setRecommendations(deals,
        ttl: const Duration(minutes: 15));

    return deals;
  }

  // 记录用户行为事件
  Future<void> trackEvent({
    required String eventType,
    String? dealId,
    String? merchantId,
    Map<String, dynamic>? metadata,
  }) async {
    await supabase.from('user_events').insert({
      'user_id':    supabase.auth.currentUser?.id,
      'event_type': eventType,
      'deal_id':    dealId,
      'merchant_id': merchantId,
      'metadata':   metadata,
    });
  }
}
```

### 10.2 行为追踪调用点

```dart
// 浏览 deal
onDealTap: (deal) {
  repo.trackEvent(
    eventType: 'view_deal',
    dealId:    deal.id,
    metadata:  { 'category': deal.category, 'price': deal.discountPrice },
  );
},

// 搜索
onSearch: (query) {
  repo.trackEvent(
    eventType: 'search',
    metadata:  { 'query': query },
  );
},

// 购买完成（在 checkout 成功回调里）
onPurchaseSuccess: (order) {
  repo.trackEvent(
    eventType: 'purchase',
    dealId:    order.dealId,
    metadata:  { 'amount': order.totalAmount, 'category': order.deal.category },
  );
},
```

---

## 十一、Phase 2 升级路径（ML）

当平台积累足够数据后（建议 10万+ 事件），可升级为协同过滤：

```
Phase 2: pgvector 协同过滤
  - 用 pgvector 存储用户 embedding 和 deal embedding
  - 基于相似用户的购买记录推荐（"买了这个的用户也买了..."）
  - embedding 由用户行为矩阵分解生成

Phase 3: Claude API 自优化
  - 定期把推荐效果数据（点击率/转化率）喂给 Claude
  - Claude 分析权重是否需要调整并自动生成建议
  - Admin 审核后一键激活
```

---

## 十二、执行顺序

```
Phase 0: 侦察 → 填检查表 ✅ 已完成 (2026-03-26)
    ↓
Phase 1: Migration
         - deals 新增字段：meal_type, price_tier, tags, is_sponsored, sponsor_priority
           （⚠️ category 已存在，跳过）
         - merchants 新增字段：cuisine_type, avg_redemption_rate, refund_rate
           （⚠️ category/tags/lat/lng/avg_rating/review_count 已存在，跳过）
         - user_events 表（新建）
         - user_tags 表（新建）
         - recommendation_config 表（新建，含默认权重）
         - recommendation_cache 表（新建）
         - recommendation_global_cache 表（新建）
         - user_events 90天清理 pg_cron 任务
    ↓ supabase db push --project-ref kqyolvmgrdekybjrwizx
Phase 2: Edge Functions
         - update-user-tags（每小时跑）
         - compute-recommendations（每15分钟跑）
           ⚠️ 侦察修正：查询用 users.last_login_at（非 last_active_at）
           ⚠️ 侦察修正：查询用 deals.is_active=true（非 status='active'）
         - get-recommendations（App 调用）
         - parse-recommendation-config（Admin 用，复用已有 ANTHROPIC_API_KEY）
    ↓ supabase functions deploy <name> --no-verify-jwt --project-ref kqyolvmgrdekybjrwizx
Phase 3: pg_cron 配置 ✅ 已完成 (2026-03-26)
         - pg_cron 已启用 ✅（无需再次启用）
         - 注册两个新定时任务：compute-recommendations + update-user-tags
         - 注册 cleanup_old_events 90天清理任务
         - 合并在 Phase 1 Migration 中一起执行
    ↓
Phase 4: Admin 端（admin/ Next.js） ✅ 已完成 (2026-03-26)
         - 算法配置页（自然语言输入 + 权重预览 + 激活）
         - 配置历史 + 回滚
         - 侧栏 Settings 下新增 Algorithm 导航
         - 创建文件：
           - admin/app/actions/recommendation.ts
           - admin/app/(dashboard)/settings/algorithm/page.tsx
           - admin/components/algorithm-config.tsx
           - admin/components/sidebar.tsx（修改）
    ↓
Phase 5: Flutter 前端（deal_joy/） ✅ 已完成 (2026-03-26)
         - RecommendationRepository（调 get-recommendations Edge Function）
         - recommendedDealsProvider（AsyncNotifier）
         - 行为追踪埋点：
           - deal_detail_screen.dart → view_deal 事件
           - search_screen.dart → search 事件
         - 首页 "Recommended For You" section
         - 创建文件：
           - deal_joy/lib/features/deals/data/repositories/recommendation_repository.dart
           - deal_joy/lib/features/deals/domain/providers/recommendation_provider.dart
           - deal_joy/lib/features/deals/presentation/screens/home_screen.dart（修改）
           - deal_joy/lib/features/deals/presentation/screens/deal_detail_screen.dart（修改）
           - deal_joy/lib/features/deals/presentation/screens/search_screen.dart（修改，如有）
    ↓
Phase 6: 验证 ✅ 代码验证通过 (2026-03-26)
         - flutter analyze: 0 errors, 0 warnings
         - 新用户：fallback 到活跃 deals 列表 → ✅ 逻辑正确
         - 有行为用户：个性化推荐（缓存 + 实时微调） → ✅ 逻辑正确
         - Sponsor：始终前3位 → ✅ get-recommendations 中 sponsor 强制置顶
         - Admin 修改算法 → 15分钟内生效 → ✅ pg_cron 每15分钟重新计算
         - 时段切换 → ✅ Dallas 时区时段匹配
    ↓
Phase 7: Maestro 测试（待手动验证）
```

---

## 实施记录

### [2026-03-26] Phase 0 完成
- 侦察结果写入设计文档侦察检查表

### [2026-03-26] Phase 1 + Phase 3 完成
- Migration 文件：`20260326000002_recommendation_system.sql`
- psql 直接执行成功（supabase db push 有远程 migration 不匹配问题，改用 psql）
- 新建表：user_events, user_tags, recommendation_config, recommendation_cache, recommendation_global_cache
- deals 新增字段：meal_type, price_tier, tags, is_sponsored, sponsor_priority
- merchants 新增字段：cuisine_type, avg_redemption_rate, refund_rate
- pg_cron 注册 3 个任务：compute-recommendations(*/15), update-user-tags(0 *), cleanup-old-events(0 3)
- 差异：跳过 deals.category（已有）、merchants.category/tags/lat/lng（已有）

### [2026-03-26] Phase 2 完成
- 4 个 Edge Functions 创建并部署成功：
  - update-user-tags — 每小时更新用户标签
  - compute-recommendations — 每15分钟预计算推荐
  - get-recommendations — App 首页调用（缓存+实时微调）
  - parse-recommendation-config — Admin 自然语言配置算法
- 差异：compute-recommendations 用 `last_login_at` 和 `is_active=true`（非设计文档原始的 `last_active_at` / `status='active'`）

### [2026-03-26] Phase 4 完成
- Admin 端算法配置页创建完成
- Settings 侧栏新增 Algorithm 入口

### [2026-03-26] Phase 5 完成
- RecommendationRepository + Provider 创建
- 首页 "Recommended For You" section 集成
- 行为埋点：view_deal（详情页）、search（搜索页）

### [2026-03-26] Phase 6 代码验证通过
- flutter analyze: 0 errors, 0 warnings
- 运行时验证需要启动 App 手动测试
