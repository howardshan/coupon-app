# Stripe Connect 解绑申请 v1 规格

**文档版本**: v1.4  
**创建日期**: 2026-04-08  
**受众**: 产品、研发（DealJoy 全栈：Admin Next.js、商家端 Flutter、Supabase）  
**状态**: Sprint 1–4 已按清单落地；Sprint 5 待实现  

---

## 变更记录

| 版本 | 日期 | 变更内容 |
| ---- | ---- | -------- |
| v1.0 | 2026-04-08 | 初版：与产品确认口径一致，附实现清单（对齐仓库现成模式） |
| v1.1 | 2026-04-08 | 实现清单拆为 Sprint 1–5，保留与原 §5.1–5.7 条目的映射 |
| v1.2 | 2026-04-08 | 同步 Sprint 1、Sprint 2 已交付内容：迁移路径、Edge 路由、M19 模板、预检与 API 说明 |
| v1.3 | 2026-04-08 | Sprint 3 落地：Admin 审批、解绑、M20/M21、审计 event、商家详情卡；`20260419100000` |
| v1.4 | 2026-04-08 | Sprint 4 落地：商家端 `EarningsService` 拉取/提交解绑 API、`Payment Account` 与 `Brand Stripe Connect` 双入口、状态条与底部申请表单、Riverpod 列表 provider |

---

## 一、背景与目标

### 1.1 问题

- 平台侧与 Stripe 的**绑定关系**存于 `merchants` / `brands` 等表；**应用内无安全、可审计的解绑能力**，仅靠手工改库或客服流程。
- 商家有**换绑 / 解除当前 Connect** 的诉求，直连「后台 SQL 解绑」风险高、无留痕。

### 1.2 目标（v1）

1. 商家在**商家端**发起**解绑申请**（非自助立即解绑）。
2. 管理员在 **Admin 统一审批中心** 审批；通过后由系统执行**仅平台库解绑**（见下文 Stripe 边界）。
3. 全流程 **邮件通知** 商家；关键操作**审计**可追溯。
4. 管理端在**商家详情**侧栏展示**只读** Connect 状态，并**跳转审批中心/待办**；**不**在详情页提供「绕过审批」的解绑按钮（与审批单联动、权限一致时除外，见 5.3）。

---

## 二、范围说明

| 包含（v1） | 不包含（v1 之后） |
| ---------- | ---------------- |
| 商家申请、管理员通过/拒绝（拒填理由） | 商家端**撤回**申请 |
| 邮件：提交成功、通过、拒绝（含理由） | **应用内推送 / 站内信**（二期） |
| 平台库解绑 + 审计 | 在 Stripe Dashboard **代商家销户** 等非必要 API |
| 单店 + 品牌两条主体下的申请与展示 | 与现网「多实体」变体未覆盖的极小众边界（需迭代补 PRD） |

**文案语言**：与现网一致，**面向北美的用户可见文案为英文**；本规格可中英思路并存，实现时 UI/邮件为英文。

---

## 三、产品规格

### 3.1 解绑对象（单店 vs 品牌）

| 身份/场景 | 解绑作用域 | 数据侧锚点（实现时以代码为准） |
| --------- | ---------- | ----------------------------- |
| **单店商家** | 仅**当前门店**对应的 Connect 绑定 | 一般为 `merchants` 上 `stripe_account_id` / 状态等 |
| **品牌商家** | **整品牌**维度的 Connect 绑定 | 一般为 `brands`（或项目内品牌级 Stripe 字段，见 `merchant-brand` 相关表） |

**原则**：以「当前在 **Payment Account** 中管理的那条 Connect」所对应的**业务主体**为准，与 `resolveAuth()` / 品牌切换后的 `X-Merchant-Id` 等现有一致，避免错绑到兄弟门店/其它品牌。

### 3.2 前置条件（不满足则**禁止提交申请**，并提示需先处理）

在提交接口或表单提交前做校验；不满足时给出**明确英文提示**（示例口径）：

