# DealJoy 邮件系统开发计划书

> **创建日期：** 2026-03-21
> **发件域名：** crunchyplum.com
> **邮件服务商：** SMTP2GO
> **邮件内容语言：** 英文（面向北美 Dallas 市场）
> **状态：** 规划中

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
4. 后台管理员可在 Dashboard 中配置通知收件人
5. 通过 `email_logs` 表完整记录所有邮件发送历史
6. 异步非阻塞——邮件发送失败绝不影响核心业务流程

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

### 核心设计原则

1. **双工具分离**：Edge Functions 使用 `_shared/email.ts`；Admin Next.js Server Actions 使用 `admin/lib/email.ts`。两者调用同一 SMTP2GO 接口，共享模板逻辑。
2. **即发即忘**：`await sendEmail(...)` 包裹在 try/catch 中——发送失败只记录日志，不向上抛出异常。
3. **幂等性保护**：发送前检查 `email_logs` 中过去 24 小时内是否已存在相同 `(email_type, reference_id, recipient_email)` 的成功记录，防止 Cron Job 或重试导致重复发送。
4. **收件人可配置**：后台管理员通知邮件（A 系列）的收件人从 `admin_notification_settings` 表动态读取，可在 Admin Dashboard 中管理。
5. **模板就近存放**：每种邮件类型对应 `_shared/email-templates/` 下一个独立的 TypeScript 函数，渲染完整 HTML（内联 CSS，无外部依赖）。

### 新增文件结构

```
deal_joy/supabase/functions/
├── _shared/
│   ├── email.ts                                ← 新建：Edge Function 发送工具 sendEmail()
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

## 3. 数据库变更

### 3.1 `email_logs` 表（邮件发送日志）

```sql
-- Migration: 20260321000001_email_system.sql

CREATE TABLE email_logs (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recipient_email  TEXT NOT NULL,
  recipient_type   TEXT NOT NULL CHECK (recipient_type IN ('customer', 'merchant', 'admin')),
  email_type       TEXT NOT NULL,
  -- 关联业务主键（order_id / order_item_id / merchant_id / after_sales_request_id 等）
  reference_id     UUID,
  subject          TEXT NOT NULL,
  status           TEXT NOT NULL DEFAULT 'pending'
                     CHECK (status IN ('pending', 'sent', 'failed', 'bounced')),
  smtp2go_message_id TEXT,
  error_message    TEXT,
  retry_count      INTEGER DEFAULT 0,
  sent_at          TIMESTAMPTZ,
  created_at       TIMESTAMPTZ DEFAULT NOW()
);

-- 用于幂等性检查的复合索引
CREATE INDEX idx_email_logs_dedup
  ON email_logs (email_type, reference_id, recipient_email, created_at);

-- RLS：仅 service_role 可读写
ALTER TABLE email_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "service_role_only" ON email_logs
  USING (auth.role() = 'service_role');
```

### 3.2 `admin_notification_settings` 表（管理员通知收件人配置）

```sql
CREATE TABLE admin_notification_settings (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  notification_type TEXT NOT NULL UNIQUE,
  -- 收件人邮件列表（JSON 数组，例如 ["admin@crunchyplum.com"]）
  recipient_emails  JSONB NOT NULL DEFAULT '[]',
  enabled           BOOLEAN NOT NULL DEFAULT TRUE,
  description       TEXT,
  updated_at        TIMESTAMPTZ DEFAULT NOW(),
  updated_by        UUID REFERENCES users(id)
);

-- 预置所有 A 系列通知类型的默认记录
INSERT INTO admin_notification_settings (notification_type, description) VALUES
  ('merchant_application',  '新商户认证申请提交'),
  ('after_sales_escalated', '售后案件由商家升级至平台审核'),
  ('after_sales_closed',    '平台完成售后案件最终裁决'),
  ('large_refund_alert',    '单笔退款超过预警阈值（$500）'),
  ('withdrawal_request',    '商家提交新的提现申请'),
  ('daily_digest',          '每日待处理事项汇总');

