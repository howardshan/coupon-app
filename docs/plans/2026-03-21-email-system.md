# CrunchyPlum 邮件系统开发计划书

> **创建日期：** 2026-03-21
> **最后更新：** 2026-03-21（v3 — 品牌改名 DealJoy → CrunchyPlum）
> **发件域名：** crunchyplum.com
> **邮件服务商：** SMTP2GO
> **邮件内容语言：** 英文（面向北美 Dallas 市场）
> **状态：** 开发中

> ⚠️ **品牌变更说明（2026-03-21）：** 项目已因版权/法律原因从 **DealJoy** 正式更名为 **CrunchyPlum**。
> 所有面向用户的邮件内容（subject、HTML body、FROM 名称、Logo 文字、页脚）均已更新为 CrunchyPlum。
> 代码内部目录名（`deal_joy/`）、变量名、数据库表名维持不变。

---

## 1. 现状与目标

### 现状

| 模块 | 现状 |
|------|------|
| 业务邮件 | 无，仅 Supabase Auth 内置验证邮件 |
| 业务通知 | `merchant_notifications` 表（仅应用内通知，无邮件） |
| Auth 邮件 | Supabase 默认模板（计划替换为品牌模板） |
| Edge Functions | 共 29 个，零 SMTP 集成 |
| 后台管理端 | Next.js 15 App Router（`admin/` 目录） |

### 目标

1. 用品牌化 crunchyplum.com 模板替换 Supabase Auth 默认邮件
2. 构建覆盖三端（客户端、商家端、后台管理端）的完整业务邮件系统
3. 所有邮件通过 SMTP2GO 统一使用 `noreply@crunchyplum.com` 发出
4. 管理端可查看全部邮件发送记录（含邮件内容预览），并可管理全局邮件开关
5. 用户端与商家端可在各自设置中管理个人邮件接收偏好
6. 全局开关与用户偏好联动：全局关闭的邮件类型，对应端口的偏好选项自动隐藏
7. 通过 `email_logs` 表完整记录所有邮件发送历史（含 HTML 正文）
8. 异步非阻塞——邮件发送失败绝不影响核心业务流程

---

## 2. 系统架构

### 发送链路

```
触发来源                      发送工具                      SMTP2GO
────────────────              ───────────────               ────────
Edge Function         →       _shared/email.ts        →    SMTP2GO REST API
                                                            (api.smtp2go.com/v3)
Admin Server Action   →       admin/lib/email.ts      →        ↓
Cron Edge Function    →       _shared/email.ts        →    email_logs (DB)
Supabase Auth Hook    →       send-auth-email（新建）  →
```

### 发送前双重权限检查

每封邮件发送前必须依次通过以下两道检查，任意一道不通过则跳过发送：

```
sendEmail() 调用
       ↓
① 全局开关检查
   查 email_type_settings.global_enabled
   → false：终止，不发送，不记录日志
       ↓
② 用户/商家偏好检查（仅适用于 user_configurable = true 的邮件类型）
   查 user_email_preferences / merchant_email_preferences
   → 用户已关闭：终止，不发送
       ↓
③ 幂等性检查
   查 email_logs 过去 24h 内是否已成功发送
   → 已发送：跳过
       ↓
④ 调用 SMTP2GO API 发送
   → 写入 email_logs（含 html_body）
```

### 核心设计原则

1. **双工具分离**：Edge Functions 使用 `_shared/email.ts`；Admin Next.js Server Actions 使用 `admin/lib/email.ts`。两者调用同一 SMTP2GO 接口，共享模板逻辑。
2. **即发即忘**：`sendEmail()` 包裹在 try/catch 中——发送失败只记录日志，不向上抛出异常。
3. **全局开关优先**：管理员在后台关闭某类邮件后，无论用户偏好如何，该类邮件一律停发。
4. **用户偏好可选**：仅 `user_configurable = true` 的邮件类型才会受用户偏好影响；密码重置、认证结果等关键邮件强制发送。
5. **UI 联动**：用户/商家设置页面加载时，仅展示 `global_enabled = true` 的邮件偏好选项，全局关闭的类型直接隐藏（而非置灰）。
6. **内容存档**：`email_logs` 表记录每封邮件的 `html_body`，管理员可在后台点击任意记录预览实际邮件内容。

### 新增文件结构