- 存在**待结算 / 在途打款**（以现有可查询状态为准，如 `merchant_earnings`、提现/结算任务等——**由研发在实现清单中落具体表/RPC**）。
- 存在**支付争议 / chargeback 未结**（若可判）。
- 存在**负余额**或其它你们定义的**阻塞性风控状态**。

*注：若某类状态当前库中尚不可查，v1 可先实现「能查的 subset」，余量在文档/代码 TODO 中列出。*

### 3.3 解绑在系统中的语义（**与产品确认**）

- **审批通过后**的系统动作：**仅更新平台库**——清除（或置空）当前主体上的 Connect 相关字段、将状态置为与「未连接」一致；**不**在 v1 强制调用 Stripe 侧删除/关闭 Connected Account。Stripe 侧历史账户、账务、老订单的 charge/dispute 按 **Stripe 政策**保留。
- **新订单**收款在解绑后应走「未连接」后的流程；**老订单/售后**在**业务上**可仍与历史支付记录、Stripe 侧历史数据关联，产品对外说明一句即可（邮件/帮助里英文简短说明），避免用户误以为「解绑=抹掉历史资金关系」。

### 3.4 申请状态机

| 状态 | 说明 |
| ---- | ---- |
| `pending` | 待审；**同一主体下同时仅允许一条** `pending` |
| `approved` | 已批准且**解绑已执行**（或幂等标记已执行） |
| `rejected` | 已拒绝；须保存 `rejected_reason`（管理员填写） |

- **不**在 v1 做商家「取消/撤回」。
- **不**允许在已存在 `pending` 时再次提交（接口返回 409 或业务错误码，前端提示）。

### 3.5 申请内容

- 必选：**解绑原因类别** 或 简短**说明**（用于审批与客服追溯）。
- 与已有优化点一致：拒绝邮件、通过邮件中可带 **Request ID、提交时间、当前状态**；**Payment Account** 页可查询**申请状态/历史**（只读列表或单条 `pending` 状态即可，v1 可最小实现）。

### 3.6 管理端双入口

| 入口 | 行为 |
| ---- | ---- |
| **审批中心** `/approvals` | 主流程：新 Tab/类型「Stripe Unlink」或统一命名；列表 + 抽屉详情；**通过 / 拒绝**（拒填理由）；与现有 `After-Sales` / `Refund` 抽屉模式一致。 |
| **商家详情** `/merchants/[id]` 右侧边栏**卡片** | **只读**展示：当前 Connect 状态摘要、`acct_` 后四位/邮箱（若有）、**最近一条**申请状态；**链接**：「**Review in Approvals Center →**」`href=/approvals?tab=...`（与现网 `admin/app/(dashboard)/merchants/[id]/page.tsx` 中同模式一致）。**不**放「无需审批的直接解绑」避免绕过。 |

*超级管理员/特权直连解绑*：**v1 不开放**；若将来需要，须独立 PRD 且与申请单/审计强绑定。

### 3.7 通知（邮件）

| 事件 | 收件人 | 内容要点 |
| ---- | ------ | -------- |
| 商家成功提交 | 商家联系邮箱 | 已提交、Request ID、时间、可在 Payment Account 查看状态（英文） |
| 审批**通过** | 同上 | 已解绑（平台侧）、对后续收款的说明一句、可重新连接（英文） |
| 审批**拒绝** | 同上 | 拒绝；**必须含管理员填写的理由**；可附下一步建议（联系 support 等）（英文） |

发送链路、开关、记录：与现有 [邮件系统](./2026-03-21-email-system.md) 一致——`deal_joy/supabase/functions/_shared/email.ts` + `email_type_settings` + `email_logs`；新增 `email_type` 需在 DB 中注册，并在 `email_type_settings` 中可配。

### 3.8 审计

以下事件建议写入现有 **`merchant_activity_events`**（或等价的 admin 审计表，与项目 `COMPLETED.md` 中 Admin 商户活动时间线模块同风格）：

- 申请创建（申请人、主体 id、申请单 id）
- 通过 / 拒绝（操作者 admin id、申请单 id、拒绝理由若拒绝）
- **平台库解绑执行成功**（幂等、可重试的 worker 也记成功/失败原因）

