# DealJoy Email System — Implementation Plan

> **Created:** 2026-03-21
> **Domain:** crunchyplum.com
> **Email Provider:** SMTP2GO
> **Language:** English (all email content)
> **Status:** Planning

---

## 1. Current State & Goals

### Current State

| Area | Status |
|------|--------|
| Transactional email | None — only Supabase Auth built-in verification |
| Business notifications | `merchant_notifications` table (in-app only) |
| Auth emails | Supabase default templates (to be replaced) |
| Edge Functions | 29 functions, zero SMTP integration |
| Admin backend | Next.js 15 App Router (`admin/`) |

### Goals

1. Replace Supabase Auth default emails with branded crunchyplum.com templates
2. Build a complete transactional email system covering all 3 portals
3. All emails sent via SMTP2GO using `noreply@crunchyplum.com`
4. Admin-configurable notification recipients (managed in admin dashboard)
5. Full send audit trail via `email_logs` table
6. Async, non-blocking — email failure must never break core business logic

---

## 2. Architecture

### Sending Path

```
Trigger Source              Sending Utility             SMTP2GO
────────────────            ───────────────             ────────
Edge Function         →     _shared/email.ts      →     SMTP2GO REST API
                                                         (api.smtp2go.com/v3)
Admin Server Action   →     admin/lib/email.ts    →         ↓
Cron Edge Function    →     _shared/email.ts      →     email_logs (DB)
Supabase Auth Hook    →     send-auth-email (new) →
```

### Key Design Principles

1. **Dual sending utilities**: Edge Functions use `_shared/email.ts`; Admin Next.js Server Actions use `admin/lib/email.ts`. Both call the same SMTP2GO endpoint with shared template logic.
2. **Fire-and-forget**: `await sendEmail(...)` wrapped in try/catch — failures are logged, never thrown up.
3. **Idempotency guard**: Before sending, check `email_logs` for a record with the same `(email_type, reference_id, recipient_email)` within the last 24 hours to prevent duplicates on retries.
4. **Admin-managed recipients**: Admin notification emails (A-series) use recipients queried from `admin_notification_settings` table, editable via the admin dashboard.
5. **Template co-location**: Each email type has its own TypeScript template function in `_shared/email-templates/`. Templates render full HTML with inline CSS — no external CSS dependencies.

### New File Structure

```
deal_joy/supabase/functions/
├── _shared/
│   ├── email.ts                          ← NEW: sendEmail() utility for Edge Functions
│   └── email-templates/
│       ├── base-layout.ts                ← NEW: shared HTML header/footer
│       ├── customer/
│       │   ├── welcome.ts                ← C1
│       │   ├── order-confirmation.ts     ← C2
│       │   ├── coupon-redeemed.ts        ← C3
│       │   ├── coupon-expiring.ts        ← C4
│       │   ├── auto-refund.ts            ← C5
│       │   ├── store-credit-added.ts     ← C6
│       │   ├── refund-requested.ts       ← C7
│       │   ├── refund-completed.ts       ← C8
│       │   ├── after-sales-submitted.ts  ← C9
│       │   ├── after-sales-approved.ts   ← C10
│       │   ├── after-sales-rejected.ts   ← C11
│       │   └── after-sales-merchant-replied.ts ← C13
│       ├── merchant/
│       │   ├── welcome.ts                ← M1
│       │   ├── verification-pending.ts   ← M2
│       │   ├── verification-approved.ts  ← M3
│       │   ├── verification-rejected.ts  ← M4
│       │   ├── new-order.ts              ← M5
│       │   ├── deal-expiring.ts          ← M6
│       │   ├── coupon-redeemed.ts        ← M7
│       │   ├── pre-redemption-refund.ts  ← M8
│       │   ├── after-sales-received.ts   ← M9
│       │   ├── after-sales-approved.ts   ← M10
│       │   ├── after-sales-rejected-escalated.ts ← M11
│       │   ├── platform-review-result.ts ← M12
│       │   ├── monthly-settlement.ts     ← M13
│       │   ├── withdrawal-received.ts    ← M14
│       │   └── withdrawal-completed.ts   ← M15
│       └── admin/
│           ├── merchant-application.ts   ← A2
│           ├── after-sales-escalated.ts  ← A5
│           ├── after-sales-closed.ts     ← A6
│           ├── large-refund-alert.ts     ← A7
│           ├── withdrawal-request.ts     ← A8
│           └── daily-digest.ts           ← A3/A4
├── send-auth-email/                      ← NEW: replace Supabase Auth emails
├── notify-expiring-coupons/              ← NEW: Cron Job (C4)
├── notify-expiring-deals/                ← NEW: Cron Job (M6)
├── monthly-settlement-report/            ← NEW: Cron Job (M13)
└── admin-daily-digest/                   ← NEW: Cron Job (A3/A4)

admin/lib/
└── email.ts                              ← NEW: sendEmail() for Next.js Server Actions
```