```
deal_joy/supabase/functions/
├── _shared/
│   ├── email.ts                                ← 新建：发送工具（含双重权限检查）
│   └── email-templates/
│       ├── base-layout.ts                      ← 新建：公共 HTML 头部/底部布局
│       ├── customer/
│       │   ├── welcome.ts                      ← C1
│       │   ├── order-confirmation.ts           ← C2
│       │   ├── coupon-redeemed.ts              ← C3
│       │   ├── coupon-expiring.ts              ← C4
│       │   ├── auto-refund.ts                  ← C5
│       │   ├── store-credit-added.ts           ← C6
│       │   ├── refund-requested.ts             ← C7
│       │   ├── refund-completed.ts             ← C8
│       │   ├── after-sales-submitted.ts        ← C9
│       │   ├── after-sales-approved.ts         ← C10
│       │   ├── after-sales-rejected.ts         ← C11
│       │   └── after-sales-merchant-replied.ts ← C13
│       ├── merchant/
│       │   ├── welcome.ts                      ← M1
│       │   ├── verification-pending.ts         ← M2
│       │   ├── verification-approved.ts        ← M3
│       │   ├── verification-rejected.ts        ← M4
│       │   ├── new-order.ts                    ← M5
│       │   ├── deal-expiring.ts                ← M6
│       │   ├── coupon-redeemed.ts              ← M7
│       │   ├── pre-redemption-refund.ts        ← M8
│       │   ├── after-sales-received.ts         ← M9
│       │   ├── after-sales-approved.ts         ← M10
│       │   ├── after-sales-rejected-escalated.ts ← M11
│       │   ├── platform-review-result.ts       ← M12
│       │   ├── monthly-settlement.ts           ← M13
│       │   ├── withdrawal-received.ts          ← M14
│       │   ├── withdrawal-completed.ts         ← M15
│       │   └── deal-rejected.ts                ← M16
│       └── admin/
│           ├── merchant-application.ts         ← A2
│           ├── after-sales-escalated.ts        ← A5
│           ├── after-sales-closed.ts           ← A6
│           ├── large-refund-alert.ts           ← A4
│           ├── withdrawal-request.ts           ← A7
│           └── daily-digest.ts                 ← A3
├── send-auth-email/                            ← 新建：替换 Supabase Auth 邮件
├── notify-expiring-coupons/                    ← 新建：Cron Job（C4）
├── notify-expiring-deals/                      ← 新建：Cron Job（M6）
├── monthly-settlement-report/                  ← 新建：Cron Job（M13）
└── admin-daily-digest/                         ← 新建：Cron Job（A3）

admin/lib/
└── email.ts                                    ← 新建：Next.js Server Actions 发送工具
```

---

## 3. 数据库变更（共新增 4 张表）

### 3.1 `email_type_settings` 表（全局邮件开关 + 管理员收件人配置）

> 覆盖全部 37 种邮件类型（C/M/A 系列），替代原 `admin_notification_settings` 设计。

```sql
-- Migration: 20260321000001_email_system.sql

CREATE TABLE email_type_settings (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email_code       TEXT NOT NULL UNIQUE,   -- 'C1', 'C2', ... 'M1', ... 'A1'
  email_name       TEXT NOT NULL,          -- 人类可读名称
  recipient_type   TEXT NOT NULL CHECK (recipient_type IN ('customer', 'merchant', 'admin')),
  -- 全局开关：管理员控制，关闭后该类邮件完全停发
  global_enabled   BOOLEAN NOT NULL DEFAULT TRUE,
  -- 是否允许用户/商家在个人设置中自主关闭
  user_configurable BOOLEAN NOT NULL DEFAULT TRUE,
  -- 仅 A 系列使用：管理员通知收件人列表
  admin_recipient_emails JSONB DEFAULT '[]',
  description      TEXT,
  updated_at       TIMESTAMPTZ DEFAULT NOW(),
  updated_by       UUID REFERENCES users(id)
);

-- 预置全部 37 种邮件类型
-- C 系列（客户端）
INSERT INTO email_type_settings (email_code, email_name, recipient_type, user_configurable) VALUES
  ('C1',  '注册欢迎邮件',           'customer', FALSE),  -- 关键，不可关闭
  ('C2',  '订单确认邮件',           'customer', FALSE),  -- 关键，不可关闭
  ('C3',  'Coupon 核销成功通知',     'customer', TRUE),
  ('C4',  'Coupon 即将到期提醒',     'customer', TRUE),
  ('C5',  '到期自动退款通知',        'customer', FALSE),  -- 退款关键通知，不可关闭
  ('C6',  'Store Credit 到账通知',  'customer', FALSE),
  ('C7',  '退款申请受理确认',        'customer', FALSE),
  ('C8',  'Stripe 退款到账通知',    'customer', FALSE),
  ('C9',  '售后申请提交确认',        'customer', FALSE),
  ('C10', '售后审核通过通知',        'customer', FALSE),
  ('C11', '售后审核拒绝通知',        'customer', FALSE),
  ('C12', '密码重置邮件',           'customer', FALSE),  -- 安全关键，不可关闭
  ('C13', '商家已回复售后通知',      'customer', TRUE);

-- M 系列（商家端）
INSERT INTO email_type_settings (email_code, email_name, recipient_type, user_configurable) VALUES
  ('M1',  '商家注册欢迎邮件',               'merchant', FALSE),
  ('M2',  '认证申请受理通知',               'merchant', FALSE),
  ('M3',  '商户认证通过通知',               'merchant', FALSE),
  ('M4',  '商户认证拒绝通知',               'merchant', FALSE),
  ('M5',  '新订单通知',                    'merchant', TRUE),
  ('M6',  'Deal 即将到期提醒',             'merchant', TRUE),
  ('M7',  'Coupon 核销成功通知',           'merchant', TRUE),
  ('M8',  '核销前退款通知',                'merchant', FALSE),
  ('M9',  '收到售后申请通知',              'merchant', FALSE),
  ('M10', '商家同意售后退款确认',           'merchant', FALSE),
  ('M11', '商家拒绝售后——升级平台通知',     'merchant', FALSE),
  ('M12', '平台最终裁决通知',              'merchant', FALSE),
  ('M13', '月度结算报告',                  'merchant', TRUE),
  ('M14', '提现申请受理通知',              'merchant', FALSE),
  ('M15', '提现完成通知',                  'merchant', FALSE),
  ('M16', 'Deal 被管理员驳回通知',         'merchant', FALSE);

-- A 系列（后台管理端）
INSERT INTO email_type_settings (email_code, email_name, recipient_type, user_configurable,
  admin_recipient_emails) VALUES
  ('A1', '管理员账户创建通知',         'admin', FALSE, '[]'),
  ('A2', '新商户认证申请提醒',         'admin', FALSE, '[]'),
  ('A3', '每日待处理任务汇总',         'admin', FALSE, '[]'),
  ('A4', '大额退款预警',              'admin', FALSE, '[]'),
  ('A5', '售后案件升级审核通知',       'admin', FALSE, '[]'),
  ('A6', '售后案件结案通知',          'admin', FALSE, '[]'),
  ('A7', '新提现申请审核通知',         'admin', FALSE, '[]'),
  ('A8', '系统异常告警邮件',          'admin', FALSE, '[]');

-- RLS：admin 角色可读写，其他角色只读（用于 UI 联动查询）
ALTER TABLE email_type_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "admin_write" ON email_type_settings
  FOR ALL USING (
    EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin')
  );
CREATE POLICY "authenticated_read" ON email_type_settings
  FOR SELECT USING (auth.role() = 'authenticated');
```