---

## 四、非功能需求

- **幂等**：管理端「通过」重复点击/重试不导致双次错误副作用；解绑 `UPDATE` 以「目标状态」为准。
- **安全**：仅 **Admin 已认证** 可审批；商家仅可操作**本账号有权**的主体；所有写操作走 RLS/Service Role 的既定模式。
- **可观测性**：关键步骤打结构化日志，便于对账与客服查询。

---

## 五、实现清单（按仓库现成模式拆解）

> 以下路径以本仓库为基准；表名/函数名可在详细设计时微调，但**模式应复用**。

### 5.0 迭代总览

| Sprint | 目标 | 依赖 | 原章节映射 |
| ------ | ---- | ---- | ---------- |
| **Sprint 1** | 落库 + 邮件类型 + RLS，无业务 UI | 无 | §5.1 — **已完成**（见下「Sprint 1 落地」） |
| **Sprint 2** | 商家可提交申请 +「已提交」邮件 + 预检最小集 | Sprint 1 | §5.2（最小）、§5.3 提交侧、§5.4 之一 — **已完成**（见下「Sprint 2 落地」） |
| **Sprint 3** | 管理端审批、通过时平台库解绑、拒审理由、两封结果邮件、审计 | Sprint 1–2 | §5.3 解绑、§5.4 余下、§5.5（不含 All）— **已完成** |
| **Sprint 4** | 商家端 Flutter：Payment Account + 品牌 Connect 解绑/状态，与 Sprint 2 API 对齐 | Sprint 2 | §5.6 — **已完成**；Admin 商家详情侧栏卡为 **Sprint 3** |
| **Sprint 5** | 全链路测试、预检补全、可选 All Tab、上线清单 | Sprint 1–4 | §5.2 补全、§5.5 All、§5.7 |

**建议排期顺序**：1 → 2 与 3 可部分并行（3 需等表与 Service 解绑函数设计定稿）→ 4 依赖 2 的 API → 5 收尾。

---

### Sprint 1 — 数据层与邮件类型

**目标**：可安全写入/读取申请单主表；邮件开关位预留。

- [x] 新建 `stripe_connect_unlink_requests`（列见原 §5.1：`id`, `subject_type`, `subject_id`, `merchant_id`, `requested_by_user_id`, `status`, 原因字段, `rejected_reason`, 审核人/时间, 时间戳, `unbind_applied_at` 等）。
- [x] **部分唯一约束**：同一 `subject` 仅一条 `pending`（部分唯一索引 `uq_stripe_unlink_one_pending_per_subject`）。
- [x] **RLS**：商家 `SELECT/INSERT` 限本主体（`can_access_stripe_unlink_request` + `INSERT` 校验 `merchant`/`brand` 与 `merchant_id` 一致）；`is_admin()` 读全表；**无** `UPDATE/DELETE` 对 `authenticated`（审批/解绑走 service_role / Server Action）。
- [x] **`email_type_settings` + 新邮件类型**：`M19` / `M20` / `M21` 预置（`ON CONFLICT DO NOTHING`），与现网风格一致。
- [x] 表/列 `COMMENT ON`；辅助函数 `can_access_stripe_unlink_request(subject_type, subject_id)`；`updated_at` 触发器接 `update_updated_at_column()`。

**落地文件**：`deal_joy/supabase/migrations/20260418120000_stripe_connect_unlink_requests.sql`

**对应原清单**：原 **§5.1 数据库** 全部。

**交付物**：`db push` 可应用；无前端依赖。部署后须先应用此 migration 再部署含 Sprint 2 的 Edge。

---

### Sprint 2 — 商家提交 API +「已提交」邮件 + 预检（最小）

**目标**：商家端/HTTP 可创建 `pending` 单并收到「申请已提交」邮件；预检先实现**能落地的子集**（余量 `TODO`）。