---

## 3. Database Changes

### 3.1 `email_logs` Table

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

-- 用于幂等性检查的索引
CREATE INDEX idx_email_logs_dedup
  ON email_logs (email_type, reference_id, recipient_email, created_at);

-- RLS: 仅 service_role 可读写
ALTER TABLE email_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "service_role_only" ON email_logs
  USING (auth.role() = 'service_role');
```

### 3.2 `admin_notification_settings` Table

```sql
CREATE TABLE admin_notification_settings (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  notification_type TEXT NOT NULL UNIQUE,
  -- 可通知的管理员邮件列表（JSON 数组，e.g. ["admin@crunchyplum.com"]）
  recipient_emails  JSONB NOT NULL DEFAULT '[]',
  enabled           BOOLEAN NOT NULL DEFAULT TRUE,
  description       TEXT,
  updated_at        TIMESTAMPTZ DEFAULT NOW(),
  updated_by        UUID REFERENCES users(id)
);

-- 预置所有管理员通知类型的默认记录
INSERT INTO admin_notification_settings (notification_type, description) VALUES
  ('merchant_application',    'New merchant verification application submitted'),
  ('after_sales_escalated',   'After-sales case escalated from merchant to platform'),
  ('after_sales_closed',      'Platform-level after-sales case resolved'),
  ('large_refund_alert',      'Single refund exceeds alert threshold ($500)'),
  ('withdrawal_request',      'New merchant withdrawal request submitted'),
  ('daily_digest',            'Daily summary of pending tasks');

-- RLS: admin 角色可读写
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

## 4. Complete Email Catalog

### 4.1 Customer Emails (C-Series)

| ID | Name | Trigger | Trigger Location | Key Data |
|----|------|---------|-----------------|----------|
| C1 | Welcome | User email verified | `send-auth-email` (new) | First name, app download links |
| C2 | Order Confirmation | Order successfully created | `create-order-v3` | Order number, deal list, quantities, amounts, expiry dates per coupon |
| C3 | Coupon Redeemed | Coupon scanned by merchant | `merchant-scan` | Merchant name, deal name, redemption time, store address |
| C4 | Coupon Expiring Soon | 3 days before coupon expiry | `notify-expiring-coupons` (Cron) | Deal name, expiry date, refund policy reminder |
| C5 | Coupon Expired — Auto Refund | `auto-refund-expired` runs | `auto-refund-expired` | Refund amount, refund method (store credit), balance after refund |
| C6 | Store Credit Added | Any store_credit refund succeeds | `create-refund` / `auto-refund-expired` | Amount added, new balance, how to use store credit |
| C7 | Refund Request Received | `create-refund` accepted | `create-refund` | Order number, refund amount, method (store credit / original payment), estimated timeline |
| C8 | Refund Completed (Stripe) | `stripe-webhook` charge.refunded | `stripe-webhook` | Refund amount, last 4 digits of card, 3-5 business days note |
| C9 | After-Sales Request Submitted | After-sales request created | `after-sales-request` | Case number, reason, 7-day review commitment, support email |
| C10 | After-Sales Approved | Platform approves refund | `platform-after-sales` | Refund amount, method, processing time |
| C11 | After-Sales Rejected | Platform rejects claim | `platform-after-sales` | Rejection reason, escalation options, support contact |
| C12 | Password Reset | User requests password reset | Supabase Auth custom template | Reset link (expires in 1 hour) |
| C13 | Merchant Replied to After-Sales | Merchant submits their response | `merchant-after-sales` | Merchant's response text, case status, next steps |

### 4.2 Merchant Emails (M-Series)