### 3.2 `email_logs` 表（邮件发送日志 + 内容存档）

```sql
CREATE TABLE email_logs (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recipient_email    TEXT NOT NULL,
  recipient_type     TEXT NOT NULL CHECK (recipient_type IN ('customer', 'merchant', 'admin')),
  email_code         TEXT NOT NULL,   -- 对应 email_type_settings.email_code
  -- 关联业务主键（order_id / order_item_id / merchant_id 等）
  reference_id       UUID,
  subject            TEXT NOT NULL,
  -- 存储实际发送的 HTML 正文，供管理端预览
  html_body          TEXT,
  status             TEXT NOT NULL DEFAULT 'pending'
                       CHECK (status IN ('pending', 'sent', 'failed', 'bounced')),
  smtp2go_message_id TEXT,
  error_message      TEXT,
  retry_count        INTEGER DEFAULT 0,
  sent_at            TIMESTAMPTZ,
  created_at         TIMESTAMPTZ DEFAULT NOW()
);

-- 幂等性检查索引
CREATE INDEX idx_email_logs_dedup
  ON email_logs (email_code, reference_id, recipient_email, created_at);

-- 管理端按类型/状态筛选索引
CREATE INDEX idx_email_logs_filter
  ON email_logs (recipient_type, email_code, status, created_at DESC);

-- RLS：service_role 写入；admin 角色可读全部
ALTER TABLE email_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "service_role_write" ON email_logs
  FOR ALL USING (auth.role() = 'service_role');
CREATE POLICY "admin_read" ON email_logs
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin')
  );
```

### 3.3 `user_email_preferences` 表（客户端邮件偏好）

```sql
CREATE TABLE user_email_preferences (
  user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  email_code TEXT NOT NULL,
  enabled    BOOLEAN NOT NULL DEFAULT TRUE,
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (user_id, email_code)
);

-- RLS：用户只能读写自己的偏好
ALTER TABLE user_email_preferences ENABLE ROW LEVEL SECURITY;
CREATE POLICY "user_own" ON user_email_preferences
  FOR ALL USING (auth.uid() = user_id);
```

### 3.4 `merchant_email_preferences` 表（商家端邮件偏好）

```sql
CREATE TABLE merchant_email_preferences (
  merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
  email_code  TEXT NOT NULL,
  enabled     BOOLEAN NOT NULL DEFAULT TRUE,
  updated_at  TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (merchant_id, email_code)
);

-- RLS：商家只能读写自己的偏好
ALTER TABLE merchant_email_preferences ENABLE ROW LEVEL SECURITY;
CREATE POLICY "merchant_own" ON merchant_email_preferences
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM merchants
      WHERE id = merchant_id AND user_id = auth.uid()
    )
  );
```

---

## 4. 邮件完整清单

### 邮件类型说明

- **`user_configurable = ✓`**：用户/商家可在个人设置中自主开启/关闭
- **`user_configurable = ✗`**：强制发送，不允许用户关闭（安全、交易、合规类邮件）

### 4.1 客户端邮件（C 系列）

| 编号 | 邮件名称 | 触发时机 | 触发位置 | 用户可关闭 | 关键内容 |
|------|---------|---------|---------|-----------|---------|
| C1 | 注册欢迎邮件 | 用户完成邮箱验证 | `send-auth-email` | ✗ | 用户名、App 下载链接 |
| C2 | 订单确认邮件 | 订单创建成功 | `create-order-v3` | ✗ | 订单号、Deal 列表、金额、各券到期日 |
| C3 | Coupon 核销成功通知 | 商家完成扫码核销 | `merchant-scan` | ✓ | 商家名称、Deal 名称、核销时间、门店地址 |
| C4 | Coupon 即将到期提醒 | 到期前 3 天 | `notify-expiring-coupons`（Cron） | ✓ | Deal 名称、到期日期、退款政策说明 |
| C5 | 到期自动退款通知 | `auto-refund-expired` 执行 | `auto-refund-expired` | ✗ | 退款金额、退款方式（Store Credit）、到账后余额 |
| C6 | Store Credit 余额到账通知 | 任何 Store Credit 退款成功 | `create-refund` / `auto-refund-expired` | ✗ | 本次到账金额、当前余额、使用说明 |
| C7 | 退款申请受理确认 | `create-refund` 受理成功 | `create-refund` | ✗ | 订单号、退款金额、方式、预计到账时间 |
| C8 | Stripe 退款到账通知 | `stripe-webhook` charge.refunded | `stripe-webhook` | ✗ | 退款金额、银行卡末四位、3-5 个工作日说明 |
| C9 | 售后申请提交确认 | 售后请求创建成功 | `after-sales-request` | ✗ | 申请编号、原因、7 天审核承诺、客服邮箱 |
| C10 | 售后审核通过通知 | 平台批准退款 | `platform-after-sales` | ✗ | 退款金额、方式、处理时间 |
| C11 | 售后审核拒绝通知 | 平台拒绝申请 | `platform-after-sales` | ✗ | 拒绝原因、申诉渠道、客服联系方式 |
| C12 | 密码重置邮件 | 用户申请重置密码 | Supabase Auth 自定义模板 | ✗ | 重置链接（1 小时内有效） |
| C13 | 商家已回复售后通知 | 商家提交售后处理意见 | `merchant-after-sales` | ✓ | 商家回复内容、案件当前状态、后续步骤 |