- [x] **预检**（原 §5.2 最小集）  
  - 已存在 `pending` 申请：DB 唯一 + `INSERT` 失败 → **409**（重复键/唯一冲突）。  
  - 当前 `X-Merchant-Id` 对应门店存在 **pending / processing 提现** → **409**（需先等提现完成）。  
  - **无 Stripe 可解绑**：`subject_type=merchant` 时要求 `merchants.stripe_account_id` 非空；若单店无 Connect 但品牌有 **品牌级** Connect，返回 **400** 并提示由品牌主在品牌侧处理。`subject_type=brand` 时要求 `brands.stripe_account_id` 非空。  
  - 品牌解绑仅 **`brand_owner`** 可 `POST`；`POST` 仍要求 `auth.role` 为 `store_owner` 或 `brand_owner`（与 Connect 同口径）。  
  - 代码中 **`// TODO(Sprint5)`**：争议、负余额、待结算/在途分账等，与 §3.2 余量一致。
- [x] **Edge**（`merchant-withdrawal` 子路由，**未**新增独立 Function）：`POST` 使用 **用户 JWT 客户端**写表以通过 RLS；`resolveAuth` + `requirePermission(…, "finance")`；`sendEmail` + **`emailCode: "M19"`**、`referenceId` = 申请行 `id`；`merchantId` 用于 `merchant_email_preferences` 等。
- [x] **邮件模板 1/3**：`deal_joy/supabase/functions/_shared/email-templates/merchant/stripe-unlink-submitted.ts`（`buildM19Email`，全英文）。
- [x] **只读 GET**：`GET /stripe-unlink?scope=merchant|brand`（默认 `merchant`），返回 `items` 列表（最近 20 条），供 Sprint 4 拉状态。

**API 约定（相对 function 根路径，与现网 `merchant-withdrawal` 一致）**

| 方法 | 路径 | 说明 |
| ---- | ---- | ---- |
| `GET` | `stripe-unlink?scope=merchant` 或 `?scope=brand` | 需 `Authorization` + `X-Merchant-Id`（及现有 finance 权限链） |
| `POST` | `stripe-unlink/request` | Body JSON：`subject_type`（`merchant` \| `brand`）、可选 `request_note`；仅 **store_owner / brand_owner** 可提交 |

**落地文件**：`deal_joy/supabase/functions/merchant-withdrawal/index.ts`（`handleGetStripeUnlinkRequests`、`handlePostStripeUnlinkRequest`）、上列 M19 模板。

**对应原清单**：**§5.2**（最小）、**§5.3** 的「商家提交」半段、**§5.4** 的 submitted。

**交付物**：Postman/curl 可通；Email Log 可见 M19（或关 `global_enabled` 仅走日志）。部署命令：`supabase functions deploy merchant-withdrawal`（并确保 DB 已含 Sprint 1 迁移与 M19–M21 记录）。

---

### Sprint 3 — 管理端审批 + 平台库解绑 + 结果邮件 + 审计

**目标**：审批中心可处理；通过则**仅平台库**解绑；拒绝必填理由；三封邮件闭环后两封。