| ID | Name | Trigger | Trigger Location | Key Data |
|----|------|---------|-----------------|----------|
| M1 | Welcome | Merchant registration submitted | `merchant-register` | Business name, verification steps, dashboard link |
| M2 | Verification Pending | Documents uploaded and under review | `merchant-register` | Application ID, estimated review time (1-3 business days) |
| M3 | Verification Approved | Admin approves merchant | `admin/app/actions/admin.ts → approveMerchant` | Activated features list, commission-free period end date, dashboard link, guide to first deal |
| M4 | Verification Rejected | Admin rejects merchant | `admin/app/actions/admin.ts → rejectMerchant` | Rejection reason, list of documents to resubmit, resubmission link |
| M5 | New Order Received | Order created involving merchant's deal | `create-order-v3` | Order number, deal name, quantity, coupon expiry dates, dashboard link |
| M6 | Deal Expiring Soon | 7 days before deal expires | `notify-expiring-deals` (Cron) | Deal name, expiry date, total sold, unredeemed coupon count |
| M7 | Coupon Successfully Redeemed | Scan completed | `merchant-scan` | Masked coupon code, deal name, redemption amount, today's total redemptions |
| M8 | Pre-Redemption Refund Notice | Customer refunds unused coupon | `create-refund` | Order number, refund amount, updated available stock |
| M9 | After-Sales Claim Received | Customer submits after-sales | `after-sales-request` | Case number, customer's reason, evidence description, 48-hour response deadline |
| M10 | After-Sales Approved (Merchant) | Merchant approves refund | `merchant-after-sales` | Case number, refund amount, customer notification confirmation |
| M11 | After-Sales Rejected — Escalated | Merchant rejects, case goes to platform | `merchant-after-sales` | Case number, merchant's rejection reason, platform review timeline (3 business days) |
| M12 | Platform Review Result | Platform issues final decision | `platform-after-sales` | Final decision (approved/rejected), reason, financial impact on merchant |
| M13 | Monthly Settlement Report | 1st of each month | `monthly-settlement-report` (Cron) | Month, gross redemptions, refunds, net earnings, commission, payout amount |
| M14 | Withdrawal Request Received | Merchant submits withdrawal | `merchant-withdrawal` | Amount, bank account (last 4 digits), estimated processing time |
| M15 | Withdrawal Completed | Admin marks withdrawal as completed | Admin action | Amount, transaction reference number |
| M16 | Deal Rejected by Admin | Admin rejects a submitted deal | `admin/app/actions/admin.ts → rejectDeal` | Deal name, rejection reason, required changes, resubmission link |

### 4.3 Admin Emails (A-Series)

> Admin recipients for each category are managed in the admin dashboard under **Settings → Notification Recipients**.

| ID | Name | Trigger | Trigger Location | Key Data |
|----|------|---------|-----------------|----------|
| A1 | Admin Account Created | New admin user created | Admin action | Username, temporary password, dashboard link |
| A2 | New Merchant Application | Merchant submits registration | `merchant-register` | Merchant name, submitted documents, review link in admin dashboard |
| A3 | Daily Digest | Every day at 9:00 AM CT | `admin-daily-digest` (Cron) | Pending merchant verifications, pending after-sales cases, pending withdrawals |
| A4 | Large Refund Alert | Single refund exceeds $500 | `create-refund` / `admin-refund` | Refund amount, user ID, order number, manual review prompt |
| A5 | After-Sales Case Escalated | Merchant rejects, escalated to platform | `merchant-after-sales` | Case number, full event timeline, customer evidence, merchant's rejection reason, review link |
| A6 | After-Sales Case Closed | Platform issues final decision | `platform-after-sales` | Case number, final decision, reviewer ID, case summary |
| A7 | New Withdrawal Request | Merchant submits withdrawal | `merchant-withdrawal` | Merchant name, amount, bank account info, approval link |
| A8 | System Error Alert | Critical exception caught in Edge Function | Any Edge Function error handler | Error type, function name, stack trace (abbreviated), affected user/order |

---

## 5. Implementation Details

### 5.1 `_shared/email.ts` (Edge Function Utility)

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
  emailType: string;       // used for email_logs.email_type
  referenceId?: string;    // used for email_logs.reference_id (UUID)
  recipientType: 'customer' | 'merchant' | 'admin';
}