### 4.2 商家端邮件（M 系列）

| 编号 | 邮件名称 | 触发时机 | 触发位置 | 商家可关闭 | 关键内容 |
|------|---------|---------|---------|-----------|---------|
| M1 | 商家注册欢迎邮件 | 注册提交成功 | `merchant-register` | ✗ | 商家名称、认证流程说明、Dashboard 链接 |
| M2 | 认证申请受理通知 | 材料上传进入审核 | `merchant-register` | ✗ | 申请编号、预计审核时间（1-3 个工作日） |
| M3 | 商户认证通过通知 | 管理员审核通过 | `approveMerchant` | ✗ | 已开通功能、免佣期截止日、Dashboard 链接 |
| M4 | 商户认证拒绝通知 | 管理员审核拒绝 | `rejectMerchant` | ✗ | 拒绝原因、需补充材料、重新提交链接 |
| M5 | 新订单通知 | 涉及该商家的订单创建 | `create-order-v3` | ✓ | 订单号、Deal 名称、数量、券到期日 |
| M6 | Deal 即将到期提醒 | 到期前 7 天 | `notify-expiring-deals`（Cron） | ✓ | Deal 名称、到期日、已售数量、未核销数量 |
| M7 | Coupon 核销成功通知 | 扫码核销完成 | `merchant-scan` | ✓ | 脱敏券码、Deal 名称、核销金额、今日累计核销 |
| M8 | 核销前退款通知 | 客户主动退回未使用券 | `create-refund` | ✗ | 订单号、退款金额、可用库存变更 |
| M9 | 收到售后申请通知 | 客户提交售后请求 | `after-sales-request` | ✗ | 申请编号、客户原因、证据说明、48 小时处理期限 |
| M10 | 商家同意售后退款确认 | 商家批准退款 | `merchant-after-sales` | ✗ | 申请编号、退款金额、已通知客户确认 |
| M11 | 商家拒绝售后——升级平台 | 商家拒绝，案件升级 | `merchant-after-sales` | ✗ | 申请编号、拒绝原因、平台 3 个工作日复核说明 |
| M12 | 平台最终裁决通知 | 平台做出最终决定 | `platform-after-sales` | ✗ | 最终决定、原因、对商家收益的影响 |
| M13 | 月度结算报告 | 每月 1 日 | `monthly-settlement-report`（Cron） | ✓ | 上月核销总额、退款额、净收益、佣金、应结算金额 |
| M14 | 提现申请受理通知 | 商家提交提现申请 | `merchant-withdrawal` | ✗ | 提现金额、银行账户末四位、预计处理时间 |
| M15 | 提现完成通知 | 管理员标记提现完成 | Admin 操作触发 | ✗ | 到账金额、交易流水号 |
| M16 | Deal 被管理员驳回通知 | 管理员驳回已提交 Deal | `rejectDeal` | ✗ | Deal 名称、驳回原因、需修改内容、重新提交链接 |

### 4.3 后台管理端邮件（A 系列）

> A 系列收件人在 Admin Dashboard **设置 → 邮件通知** 页面中配置（`email_type_settings.admin_recipient_emails`）。

| 编号 | 邮件名称 | 触发时机 | 触发位置 | 关键内容 |
|------|---------|---------|---------|---------|
| A1 | 管理员账户创建通知 | 新管理员账户创建 | Admin 操作 | 用户名、临时密码、Dashboard 登录链接 |
| A2 | 新商户认证申请提醒 | 商家提交注册材料 | `merchant-register` | 商家名称、提交时间、材料列表、Dashboard 审核链接 |
| A3 | 每日待处理任务汇总 | 每天 9:00 AM CT | `admin-daily-digest`（Cron） | 待审商户数、待处理售后数、待审提现数 |
| A4 | 大额退款预警 | 单笔退款超过 $500 | `create-refund` / `admin-refund` | 退款金额、用户 ID、订单号、人工复核提示 |
| A5 | 售后案件升级审核通知 | 商家拒绝，案件升级至平台 | `merchant-after-sales` | 申请编号、完整事件时间线、客户证据、商家拒绝理由 |
| A6 | 售后案件结案通知 | 平台做出最终裁决 | `platform-after-sales` | 案件编号、最终决定、审核人、摘要存档 |
| A7 | 新提现申请审核通知 | 商家提交提现申请 | `merchant-withdrawal` | 商家名称、提现金额、账户信息、Dashboard 审批链接 |
| A8 | 系统异常告警邮件 | Edge Function 捕获严重错误 | 各 Edge Function 错误处理器 | 错误类型、函数名、简化 Stack Trace、受影响用户/订单 |

---

## 5. 实现细节

### 5.1 `_shared/email.ts`（Edge Function 发送工具）