-- RLS：admin 角色可读写
ALTER TABLE admin_notification_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "admin_read" ON admin_notification_settings
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin')
  );
CREATE POLICY "admin_write" ON admin_notification_settings
  FOR ALL USING (
    EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin')
  );
```

---

## 4. 邮件完整清单

### 4.1 客户端邮件（C 系列）

| 编号 | 邮件名称 | 触发时机 | 触发位置 | 关键内容 |
|------|---------|---------|---------|---------|
| C1 | 注册欢迎邮件 | 用户完成邮箱验证 | `send-auth-email`（新建） | 用户名、App 下载链接 |
| C2 | 订单确认邮件 | 订单创建成功 | `create-order-v3` | 订单号、Deal 列表、购买数量、金额、每张券到期日 |
| C3 | Coupon 核销成功通知 | 商家完成扫码核销 | `merchant-scan` | 商家名称、Deal 名称、核销时间、门店地址 |
| C4 | Coupon 即将到期提醒 | 到期前 3 天 | `notify-expiring-coupons`（Cron） | Deal 名称、到期日期、退款政策说明 |
| C5 | Coupon 到期自动退款通知 | `auto-refund-expired` 执行 | `auto-refund-expired` | 退款金额、退款方式（Store Credit）、到账后余额 |
| C6 | Store Credit 余额到账通知 | 任何 Store Credit 退款成功 | `create-refund` / `auto-refund-expired` | 本次到账金额、当前余额、Store Credit 使用说明 |
| C7 | 退款申请受理确认 | `create-refund` 受理成功 | `create-refund` | 订单号、退款金额、退款方式（Store Credit / 原路退回）、预计到账时间 |
| C8 | Stripe 退款到账通知 | `stripe-webhook` 收到 charge.refunded | `stripe-webhook` | 退款金额、银行卡末四位、3-5 个工作日说明 |
| C9 | 售后申请提交确认 | 售后请求创建成功 | `after-sales-request` | 申请编号、申请原因、7 天审核承诺、客服邮箱 |
| C10 | 售后退款审核通过通知 | 平台批准退款 | `platform-after-sales` | 退款金额、退款方式、处理时间 |
| C11 | 售后退款审核拒绝通知 | 平台拒绝申请 | `platform-after-sales` | 拒绝原因、申诉渠道、客服联系方式 |
| C12 | 密码重置邮件 | 用户申请重置密码 | Supabase Auth 自定义模板 | 重置链接（1 小时内有效） |
| C13 | 商家已回复售后通知 | 商家提交售后处理意见 | `merchant-after-sales` | 商家回复内容、案件当前状态、后续步骤说明 |

### 4.2 商家端邮件（M 系列）

| 编号 | 邮件名称 | 触发时机 | 触发位置 | 关键内容 |
|------|---------|---------|---------|---------|
| M1 | 注册欢迎邮件 | 商家注册提交成功 | `merchant-register` | 商家名称、认证流程说明、Dashboard 链接 |
| M2 | 认证申请受理通知 | 材料上传并进入审核 | `merchant-register` | 申请编号、预计审核时间（1-3 个工作日） |
| M3 | 商户认证通过通知 | 后台管理员审核通过 | `admin/app/actions/admin.ts → approveMerchant` | 已开通功能列表、免佣期截止日期、Dashboard 链接、发布首个 Deal 指引 |
| M4 | 商户认证拒绝通知 | 后台管理员审核拒绝 | `admin/app/actions/admin.ts → rejectMerchant` | 拒绝原因、需补充材料清单、重新提交链接 |
| M5 | 新订单通知 | 涉及该商家 Deal 的订单创建成功 | `create-order-v3` | 订单号、Deal 名称、购买数量、券到期日、Dashboard 链接 |
| M6 | Deal 即将到期提醒 | 到期前 7 天 | `notify-expiring-deals`（Cron） | Deal 名称、到期日期、已售数量、未核销券数量 |
| M7 | Coupon 核销成功通知 | 扫码核销完成 | `merchant-scan` | 脱敏券码、Deal 名称、核销金额、今日累计核销笔数 |
| M8 | 核销前退款通知 | 客户主动退回未使用券 | `create-refund` | 订单号、退款金额、可用库存变更说明 |
| M9 | 收到售后申请通知 | 客户提交售后请求 | `after-sales-request` | 申请编号、客户申请原因、证据材料说明、48 小时处理期限 |
| M10 | 商家同意售后退款确认 | 商家批准退款 | `merchant-after-sales` | 申请编号、退款金额、已通知客户确认 |
| M11 | 商家拒绝售后——升级平台通知 | 商家拒绝，案件升级至平台 | `merchant-after-sales` | 申请编号、商家拒绝原因、平台将在 3 个工作日内复核说明 |
| M12 | 平台最终裁决通知 | 平台做出最终决定 | `platform-after-sales` | 最终决定（通过/拒绝）、原因说明、对商家收益的影响 |
| M13 | 月度结算报告 | 每月 1 日 | `monthly-settlement-report`（Cron） | 上月核销总额、退款总额、净收益、平台佣金、应结算金额 |
| M14 | 提现申请受理通知 | 商家提交提现申请 | `merchant-withdrawal` | 提现金额、银行账户末四位、预计处理时间 |
| M15 | 提现完成通知 | 管理员标记提现完成 | Admin 操作触发 | 到账金额、交易流水号 |
| M16 | Deal 被管理员驳回通知 | 管理员驳回已提交的 Deal | `admin/app/actions/admin.ts → rejectDeal` | Deal 名称、驳回原因、需修改内容说明、重新提交链接 |

### 4.3 后台管理端邮件（A 系列）

> A 系列各类通知的收件人在 Admin Dashboard **设置 → 通知收件人** 页面中配置和管理。

| 编号 | 邮件名称 | 触发时机 | 触发位置 | 关键内容 |
|------|---------|---------|---------|---------|
| A1 | 管理员账户创建通知 | 新管理员账户创建 | Admin 操作 | 用户名、临时密码、Dashboard 登录链接 |
| A2 | 新商户认证申请提醒 | 商家提交注册材料 | `merchant-register` | 商家名称、提交时间、材料列表、Dashboard 审核链接 |
| A3 | 每日待处理任务汇总 | 每天上午 9:00（美国中部时间） | `admin-daily-digest`（Cron） | 待审商户认证数、待处理售后案件数、待审提现申请数 |
| A4 | 大额退款预警 | 单笔退款超过 $500 | `create-refund` / `admin-refund` | 退款金额、用户 ID、订单号、需人工复核提示 |
| A5 | 售后案件升级审核通知 | 商家拒绝售后，案件升级至平台 | `merchant-after-sales` | 申请编号、完整事件时间线、客户证据、商家拒绝理由、Dashboard 审核链接 |
| A6 | 售后案件结案通知 | 平台做出最终裁决 | `platform-after-sales` | 案件编号、最终决定、审核人、案件摘要存档 |
| A7 | 新提现申请审核通知 | 商家提交提现申请 | `merchant-withdrawal` | 商家名称、提现金额、银行账户信息、Dashboard 审批链接 |
| A8 | 系统异常告警邮件 | Edge Function 捕获严重错误 | 各 Edge Function 错误处理器 | 错误类型、函数名称、简化 Stack Trace、受影响的用户/订单 |

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
  emailType: string;       // 写入 email_logs.email_type
  referenceId?: string;    // 写入 email_logs.reference_id（UUID）
  recipientType: 'customer' | 'merchant' | 'admin';
}

export async function sendEmail(
  supabaseClient: SupabaseClient,
  payload: EmailPayload
): Promise<void> {
  const recipients = Array.isArray(payload.to) ? payload.to : [payload.to];

  for (const email of recipients) {
    // 幂等性检查：过去 24 小时内是否已成功发过同类邮件
    if (payload.referenceId) {
      const { data: existing } = await supabaseClient
        .from('email_logs')
        .select('id')
        .eq('email_type', payload.emailType)
        .eq('reference_id', payload.referenceId)
        .eq('recipient_email', email)
        .eq('status', 'sent')
        .gte('created_at', new Date(Date.now() - 86400000).toISOString())
        .maybeSingle();
      if (existing) continue; // 已发过，跳过
    }

    // 插入 pending 日志记录
    const { data: logRow } = await supabaseClient
      .from('email_logs')
      .insert({
        recipient_email: email,
        recipient_type: payload.recipientType,
        email_type: payload.emailType,
        reference_id: payload.referenceId ?? null,
        subject: payload.subject,
        status: 'pending',
      })
      .select('id')
      .single();

    try {
      const response = await fetch(SMTP2GO_API_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          api_key: Deno.env.get('SMTP2GO_API_KEY'),
          to: [email],
          sender: `${FROM_NAME} <${FROM_EMAIL}>`,
          subject: payload.subject,
          html_body: payload.htmlBody,
          text_body: payload.textBody ?? '',
        }),
      });

      const result = await response.json();

      // 更新日志状态为 sent
      await supabaseClient.from('email_logs').update({
        status: 'sent',
        smtp2go_message_id: result?.data?.email_id ?? null,
        sent_at: new Date().toISOString(),
      }).eq('id', logRow?.id);

    } catch (err) {
      // 更新日志状态为 failed，但不向上抛出异常
      await supabaseClient.from('email_logs').update({
        status: 'failed',
        error_message: String(err),
        retry_count: 1,
      }).eq('id', logRow?.id);
    }
  }
}
```

