# 账户删除 — 外键与 §4.4 定稿附录（T0）

> 与 [客户端账户删除计划](./2026-05-08-deal-joy-account-deletion-customer.md) §4.4、§7.1 对齐。  
> **匿名占位用户**：固定 UUID `a0000001-0000-4000-8000-000000000001`（迁移 `20260508100000_account_deletion_support.sql` 写入 `auth.users` + `public.users`）。  
> **订单 `user_id` 策略**：整账号 `full` 收尾前，将仍须保留财务链路的 `orders.user_id`（及同类字段）**批量更新为上述占位 ID**，再执行 `auth.admin.deleteUser(真实用户)`；禁止依赖「删 `auth.users` 级联删订单」。

## §4.4 行为 — 已确认（T0 Done）

| 域 | 已确认行为 |
|----|------------|
| `saved_deals` / 收藏 | **硬删除**该用户相关行 |
| `reviews` | **匿名化**：`reviewer_user_id`（若存在）→ 占位 ID；正文保留 |
| `friends` / `chat` / 会话 | **占位用户**：消息/会话侧 `user_id`/`sender_id`/`receiver_id` 等改为占位 ID；不级联删全会话 |
| `referral` / `users.referral_code` | **解除**：子用户 `referred_by` 置 `NULL`；被删用户 `referral_code` 置空或废弃 |
| `push` / device token | **删除** `user_fcm_tokens` 等该用户行 |
| `marketing_opt_in` / 邮件偏好 | 随 `public.users` 行删除（在 `auth` 删除前已脱敏/或已由占位行承接的业务外键处理） |

## `public.users(id)` 引用（迁移 grep 汇总）

> 下列自 `deal_joy/supabase/migrations/*.sql` 检索 `REFERENCES ...users(id)`；`ON DELETE` 未写明时为默认 **NO ACTION / RESTRICT**（删用户前须应用层或占位替换）。

| 表/列 | 迁移文件（示例） | ON DELETE |
|-------|------------------|-----------|
| `merchants.user_id` | `20260228000000_initial_schema.sql` | CASCADE（历史）— **删消费者会级联删门店**；删号流程须先闭店并 **改 FK / 置占位** 见迁移 |
| `orders.user_id` | initial | 默认 NO ACTION |
| `coupons.user_id` | initial | 默认 NO ACTION |
| `reviews.user_id` / `reviewer_user_id` | initial / `20260325000002` | 混合 |
| `saved_deals.user_id` | initial | 默认 |
| `cart_items.user_id` | `20260320000001` | CASCADE |
| `store_credits.user_id` | `20260320000001` | CASCADE |
| `store_credit_transactions.user_id` | `20260320000001` | 未声明 |
| `coupon_gifts.gifter_user_id` / `recipient_user_id` | `20260325000001` | 未声明 / 可空 |
| `coupons.current_holder_user_id` / `gifted_from_user_id` | gift 系列 | 未声明 |
| `refund_requests.user_id` 等 | `20260310000002` | 未声明 |
| `support_claims` | `20260428000002` | 部分 CASCADE |
| `referral_events` / `users.referred_by` | `20260429140000` | 未声明 |
| `chat` / `messages` / `friends` / `conversations` | `20260326000001` | 多为 CASCADE |
| `notifications` / `user_fcm_tokens` | `20260326000001` | CASCADE |
| `login_sessions` / `user_preferences` 等 | `20260301300000` 等 | CASCADE |
| `merchant_activity_events.actor_user_id` | `20260402140000` | SET NULL |
| `post_redemption_tips` | `20260423120000` | SET NULL |
| `geo_push_campaigns.created_by` | `20260426000002` | SET NULL |
| `ad_campaign_logs.actor_user_id` | `20260407000002` | 未声明 |
| `welcome_screens` / 运营表 `created_by` | `20260327000001` | 未声明 |
| `sponsor_bids.user_id` | `20260401000001` | 未声明 |
| `legal_documents.published_by` | `20260407100001` | 未声明 |
| `recommendation_*` | `20260326000002` | 多为 CASCADE |

## `auth.users(id)` 引用（节选）

| 表/列 | 说明 |
|-------|------|
| `public.users.id` | PK → auth，**ON DELETE CASCADE**（删 auth 则删 public profile） |
| `brand_admins` / `merchant_staff` / `merchant_invitations` | `20260307000001` 等 |
| `merchant_scan` / `merchant_adjustments` / `deal_templates` | 审计/创建者 |
| `order_items.redeemed_by` | 核销人 |
| `after_sales_refund_requests.user_id` | CASCADE |
| `merchant_fcm_tokens` / 商家侧 | 若干 |

## RLS 注意

删号使用 **service_role** 的 Edge Function，绕过 RLS；占位用户仅用于 FK 完整性，**不用于真实登录**。

---

**文档结束**