```typescript
// deal_joy/supabase/functions/_shared/email.ts

const SMTP2GO_API_URL = 'https://api.smtp2go.com/v3/email/send';
const FROM_NAME       = 'DealJoy';
const FROM_EMAIL      = 'noreply@crunchyplum.com';

export interface EmailPayload {
  to: string | string[];
  subject: string;
  htmlBody: string;
  textBody?: string;
  emailCode: string;           // 对应 email_type_settings.email_code，如 'C2'
  referenceId?: string;        // 关联业务 ID（UUID）
  recipientType: 'customer' | 'merchant' | 'admin';
  // 用于偏好检查（二选一）
  userId?: string;             // 客户端邮件传 user_id
  merchantId?: string;         // 商家端邮件传 merchant_id
}

export async function sendEmail(
  supabaseClient: SupabaseClient,
  payload: EmailPayload
): Promise<void> {
  // ① 全局开关检查
  const { data: setting } = await supabaseClient
    .from('email_type_settings')
    .select('global_enabled, user_configurable')
    .eq('email_code', payload.emailCode)
    .single();

  if (!setting?.global_enabled) return; // 全局关闭，直接终止

  const recipients = Array.isArray(payload.to) ? payload.to : [payload.to];

  for (const email of recipients) {
    // ② 用户/商家偏好检查（仅 user_configurable = true 的邮件类型）
    if (setting.user_configurable) {
      if (payload.userId) {
        const { data: pref } = await supabaseClient
          .from('user_email_preferences')
          .select('enabled')
          .eq('user_id', payload.userId)
          .eq('email_code', payload.emailCode)
          .maybeSingle();
        // 有明确记录且为 false 时才跳过；无记录则默认发送
        if (pref !== null && !pref.enabled) continue;
      }

      if (payload.merchantId) {
        const { data: pref } = await supabaseClient
          .from('merchant_email_preferences')
          .select('enabled')
          .eq('merchant_id', payload.merchantId)
          .eq('email_code', payload.emailCode)
          .maybeSingle();
        if (pref !== null && !pref.enabled) continue;
      }
    }

    // ③ 幂等性检查：24 小时内是否已成功发过同类邮件
    if (payload.referenceId) {
      const { data: existing } = await supabaseClient
        .from('email_logs')
        .select('id')
        .eq('email_code', payload.emailCode)
        .eq('reference_id', payload.referenceId)
        .eq('recipient_email', email)
        .eq('status', 'sent')
        .gte('created_at', new Date(Date.now() - 86400000).toISOString())
        .maybeSingle();
      if (existing) continue;
    }

    // ④ 写入 pending 日志（含 html_body）
    const { data: logRow } = await supabaseClient
      .from('email_logs')
      .insert({
        recipient_email: email,
        recipient_type:  payload.recipientType,
        email_code:      payload.emailCode,
        reference_id:    payload.referenceId ?? null,
        subject:         payload.subject,
        html_body:       payload.htmlBody,   // 存档邮件内容
        status:          'pending',
      })
      .select('id')
      .single();

    try {
      const response = await fetch(SMTP2GO_API_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          api_key:   Deno.env.get('SMTP2GO_API_KEY'),
          to:        [email],
          sender:    `${FROM_NAME} <${FROM_EMAIL}>`,
          subject:   payload.subject,
          html_body: payload.htmlBody,
          text_body: payload.textBody ?? '',
        }),
      });

      const result = await response.json();

      await supabaseClient.from('email_logs').update({
        status:             'sent',
        smtp2go_message_id: result?.data?.email_id ?? null,
        sent_at:            new Date().toISOString(),
      }).eq('id', logRow?.id);

    } catch (err) {
      // 静默失败，不向上抛出异常
      await supabaseClient.from('email_logs').update({
        status:        'failed',
        error_message: String(err),
        retry_count:   1,
      }).eq('id', logRow?.id);
    }
  }
}
```

### 5.2 `admin/lib/email.ts`（Next.js 发送工具）

```typescript
// admin/lib/email.ts

const SMTP2GO_API_URL = 'https://api.smtp2go.com/v3/email/send';

export interface AdminEmailPayload {
  to: string | string[];
  subject: string;
  htmlBody: string;
  emailCode: string;
  referenceId?: string;
}

// 从 email_type_settings 读取指定类型的全局开关状态
export async function isEmailEnabled(
  supabase: SupabaseClient,
  emailCode: string
): Promise<boolean> {
  const { data } = await supabase
    .from('email_type_settings')
    .select('global_enabled')
    .eq('email_code', emailCode)
    .single();
  return data?.global_enabled ?? false;
}

// 从 email_type_settings 读取 A 系列管理员收件人列表
export async function getAdminRecipients(
  supabase: SupabaseClient,
  emailCode: string
): Promise<string[]> {
  const { data } = await supabase
    .from('email_type_settings')
    .select('admin_recipient_emails, global_enabled')
    .eq('email_code', emailCode)
    .single();
  if (!data?.global_enabled) return [];
  return (data?.admin_recipient_emails as string[]) ?? [];
}

export async function sendAdminEmail(
  supabase: SupabaseClient,
  payload: AdminEmailPayload
): Promise<void> {
  // 全局开关检查
  const enabled = await isEmailEnabled(supabase, payload.emailCode);
  if (!enabled) return;

  try {
    await fetch(SMTP2GO_API_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        api_key:   process.env.SMTP2GO_API_KEY,
        to:        Array.isArray(payload.to) ? payload.to : [payload.to],
        sender:    'DealJoy <noreply@crunchyplum.com>',
        subject:   payload.subject,
        html_body: payload.htmlBody,
      }),
    });

    // 写入发送日志（含 html_body）
    const serviceSupabase = getServiceRoleClient();
    await serviceSupabase.from('email_logs').insert({
      recipient_email: Array.isArray(payload.to) ? payload.to[0] : payload.to,
      recipient_type:  'admin',
      email_code:      payload.emailCode,
      reference_id:    payload.referenceId ?? null,
      subject:         payload.subject,
      html_body:       payload.htmlBody,
      status:          'sent',
      sent_at:         new Date().toISOString(),
    });
  } catch {
    // 静默失败——邮件发送不阻断管理员操作
  }
}
```