### 5.2 `admin/lib/email.ts`（Next.js 发送工具）

```typescript
// admin/lib/email.ts
// 在 Next.js Server Actions 中调用，逻辑与 Edge Function 版本一致，使用 Node.js fetch

const SMTP2GO_API_URL = 'https://api.smtp2go.com/v3/email/send';

export interface AdminEmailPayload {
  to: string | string[];
  subject: string;
  htmlBody: string;
  emailType: string;
  referenceId?: string;
}

export async function sendAdminEmail(payload: AdminEmailPayload): Promise<void> {
  try {
    await fetch(SMTP2GO_API_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        api_key: process.env.SMTP2GO_API_KEY,
        to: Array.isArray(payload.to) ? payload.to : [payload.to],
        sender: 'DealJoy <noreply@crunchyplum.com>',
        subject: payload.subject,
        html_body: payload.htmlBody,
      }),
    });
  } catch {
    // 静默失败——邮件发送不阻断管理员操作
  }
}

// 从数据库读取指定通知类型的管理员收件人列表
export async function getAdminRecipients(
  supabase: SupabaseClient,
  notificationType: string
): Promise<string[]> {
  const { data } = await supabase
    .from('admin_notification_settings')
    .select('recipient_emails, enabled')
    .eq('notification_type', notificationType)
    .single();

  if (!data?.enabled || !data?.recipient_emails) return [];
  return data.recipient_emails as string[];
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

通过 Supabase Dashboard **Auth → Email Templates** 替换默认模板：
- **Confirm Signup（注册验证）**：品牌化欢迎邮件 + 验证按钮
- **Reset Password（密码重置）**：品牌化重置邮件 + 有效期提示

或者：通过配置 SMTP2GO 的 SMTP 端点（`GOTRUE_SMTP_*` 环境变量），使所有 Auth 邮件也统一从 `noreply@crunchyplum.com` 发出（推荐此方式，确保发件人一致性）。

### 5.5 新建 Cron Job Edge Functions

#### `notify-expiring-coupons`（每天 8:00 AM 美国中部时间）
```sql
-- 查询：找出恰好 3 天后到期的 order_items
SELECT oi.id, oi.order_id, u.email, u.full_name, d.title AS deal_title,
       c.expires_at, oi.unit_price