- [x] **解绑纯函数/共享逻辑**：`admin/lib/stripe-unlink-platform.ts` 中 `applyPlatformStripeUnlink`（`merchant`：清该店 `merchants` + 删 `merchant_bank_accounts`；`brand`：清 `brands`、同 `brand_id` 下全部门店 Stripe 展示字段、逐店删 `merchant_bank_accounts`）。**不**调 Stripe 删户；可重复执行（再清一次空值）。
- [x] **Server Actions**：`admin/app/actions/stripe-unlink-approvals.ts` — `approveStripeUnlinkRequest` / `rejectStripeUnlinkRequest`；拒审理由 **≥10 字**；通过时先解绑再 `UPDATE` 申请行 `status/approved` + `unbind_applied_at`；`service_role` 写库（绕过 RLS）。已批准且已 `unbind_applied_at` 的再次调用直接返回（幂等）。
- [x] **邮件 M20 / M21**：`admin/lib/email-templates/merchant/stripe-unlink-approved.ts`、`stripe-unlink-rejected.ts`；`sendAdminEmail`，`emailCode` M20/M21，`referenceId` = 申请 `id`。
- [x] **Admin 审批中心（不含 All 合并）**：`approvals/page.tsx` 拉取列表 + `fetchCounts` 含 `stripe_connect_unlink_requests` pending；`approvals-page-client` 新 Tab **Stripe Unlink**、Pending/History、列表行与 `StripeUnlinkDrawer`（通过 / 拒审表单）。
- [x] **商家详情侧栏**：`merchants/[id]/page.tsx` 只读卡 + 链至 `/approvals?tab=stripe-unlink` 或 `…&queue=history`；按本店 `merchant` 与（若有）`brand` 两条 subject 取**较新**一条申请。
- [x] **审计**：迁移 `20260419100000_merchant_activity_stripe_unlink.sql` 扩展 `event_type`：`stripe_unlink_approved` / `stripe_unlink_rejected`；`logMerchantActivityServer` 在通过/拒绝后写入；`merchant-admin-timeline` 英文标题。

**对应原清单**：**§5.3 解绑执行**、**§5.4** 余下、**§5.5**（先不做 All 合并）。

**交付物**：部署顺序：先 `db push`（含 `20260419100000`），再部署 Admin。管理员在 Staging 可走通通过/拒审与邮件、商家详情时间线出现新事件。

---

### Sprint 4 — 商家端 Flutter + 品牌入口

**目标**：商家在 App 内发起申请、看到状态/反馈；与 API 合同对齐。

- [x] `payment_account_page.dart`：已连接时 **Request to Unlink Stripe**、底部表单单选「可选说明」+ 提交/取消、调 `POST …/stripe-unlink/request`（`subject_type: merchant`）；**仅** `store_owner` / `brand_owner` 显示主按钮；`How does unlinking work?` 政策说明。成功/失败 **SnackBar**；成功后 `invalidate` **`stripeAccountProvider`** + **`stripeUnlinkRequestsMerchantProvider`**。列表 **GET** `scope=merchant` 驱动状态条（`pending` / 最近历史）。
- [x] 品牌线：`lib/features/store/pages/brand_stripe_connect_page.dart` 平行入口：已连接时 **仅 `brand_owner`** 显示主按钮，**GET** `scope=brand` 状态条；`subject_type: brand` 提交；成功后 `invalidate` **`brandStripeAccountProvider`** + **`stripeUnlinkRequestsBrandProvider`**。`isBrandAdmin` 可拉取列表，非 owner 只读状态 + 英文说明。

**落地文件**

| 说明 | 路径 |
| ---- | ---- |
| 解绑行模型 + GET/POST 封装 | `dealjoy_merchant/lib/features/earnings/models/earnings_data.dart`（`StripeUnlinkRequestItem`）；`.../earnings/services/earnings_service.dart`（`fetchStripeUnlinkRequests` / `submitStripeUnlinkRequest`） |
| 列表 provider | `dealjoy_merchant/lib/features/earnings/providers/earnings_provider.dart`（`stripeUnlinkRequestsMerchantProvider`、`stripeUnlinkRequestsBrandProvider`；依赖 `storeProvider` 切换门店重建） |
| 状态条 + 底部申请表单 | `dealjoy_merchant/lib/features/earnings/widgets/stripe_unlink_status_banner.dart`（`StripeUnlinkRequestStatusBanner`、`showStripeUnlinkRequestSheet`） |
| 单店页、品牌页 | `dealjoy_merchant/lib/features/earnings/pages/payment_account_page.dart`；`dealjoy_merchant/lib/features/store/pages/brand_stripe_connect_page.dart` |

**注**：Sprint 3 已覆盖 **「商家详情侧栏卡」**（Admin）；本 Sprint 4 不重复，仅做 **商家端 App**。

**对应原清单**：原 **§5.6 商家端** 全部。

**交付物**：真机/模拟器可提单；与 Sprint 2/3 联调走真实 Edge（**无** Mock 桩）；E2E 全链路验收归入 **Sprint 5**。