### 5.3 邮件基础模板布局规范

所有邮件模板继承统一基础布局，包含：
- DealJoy 品牌 Logo（托管在 Supabase Storage）
- 品牌主色调配色
- 底部：退订说明、crunchyplum.com 地址、社交媒体链接
- 移动端自适应布局（最大宽度 600px，内联 CSS）
- 字体：`system-ui, -apple-system, sans-serif`

### 5.4 Supabase Auth 自定义邮件（C1、C12）

通过配置 SMTP2GO 的 SMTP 端点（推荐方式，确保所有邮件发件人一致性）：
- Dashboard → Authentication → SMTP Settings
- Host: `mail.smtp2go.com`，Port: `587`
- 同时在 Auth → Email Templates 中更新为品牌化 HTML 模板

### 5.5 新建 Cron Job Edge Functions

#### `notify-expiring-coupons`（每天 8:00 AM 美国中部时间）
```sql
-- 查询恰好 3 天后到期的未使用 order_items
SELECT oi.id, oi.order_id, o.user_id, u.email, u.full_name,
       d.title AS deal_title, c.expires_at, oi.unit_price
FROM order_items oi
JOIN orders o ON o.id = oi.order_id
JOIN users u ON u.id = o.user_id
JOIN deals d ON d.id = oi.deal_id
JOIN coupons c ON c.order_item_id = oi.id
WHERE oi.customer_status = 'unused'
  AND c.expires_at::date = CURRENT_DATE + INTERVAL '3 days'
  AND c.status = 'active';
```
发送 C4，通过 `email_logs` 去重，发送前检查用户偏好。

#### `notify-expiring-deals`（每天 9:00 AM 美国中部时间）
```sql
-- 查询恰好 7 天后到期的活跃 deals
SELECT d.id, d.title, d.expires_at, m.id AS merchant_id,
       m.name AS merchant_name, u.email AS merchant_email,
       COUNT(c.id) FILTER (WHERE c.status = 'active') AS unredeemed_count,
       COUNT(c.id) AS total_sold
FROM deals d
JOIN merchants m ON m.id = d.merchant_id
JOIN users u ON u.id = m.user_id
LEFT JOIN coupons c ON c.deal_id = d.id
WHERE d.is_active = true
  AND d.expires_at::date = CURRENT_DATE + INTERVAL '7 days'
GROUP BY d.id, m.id, m.name, u.email;
```
发送 M6，发送前检查商家偏好。

#### `monthly-settlement-report`（每月 1 日 6:00 AM 美国中部时间）
查询 `merchant_earnings` 视图获取上月数据，向每个活跃商家发送 M13。发送前检查商家偏好。

#### `admin-daily-digest`（每天 9:00 AM 美国中部时间）
查询各维度待处理数量，向 A3 配置的管理员收件人发送汇总邮件。

---

## 6. 现有 Edge Functions 改造清单

### Edge Functions

| 函数名 | 改动内容 | 新增邮件 |
|--------|---------|---------|
| `create-order-v3` | 订单创建成功后调用 `sendEmail()`，传入 `userId` 和 `merchantId` | C2、M5 |
| `merchant-scan` | 核销成功后调用 `sendEmail()`，传入 `userId` 和 `merchantId` | C3、M7 |
| `create-refund` | 按退款类型调用；超 $500 触发 A4 预警 | C6、C7、M8、A4 |
| `auto-refund-expired` | 每笔到期退款后调用 | C5、C6 |
| `stripe-webhook` | charge.refunded 事件时调用 | C8 |
| `after-sales-request` | 三方同时通知 | C9、M9、A5 |
| `merchant-after-sales` | 按批准/拒绝路径调用 | C13、M10、M11 |
| `platform-after-sales` | 平台最终裁决时通知三方 | C10、C11、M12、A6 |
| `merchant-register` | 注册成功后调用 | M1、M2、A2 |
| `merchant-withdrawal` | 提现申请提交后调用 | M14、A7 |

### Admin Server Actions

| Server Action | 改动内容 | 新增邮件 |
|---------------|---------|---------|
| `approveMerchant` | DB 更新后调用 `sendAdminEmail()` | M3 |
| `rejectMerchant` | DB 更新后调用 `sendAdminEmail()` | M4 |
| `rejectDeal` | DB 更新后调用 `sendAdminEmail()` | M16 |
| 新建：提现审批通过 action | 状态更新时调用 `sendAdminEmail()` | M15 |

---

## 7. Admin Dashboard 新增功能

### 7.1 新页面：`/settings/email-types`（全局邮件开关管理）

管理员可以：
- 查看全部 37 种邮件类型及其当前状态（全局开关 on/off）
- 一键切换任意邮件类型的全局开关
- 查看每种类型是否允许用户自主配置（`user_configurable`）
- 为 A 系列邮件配置收件人邮箱列表
- 修改后实时生效，所有后续发送立即受影响

```
admin/app/(dashboard)/settings/
└── email-types/
    └── page.tsx                      ← Server Component
admin/components/
└── email-type-settings-table.tsx     ← Client Component（含开关 toggle）
admin/app/actions/
└── email-settings.ts                 ← Server Actions: toggleEmailType, updateAdminRecipients
```

### 7.2 新页面：`/settings/email-logs`（邮件发送记录 + 内容预览）