FROM order_items oi
JOIN orders o ON o.id = oi.order_id
JOIN users u ON u.id = o.user_id
JOIN deals d ON d.id = oi.deal_id
JOIN coupons c ON c.order_item_id = oi.id
WHERE oi.customer_status = 'unused'
  AND c.expires_at::date = CURRENT_DATE + INTERVAL '3 days'
  AND c.status = 'active';
```
向每位客户发送 C4 邮件，通过 `email_logs` 做去重。

#### `notify-expiring-deals`（每天 9:00 AM 美国中部时间）
```sql
-- 查询：找出恰好 7 天后到期的 deals
SELECT d.id, d.title, d.expires_at, m.name AS merchant_name,
       u.email AS merchant_email,
       COUNT(c.id) FILTER (WHERE c.status = 'active') AS unredeemed_count,
       COUNT(c.id) AS total_sold
FROM deals d
JOIN merchants m ON m.id = d.merchant_id
JOIN users u ON u.id = m.user_id
LEFT JOIN coupons c ON c.deal_id = d.id
WHERE d.is_active = true
  AND d.expires_at::date = CURRENT_DATE + INTERVAL '7 days'
GROUP BY d.id, m.name, u.email;
```
向各商家主账号邮箱发送 M6 邮件。

#### `monthly-settlement-report`（每月 1 日 6:00 AM 美国中部时间）
查询 `merchant_earnings` 视图获取上月数据，向每个活跃商家发送 M13 月度结算报告。

#### `admin-daily-digest`（每天 9:00 AM 美国中部时间）
查询各维度待处理数量：待审商户认证、未结案售后、待审提现申请。向 `daily_digest` 类型配置的管理员收件人发送 A3 邮件。

---

## 6. 现有 Edge Functions 改造清单

### Edge Functions

| 函数名 | 需要改动 | 新增邮件 |
|--------|---------|---------|
| `create-order-v3` | 订单创建成功后调用 `sendEmail()` | C2、M5 |
| `merchant-scan` | 核销成功后调用 `sendEmail()` | C3、M7 |
| `create-refund` | 按退款类型调用 `sendEmail()`；金额超过 $500 时触发预警 | C6、C7、M8、A4 |
| `auto-refund-expired` | 每笔到期退款后调用 `sendEmail()` | C5、C6 |
| `stripe-webhook` | 收到 `charge.refunded` 事件时调用 `sendEmail()` | C8 |
| `after-sales-request` | 三方同时通知 | C9、M9、A5 |
| `merchant-after-sales` | 按批准/拒绝路径调用 `sendEmail()` | C13、M10、M11 |
| `platform-after-sales` | 平台最终裁决时通知三方 | C10、C11、M12、A6 |
| `merchant-register` | 注册成功后调用 `sendEmail()` | M1、M2、A2 |
| `merchant-withdrawal` | 提现申请提交后调用 `sendEmail()` | M14、A7 |

### Admin Server Actions

| Server Action | 需要改动 | 新增邮件 |
|---------------|---------|---------|
| `approveMerchant` | DB 更新后调用 `sendAdminEmail()` | M3 |
| `rejectMerchant` | DB 更新后调用 `sendAdminEmail()` | M4 |
| `rejectDeal` | DB 更新后调用 `sendAdminEmail()` | M16 |
| 新建：提现审批通过 action | 状态更新时调用 `sendAdminEmail()` | M15 |

---

## 7. Admin Dashboard 新增功能

### 新页面：`/settings/notifications`（通知收件人管理）

允许管理员执行以下操作：
- 查看全部通知类型（A 系列）
- 为每种通知类型添加/删除收件人邮箱
- 单独开启/关闭某类通知
- 查看最近的 Admin 邮件发送记录（查询 `email_logs` 中 `recipient_type = 'admin'` 的记录）

```
admin/app/(dashboard)/settings/
└── notifications/
    └── page.tsx                            ← Server Component + Client 表单