export async function sendEmail(
  supabaseClient: SupabaseClient,
  payload: EmailPayload
): Promise<void> {
  const recipients = Array.isArray(payload.to) ? payload.to : [payload.to];

  for (const email of recipients) {
    // 幂等性检查：过去 24 小时内是否已发过同类邮件
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
      if (existing) continue;
    }

    // 插入 pending 日志
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

      // 更新日志为 sent
      await supabaseClient.from('email_logs').update({
        status: 'sent',
        smtp2go_message_id: result?.data?.email_id ?? null,
        sent_at: new Date().toISOString(),
      }).eq('id', logRow?.id);

    } catch (err) {
      // 更新日志为 failed，但不抛出异常
      await supabaseClient.from('email_logs').update({
        status: 'failed',
        error_message: String(err),
        retry_count: 1,
      }).eq('id', logRow?.id);
    }
  }
}
```

### 5.2 `admin/lib/email.ts` (Next.js Utility)

```typescript
// admin/lib/email.ts
// Next.js Server Actions 中调用，语法与 Edge Function 版本一致但使用 Node.js fetch

const SMTP2GO_API_URL = 'https://api.smtp2go.com/v3/email/send';

export interface AdminEmailPayload {
  to: string | string[];
  subject: string;
  htmlBody: string;
  emailType: string;
  referenceId?: string;
}

export async function sendAdminEmail(payload: AdminEmailPayload): Promise<void> {
  // 使用 service_role 客户端写 email_logs，忽略失败
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
    // 静默失败 — 邮件发送不阻断管理员操作
  }
}

// 从数据库读取指定类型的管理员收件人列表
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

### 5.3 Base Email Template Layout

All templates extend a shared base layout with:
- DealJoy logo (hosted on Supabase Storage)
- Brand color: primary brand color
- Footer: unsubscribe note, crunchyplum.com address, social links
- Mobile-responsive layout (max-width 600px, inline CSS)
- Font: system-ui, -apple-system, sans-serif

### 5.4 Supabase Auth Custom Email (C1, C12)

Replace Supabase default auth emails via the **Auth → Email Templates** section in Supabase Dashboard:
- **Confirm Signup**: branded welcome with verification button
- **Reset Password**: branded reset with time-expiry notice
- **Magic Link**: if used, branded magic link

Alternatively, use the `GOTRUE_SMTP_*` environment variables with SMTP2GO's SMTP endpoint for consistent sending via the same domain.

### 5.5 New Edge Functions (Cron Jobs)

#### `notify-expiring-coupons` (Daily at 8:00 AM CT)
```sql
-- Query: find order_items expiring in exactly 3 days
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
Sends C4 to each customer. Deduplication via `email_logs`.

#### `notify-expiring-deals` (Daily at 9:00 AM CT)
```sql
-- Query: find deals expiring in exactly 7 days
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
Sends M6 to the primary merchant account email.

#### `monthly-settlement-report` (1st of each month at 6:00 AM CT)
Queries `merchant_earnings` view for the previous month. Sends M13 to each active merchant.

#### `admin-daily-digest` (Daily at 9:00 AM CT)
Queries counts for: pending merchant verifications, open after-sales cases, pending withdrawals, flagged refunds. Sends A3 to admin recipients configured for `daily_digest`.

---

## 6. Existing Edge Functions — Modification Summary

| Function | Changes Required | Emails Added |
|----------|-----------------|--------------|
| `create-order-v3` | Add `sendEmail()` call after order created | C2, M5 |
| `merchant-scan` | Add `sendEmail()` after successful scan | C3, M7 |
| `create-refund` | Add `sendEmail()` based on refund type; check $500 threshold | C6, C7, M8, A4 |
| `auto-refund-expired` | Add `sendEmail()` per expired item | C5, C6 |
| `stripe-webhook` | Add `sendEmail()` on `charge.refunded` event | C8 |
| `after-sales-request` | Add `sendEmail()` for 3 parties | C9, M9, A5 |
| `merchant-after-sales` | Add `sendEmail()` for approve/reject paths | C13, M10, M11 |
| `platform-after-sales` | Add `sendEmail()` for final decision | C10, C11, M12, A6 |
| `merchant-register` | Add `sendEmail()` on successful registration | M1, M2, A2 |
| `merchant-withdrawal` | Add `sendEmail()` on new withdrawal request | M14, A7 |