管理员可以：
- 查看**全部三端**（客户端 / 商家端 / 后台管理端）的邮件发送记录
- 按 `email_code`、`recipient_type`、`status`、`recipient_email`、日期范围筛选
- 点击任意一条记录，**弹出预览面板**展示该邮件的实际 HTML 渲染效果（iframe 渲染 `html_body`）
- 查看 `smtp2go_message_id`、`error_message`、`retry_count` 等技术细节

```
admin/app/(dashboard)/settings/
└── email-logs/
    └── page.tsx                      ← Server Component（列表 + 筛选）
admin/components/
├── email-logs-table.tsx              ← Client Component（表格）
└── email-preview-modal.tsx           ← Client Component（内容预览弹窗）
```

---

## 8. 用户端 / 商家端新增功能

### 8.1 客户端：邮件偏好设置

**位置**：`deal_joy/lib/features/profile/` 设置页面中新增「Email Notifications」入口

**展示逻辑**：
- 查询 `email_type_settings` 中 `recipient_type = 'customer'` 且 `global_enabled = true` 且 `user_configurable = true` 的邮件类型
- 仅展示上述结果（当前为 C3、C4、C13 三项）
- 管理员关闭某项后，该选项从用户设置中自动消失

**当前可配置邮件（共 3 种）**：
| 邮件编号 | 名称 | 默认 |
|---------|------|-----|
| C3 | Coupon 核销成功通知 | 开启 |
| C4 | Coupon 即将到期提醒 | 开启 |
| C13 | 商家已回复售后通知 | 开启 |

**新增文件**：
```
deal_joy/lib/features/profile/
├── data/repositories/email_preferences_repository.dart
├── domain/providers/email_preferences_provider.dart
└── presentation/
    └── widgets/email_preferences_section.dart  ← 嵌入现有设置页
```

### 8.2 商家端：邮件偏好设置

**位置**：`dealjoy_merchant/` 设置页面中新增「Email Notifications」入口

**展示逻辑**：与客户端相同，动态读取 `global_enabled = true` 且 `user_configurable = true` 的商家端邮件类型

**当前可配置邮件（共 4 种）**：
| 邮件编号 | 名称 | 默认 |
|---------|------|-----|
| M5 | 新订单通知 | 开启 |
| M6 | Deal 即将到期提醒 | 开启 |
| M7 | Coupon 核销成功通知 | 开启 |
| M13 | 月度结算报告 | 开启 |

---

## 9. SMTP2GO 配置检查清单

**在开始开发前必须完成以下步骤：**

- [ ] **注册 SMTP2GO 账户**（smtp2go.com）
- [ ] **添加发件域名**：`crunchyplum.com`
- [ ] **在 crunchyplum.com 域名 DNS 配置以下记录**：
  - SPF 记录：使用 SMTP2GO 提供的 SPF 值（TXT 记录）
  - DKIM 记录：SMTP2GO 后台提供（TXT 记录）
  - DMARC 记录：`v=DMARC1; p=none; rua=mailto:dmarc@crunchyplum.com`
- [ ] **创建发件人**：`noreply@crunchyplum.com`
- [ ] **生成 API Key** → 保存为 Supabase Secret
- [ ] **添加到 Supabase Secrets**：`SMTP2GO_API_KEY=<key>`
- [ ] **添加到 admin `.env.local`**：`SMTP2GO_API_KEY=<same key>`
- [ ] **配置 Supabase Auth SMTP**：
  - Dashboard → Authentication → SMTP Settings
  - Host: `mail.smtp2go.com`，Port: `587`

---

## 10. 分阶段开发计划

### Phase 1 — 基础设施（优先完成）

**目标：** 所有共享工具、数据库表、SMTP2GO 配置完成并可用。

- [ ] SMTP2GO 账户注册及 crunchyplum.com 域名 DNS 验证
- [ ] Migration `20260321000001_email_system.sql`（4 张新表）
- [ ] `_shared/email.ts`（含双重权限检查的发送工具）
- [ ] `_shared/email-templates/base-layout.ts`（公共模板布局）
- [ ] `admin/lib/email.ts`（Next.js 发送工具）
- [ ] Supabase Auth 自定义邮件模板（C1 欢迎邮件、C12 密码重置）
- [ ] Admin `/settings/email-types` 页面（全局开关管理）

**验收标准：** 发送测试邮件，确认 `email_logs` 中出现记录且 `html_body` 不为空；切换全局开关后验证发送被拦截。

---

### Phase 2 — 客户端核心交易邮件

**目标：** 覆盖购买与退款主流程。

- [ ] C2 — 订单确认邮件（`create-order-v3`）
- [ ] C3 — Coupon 核销成功通知（`merchant-scan`）
- [ ] C7 — 退款申请受理确认（`create-refund`）
- [ ] C8 — Stripe 退款到账通知（`stripe-webhook`）
- [ ] C5 / C6 — 到期自动退款 + Store Credit 到账通知（`auto-refund-expired`）

---

### Phase 3 — 商家端核心邮件

**目标：** 商家能收到所有关键业务事件通知。

- [ ] M1 / M2 — 注册欢迎 + 认证申请受理（`merchant-register`）
- [ ] M3 / M4 — 认证通过/拒绝（`admin/actions/admin.ts`）
- [ ] M5 — 新订单通知（`create-order-v3`）
- [ ] M7 — Coupon 核销成功通知（`merchant-scan`）
- [ ] M8 — 核销前退款通知（`create-refund`）
- [ ] M16 — Deal 被管理员驳回通知（`admin/actions/admin.ts`）