admin/components/
└── notification-settings-form.tsx          ← Client Component
admin/app/actions/
└── email-settings.ts                       ← Server Actions: updateNotificationRecipients, toggleNotification
```

### 新页面：`/settings/email-logs`（邮件发送日志）

管理员只读查看邮件发送健康状态：
- 按 `email_type`、`status`、`recipient_type`、日期范围筛选
- 显示 `smtp2go_message_id`、`error_message`、`retry_count`

---

## 8. SMTP2GO 配置检查清单

**在开始开发前必须完成以下步骤：**

- [ ] **注册 SMTP2GO 账户**（smtp2go.com）
- [ ] **添加发件域名**：`crunchyplum.com`
- [ ] **在 crunchyplum.com 域名 DNS 配置以下记录**：
  - SPF 记录：使用 SMTP2GO 提供的 SPF 值（TXT 记录）
  - DKIM 记录：SMTP2GO 后台提供（TXT 记录）
  - DMARC 记录：`v=DMARC1; p=none; rua=mailto:dmarc@crunchyplum.com`
- [ ] **创建发件人**：`noreply@crunchyplum.com`
- [ ] **生成 API Key** → 保存为 Supabase Secret
- [ ] **添加到 Supabase Secrets**：
  ```
  SMTP2GO_API_KEY=<key>
  ```
- [ ] **添加到 admin `.env.local`**：
  ```
  SMTP2GO_API_KEY=<same key>
  ```
- [ ] **配置 Supabase Auth SMTP**（用于 C1/C12）：
  - Dashboard → Authentication → SMTP Settings
  - Host: `mail.smtp2go.com`，Port: `587`
  - Username/Password：使用 SMTP2GO 账户凭据

---

## 9. 分阶段开发计划

### Phase 1 — 基础设施（优先完成）

**目标：** 所有共享工具、数据库表、SMTP2GO 配置完成并可用，为后续邮件开发打好基础。

- [ ] SMTP2GO 账户注册及 crunchyplum.com 域名 DNS 验证
- [ ] Migration `20260321000001_email_system.sql`（`email_logs` + `admin_notification_settings` 表）
- [ ] `_shared/email.ts`（Edge Function 发送工具）
- [ ] `_shared/email-templates/base-layout.ts`（公共 HTML 模板布局）
- [ ] `admin/lib/email.ts`（Next.js 发送工具）
- [ ] Supabase Auth 自定义邮件模板（C1 欢迎邮件、C12 密码重置）
- [ ] 预置 `admin_notification_settings` 全部 A 系列默认记录

**验收标准：** 分别从两套工具各发送一封测试邮件，确认 `email_logs` 中出现对应记录。

---

### Phase 2 — 客户端核心交易邮件

**目标：** 覆盖购买与退款主流程，优先级最高、用户感知最强。

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

**目标：** 售后申请全程三方（客户、商家、管理员）均有邮件知会。

- [ ] C9 + M9 + A5 — 售后申请提交通知（`after-sales-request`）
- [ ] C13 + M10 / M11 — 商家处理结果通知（`merchant-after-sales`）
- [ ] C10 / C11 + M12 + A6 — 平台最终裁决通知（`platform-after-sales`）

---

### Phase 5 — 定时提醒邮件（Cron Jobs）

**目标：** 主动提醒，降低 Coupon 过期流失率，保持商家活跃度。

- [ ] C4 — Coupon 即将到期提醒（新建 `notify-expiring-coupons` Cron，每日）
- [ ] M6 — Deal 即将到期提醒（新建 `notify-expiring-deals` Cron，每日）
- [ ] A3 — 管理员每日汇总（新建 `admin-daily-digest` Cron，每日 9AM CT）
- [ ] M13 — 商家月度结算报告（新建 `monthly-settlement-report` Cron，每月）

---

### Phase 6 — Admin Dashboard 功能 & 剩余邮件

**目标：** 完成管理端可视化配置功能及剩余邮件类型。

- [ ] Admin `/settings/notifications` 页面（通知收件人管理）
- [ ] Admin `/settings/email-logs` 页面（发送日志查看）
- [ ] A4 — 大额退款预警（`create-refund` 阈值检测，$500）
- [ ] A7 + M14 — 提现申请通知（`merchant-withdrawal`）
- [ ] M15 + 新建提现审批通过 Admin Action
- [ ] A8 — 系统异常告警邮件（`_shared/error.ts` 统一错误处理器）

---

## 10. 已确认事项

| 问题 | 确认结果 |
|------|---------|
| 后台管理端技术栈 | Next.js 15 App Router（`admin/` 目录） |
| 管理员收件人管理方式 | `admin_notification_settings` 表 + Admin Dashboard 配置页面 |
| 发件域名 | crunchyplum.com |
| Supabase Auth 邮件处理 | 替换为通过 SMTP2GO 发送的品牌化模板 |
| 邮件内容语言 | 全英文（面向北美 Dallas 市场） |
| Admin 端代码位置 | `admin/app/actions/admin.ts`，Server Actions 模式 |

---

## 11. 邮件编号速查表

| 编号 | 邮件名称 | 开发阶段 |
|------|---------|---------|
| C1 | 客户注册欢迎邮件 | Phase 1 |
| C2 | 订单确认邮件 | Phase 2 |
| C3 | Coupon 核销成功（客户） | Phase 2 |
| C4 | Coupon 即将到期提醒 | Phase 5 |
| C5 | 到期自动退款通知 | Phase 2 |
| C6 | Store Credit 余额到账通知 | Phase 2 |
| C7 | 退款申请受理确认 | Phase 2 |
| C8 | Stripe 退款到账通知 | Phase 2 |
| C9 | 售后申请提交确认 | Phase 4 |
| C10 | 售后审核通过通知 | Phase 4 |
| C11 | 售后审核拒绝通知 | Phase 4 |
| C12 | 密码重置邮件 | Phase 1 |
| C13 | 商家已回复售后通知 | Phase 4 |
| M1 | 商家注册欢迎邮件 | Phase 3 |
| M2 | 认证申请受理通知 | Phase 3 |
| M3 | 商户认证通过通知 | Phase 3 |
| M4 | 商户认证拒绝通知 | Phase 3 |
| M5 | 新订单通知 | Phase 3 |
| M6 | Deal 即将到期提醒 | Phase 5 |
| M7 | Coupon 核销成功（商家） | Phase 3 |
| M8 | 核销前退款通知 | Phase 3 |
| M9 | 收到售后申请通知 | Phase 4 |
| M10 | 商家同意售后退款确认 | Phase 4 |
| M11 | 商家拒绝售后——升级平台 | Phase 4 |
| M12 | 平台最终裁决通知 | Phase 4 |
| M13 | 月度结算报告 | Phase 5 |
| M14 | 提现申请受理通知 | Phase 6 |
| M15 | 提现完成通知 | Phase 6 |
| M16 | Deal 被管理员驳回通知 | Phase 3 |
| A1 | 管理员账户创建通知 | Phase 1 |
| A2 | 新商户认证申请提醒 | Phase 3 |
| A3 | 每日待处理任务汇总 | Phase 5 |
| A4 | 大额退款预警 | Phase 6 |
| A5 | 售后案件升级审核通知 | Phase 4 |
| A6 | 售后案件结案通知 | Phase 4 |
| A7 | 新提现申请审核通知 | Phase 6 |
| A8 | 系统异常告警邮件 | Phase 6 |