---

### Sprint 5 — 预检补全、All Tab（可选）、测试与上线

**目标**：生产可上；与产品对「待结算/在途」等定义对齐。

- [ ] **预检补全**（原 §5.2 余量）：待结算、在途、争议、负余额等**以库表/RPC 可行为准**；不可行项关闭 TODO 或移入 v1.1。
- [ ] **（可选）All Tab**（原 §5.5）：扩展 `admin_pending_approvals_unified_page` 或文档约定二期；若本期不做，在 **§六** 明确「All 未含 Stripe Unlink」。
- [ ] **测试**（原 §5.7）：Staging E2E；拒审理由前后端双端校验；解绑后商家端 Refresh 为未连接。
- [ ] **上线**：`COMPLETED.md`、发版说明、Edge/migration/Admin 发布顺序（先库后 Function 后 Admin）。

**对应原清单**：**§5.2** 补全、**§5.5** 的 All（可选）、**§5.7** 全部。

**交付物**： sign-off 检查表 + 回滚说明（如仅回滚 Admin 不破坏已解绑数据）。

---

### 原分类速查（与上表 Sprint 对应）

| 原小节 | 内容 | Sprint |
| ------ | ---- | ------ |
| **§5.1** 数据库 | 表、约束、RLS、邮件类型 | 1 |
| **§5.2** 预检 | 阻塞条件 | 2（最小）+ 5（补全） |
| **§5.3** Edge / RPC | 提交 + 解绑 | 2 + 3 |
| **§5.4** 邮件 | 三封模板 | 2 + 3 |
| **§5.5** Admin | 审批页、抽屉、侧栏、All 可选 | 3 + 5 |
| **§5.6** Flutter | 商家端 | 4 |
| **§5.7** 测试上线 |  | 5 |

### 5.8 参考文件（不修改本清单内容时仅作开发指引）

- **Sprint 1–2 已落地路径**：`deal_joy/supabase/migrations/20260418120000_stripe_connect_unlink_requests.sql`；`deal_joy/supabase/functions/merchant-withdrawal/index.ts`（含 `GET/POST …/stripe-unlink`）；`deal_joy/supabase/functions/_shared/email-templates/merchant/stripe-unlink-submitted.ts`（M19）
- **Sprint 4 商家端 Flutter**：`dealjoy_merchant/lib/features/earnings/pages/payment_account_page.dart`、`dealjoy_merchant/lib/features/store/pages/brand_stripe_connect_page.dart`；`dealjoy_merchant/lib/features/earnings/services/earnings_service.dart`；`dealjoy_merchant/lib/features/earnings/providers/earnings_provider.dart`；`dealjoy_merchant/lib/features/earnings/widgets/stripe_unlink_status_banner.dart`
- 统一审批：[`admin/app/(dashboard)/approvals/page.tsx`](../admin/app/(dashboard)/approvals/page.tsx)、[`approvals-page-client.tsx`](../admin/components/approvals-page-client.tsx)
- 邮件与日志：[邮件系统总览](2026-03-21-email-system.md)、`deal_joy/supabase/functions/_shared/email.ts`
- Connect 与解绑现网逻辑：`deal_joy/supabase/functions/merchant-withdrawal/index.ts`（`stripe_account_id` 清空、stale 处理；**另含**解绑申请 API）、`deal_joy/supabase/functions/merchant-brand/index.ts`（品牌）
- 管理端发信：`admin/lib/email.ts`（若审批走 Server Action 在 Next 内发信）
- 活动审计：`admin/lib/merchant-activity-*.ts`、`merchant_activity_events` 相关迁移

---

## 六、待产品后续拍板（不影响本 v1 文档结构）

- 「待结算/在途」的**精确定义**以你们财务/风控字段为准，实现清单中以第一次落地版本为准做文档脚注。
- **All** Tab 与统一 RPC 是否**一期**就合并新类型：建议研发评估工作量后二选一（见 **§5.0 / Sprint 5** 与 **§5.5** 原意）。

---

**文档结束**