| Admin Server Action | Changes Required | Emails Added |
|--------------------|-----------------|--------------|
| `approveMerchant` | Call `sendAdminEmail()` after DB update | M3 |
| `rejectMerchant` | Call `sendAdminEmail()` after DB update | M4 |
| `rejectDeal` | Call `sendAdminEmail()` after DB update | M16 |
| New withdrawal approval action | Call `sendAdminEmail()` on status update | M15 |

---

## 7. Admin Dashboard Changes

### New Page: `/settings/notifications`

A settings page in the admin Next.js app allowing admins to:
- View all notification types (A-series)
- Add/remove recipient email addresses per notification type
- Toggle individual notification types on/off
- View recent send history (queries `email_logs` filtered by `recipient_type = 'admin'`)

```
admin/app/(dashboard)/settings/
└── notifications/
    └── page.tsx        ← Server Component + Client form
admin/components/
└── notification-settings-form.tsx  ← Client Component
admin/app/actions/
└── email-settings.ts   ← Server Actions: updateNotificationRecipients, toggleNotification
```

### New Page: `/settings/email-logs`

A read-only log viewer for admins to monitor email delivery health:
- Filter by `email_type`, `status`, `recipient_type`, date range
- Shows `smtp2go_message_id`, `error_message`, `retry_count`

---

## 8. SMTP2GO Configuration Checklist

Before development begins, complete these steps:

- [ ] **Create SMTP2GO account** at smtp2go.com
- [ ] **Add sending domain**: `crunchyplum.com`
- [ ] **Configure DNS records** on crunchyplum.com:
  - SPF record: `v=spf1 include:mailgun.org ~all` → replace with SMTP2GO's SPF value
  - DKIM record: provided by SMTP2GO (TXT record)
  - DMARC record: `v=DMARC1; p=none; rua=mailto:dmarc@crunchyplum.com`
- [ ] **Create sender**: `noreply@crunchyplum.com`
- [ ] **Generate API key** in SMTP2GO → save as Supabase Secret `SMTP2GO_API_KEY`
- [ ] **Add to Supabase Secrets**:
  ```
  SMTP2GO_API_KEY=<key>
  ```
- [ ] **Add to admin `.env.local`**:
  ```
  SMTP2GO_API_KEY=<same key>
  ```
- [ ] **Configure Supabase Auth SMTP** (for C1/C12):
  - Settings → Authentication → SMTP Settings
  - Host: `mail.smtp2go.com`, Port: `587`
  - Username/Password: SMTP2GO credentials

---

## 9. Phased Development Plan

### Phase 1 — Infrastructure (Complete First)

**Goal:** All shared utilities, DB tables, and SMTP2GO are production-ready before any email is sent.

- [ ] SMTP2GO setup and domain DNS verification (crunchyplum.com)
- [ ] Migration `20260321000001_email_system.sql` — `email_logs` + `admin_notification_settings` tables
- [ ] `_shared/email.ts` — Edge Function sending utility
- [ ] `_shared/email-templates/base-layout.ts` — shared HTML layout
- [ ] `admin/lib/email.ts` — Next.js sending utility
- [ ] Supabase Auth custom email templates (C1 Welcome, C12 Password Reset)
- [ ] Seed `admin_notification_settings` with all A-series types

**Verification:** Send a test email from both utilities. Confirm log appears in `email_logs`.

---

### Phase 2 — Customer Core Transaction Emails

**Goal:** Highest-impact emails covering the main purchase and refund journey.

- [ ] C2 — Order Confirmation (`create-order-v3`)
- [ ] C3 — Coupon Redeemed (`merchant-scan`)
- [ ] C7 — Refund Request Received (`create-refund`)
- [ ] C8 — Refund Completed via Stripe (`stripe-webhook`)
- [ ] C5/C6 — Auto-Refund + Store Credit Added (`auto-refund-expired`)

---

### Phase 3 — Merchant Core Emails

**Goal:** Merchants are informed of all critical business events.