---

### Phase 4 — 售后邮件全流程

**目标：** 售后申请全程三方均有邮件通知。

- [ ] C9 + M9 + A5 — 售后申请提交（`after-sales-request`）
- [ ] C13 + M10 / M11 — 商家处理结果（`merchant-after-sales`）
- [ ] C10 / C11 + M12 + A6 — 平台最终裁决（`platform-after-sales`）

---

### Phase 5 — 定时提醒邮件（Cron Jobs）

**目标：** 主动提醒，降低 Coupon 过期流失率，保持商家活跃度。

- [ ] C4 — Coupon 即将到期提醒（新建 `notify-expiring-coupons` Cron）
- [ ] M6 — Deal 即将到期提醒（新建 `notify-expiring-deals` Cron）
- [ ] A3 — 管理员每日汇总（新建 `admin-daily-digest` Cron）
- [ ] M13 — 商家月度结算报告（新建 `monthly-settlement-report` Cron）

---

### Phase 6 — 用户偏好设置 + 剩余功能

**目标：** 完成用户/商家偏好设置 UI、Admin 邮件日志预览、剩余邮件类型。

- [ ] 客户端邮件偏好设置 UI（C3、C4、C13）
- [ ] 商家端邮件偏好设置 UI（M5、M6、M7、M13）
- [ ] Admin `/settings/email-logs` 页面（含 HTML 内容预览弹窗）
- [ ] A4 — 大额退款预警（`create-refund` 阈值检测 $500）
- [ ] A7 + M14 — 提现申请通知（`merchant-withdrawal`）
- [ ] M15 + 新建提现审批通过 Admin Action
- [ ] A8 — 系统异常告警邮件（`_shared/error.ts` 统一错误处理器）

---

## 11. 已确认事项

| 问题 | 确认结果 |
|------|---------|
| 后台管理端技术栈 | Next.js 15 App Router（`admin/` 目录） |
| 管理员收件人管理方式 | `email_type_settings.admin_recipient_emails` + Admin Dashboard 配置页面 |
| 发件域名 | crunchyplum.com |
| Supabase Auth 邮件处理 | 替换为通过 SMTP2GO 发送的品牌化模板 |
| 邮件内容语言 | 全英文（面向北美 Dallas 市场） |
| 全局开关管控 | 管理员可从后台开启/关闭任意邮件类型，实时生效 |
| 用户偏好设置 | 仅 `user_configurable = true` 的邮件类型开放给用户自主配置 |
| 全局开关与偏好联动 | 全局关闭时，用户/商家设置页中该选项完全隐藏（非置灰） |
| 邮件日志内容预览 | `email_logs` 存储 `html_body`，管理端点击记录可弹窗预览渲染效果 |

---

## 12. 邮件编号速查表

| 编号 | 邮件名称 | 用户可关闭 | 开发阶段 |
|------|---------|-----------|---------|
| C1 | 客户注册欢迎邮件 | ✗ | Phase 1 |
| C2 | 订单确认邮件 | ✗ | Phase 2 |
| C3 | Coupon 核销成功（客户） | ✓ | Phase 2 |
| C4 | Coupon 即将到期提醒 | ✓ | Phase 5 |
| C5 | 到期自动退款通知 | ✗ | Phase 2 |
| C6 | Store Credit 余额到账通知 | ✗ | Phase 2 |
| C7 | 退款申请受理确认 | ✗ | Phase 2 |
| C8 | Stripe 退款到账通知 | ✗ | Phase 2 |
| C9 | 售后申请提交确认 | ✗ | Phase 4 |
| C10 | 售后审核通过通知 | ✗ | Phase 4 |
| C11 | 售后审核拒绝通知 | ✗ | Phase 4 |
| C12 | 密码重置邮件 | ✗ | Phase 1 |
| C13 | 商家已回复售后通知 | ✓ | Phase 4 |
| M1 | 商家注册欢迎邮件 | ✗ | Phase 3 |
| M2 | 认证申请受理通知 | ✗ | Phase 3 |
| M3 | 商户认证通过通知 | ✗ | Phase 3 |
| M4 | 商户认证拒绝通知 | ✗ | Phase 3 |
| M5 | 新订单通知 | ✓ | Phase 3 |
| M6 | Deal 即将到期提醒 | ✓ | Phase 5 |
| M7 | Coupon 核销成功（商家） | ✓ | Phase 3 |
| M8 | 核销前退款通知 | ✗ | Phase 3 |
| M9 | 收到售后申请通知 | ✗ | Phase 4 |
| M10 | 商家同意售后退款确认 | ✗ | Phase 4 |
| M11 | 商家拒绝售后——升级平台 | ✗ | Phase 4 |
| M12 | 平台最终裁决通知 | ✗ | Phase 4 |
| M13 | 月度结算报告 | ✓ | Phase 5 |
| M14 | 提现申请受理通知 | ✗ | Phase 6 |
| M15 | 提现完成通知 | ✗ | Phase 6 |
| M16 | Deal 被管理员驳回通知 | ✗ | Phase 3 |
| A1 | 管理员账户创建通知 | — | Phase 1 |
| A2 | 新商户认证申请提醒 | — | Phase 3 |
| A3 | 每日待处理任务汇总 | — | Phase 5 |
| A4 | 大额退款预警 | — | Phase 6 |
| A5 | 售后案件升级审核通知 | — | Phase 4 |
| A6 | 售后案件结案通知 | — | Phase 4 |
| A7 | 新提现申请审核通知 | — | Phase 6 |
| A8 | 系统异常告警邮件 | — | Phase 6 |