- [ ] M1/M2 — Welcome + Verification Pending (`merchant-register`)
- [ ] M3/M4 — Verification Approved/Rejected (`admin/actions/admin.ts`)
- [ ] M5 — New Order (`create-order-v3`)
- [ ] M7 — Coupon Redeemed (`merchant-scan`)
- [ ] M8 — Pre-Redemption Refund (`create-refund`)
- [ ] M16 — Deal Rejected by Admin (`admin/actions/admin.ts`)

---

### Phase 4 — After-Sales Email Flow

**Goal:** All three parties (customer, merchant, admin) are kept informed throughout the after-sales process.

- [ ] C9 + M9 + A5 — After-Sales Submitted (`after-sales-request`)
- [ ] C13 + M10/M11 — Merchant Response (`merchant-after-sales`)
- [ ] C10/C11 + M12 + A6 — Platform Decision (`platform-after-sales`)

---

### Phase 5 — Scheduled / Cron Emails

**Goal:** Proactive reminders to reduce churn and keep merchants engaged.

- [ ] C4 — Coupon Expiring (new `notify-expiring-coupons` Cron, daily)
- [ ] M6 — Deal Expiring (new `notify-expiring-deals` Cron, daily)
- [ ] A3 — Admin Daily Digest (new `admin-daily-digest` Cron, daily 9 AM CT)
- [ ] M13 — Monthly Settlement Report (new `monthly-settlement-report` Cron, monthly)

---

### Phase 6 — Admin Dashboard & Remaining Emails

**Goal:** Full admin visibility and remaining emails.

- [ ] Admin `/settings/notifications` page
- [ ] Admin `/settings/email-logs` page
- [ ] A4 — Large Refund Alert (`create-refund` threshold check, $500)
- [ ] A7 + M14 — Withdrawal Request (`merchant-withdrawal`)
- [ ] M15 + Admin withdrawal approval action
- [ ] A8 — System Error Alert (shared error handler in `_shared/error.ts`)

---

## 10. Open Questions (Resolved)

| Question | Answer |
|----------|--------|
| Admin tech stack | Next.js 15 App Router (`admin/` directory) |
| Admin email recipient management | `admin_notification_settings` table, editable in admin dashboard |
| Sending domain | crunchyplum.com |
| Supabase Auth emails | Replace with SMTP2GO-delivered branded templates |
| Email language | English only (North America / Dallas market) |
| Admin backend location | `admin/app/actions/admin.ts` — Server Actions pattern |

---

## 11. Email Type Reference (Quick Lookup)

| Code | Name | Phase |
|------|------|-------|
| C1 | Customer Welcome | 1 |
| C2 | Order Confirmation | 2 |
| C3 | Coupon Redeemed (Customer) | 2 |
| C4 | Coupon Expiring Soon | 5 |
| C5 | Auto-Refund on Expiry | 2 |
| C6 | Store Credit Added | 2 |
| C7 | Refund Request Received | 2 |
| C8 | Refund Completed (Stripe) | 2 |
| C9 | After-Sales Submitted | 4 |
| C10 | After-Sales Approved | 4 |
| C11 | After-Sales Rejected | 4 |
| C12 | Password Reset | 1 |
| C13 | Merchant Replied to After-Sales | 4 |
| M1 | Merchant Welcome | 3 |
| M2 | Verification Pending | 3 |
| M3 | Verification Approved | 3 |
| M4 | Verification Rejected | 3 |
| M5 | New Order Received | 3 |
| M6 | Deal Expiring Soon | 5 |
| M7 | Coupon Redeemed (Merchant) | 3 |
| M8 | Pre-Redemption Refund Notice | 3 |
| M9 | After-Sales Claim Received | 4 |
| M10 | After-Sales Approved (Merchant) | 4 |
| M11 | After-Sales Rejected — Escalated | 4 |
| M12 | Platform Review Result | 4 |
| M13 | Monthly Settlement Report | 5 |
| M14 | Withdrawal Request Received | 6 |
| M15 | Withdrawal Completed | 6 |
| M16 | Deal Rejected by Admin | 3 |
| A1 | Admin Account Created | 1 |
| A2 | New Merchant Application | 3 |
| A3 | Admin Daily Digest | 5 |
| A4 | Large Refund Alert | 6 |
| A5 | After-Sales Case Escalated | 4 |
| A6 | After-Sales Case Closed | 4 |
| A7 | New Withdrawal Request | 6 |
| A8 | System Error Alert | 6 |
