# Stripe Connect 解绑申请 v1 规格

**文档版本**: v1.0  
**创建日期**: 2026-04-08  
**受众**: 产品、研发（DealJoy 全栈：Admin Next.js、商家端 Flutter、Supabase）  
**状态**: 规格定稿，待排期实现  

---

## 变更记录

| 版本 | 日期 | 变更内容 |
| ---- | ---- | -------- |
| v1.0 | 2026-04-08 | 初版：与产品确认口径一致，附实现清单（对齐仓库现成模式） |

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

### 5.1 数据库（`deal_joy/supabase/migrations/`）

- [ ] 新建申请单表，例如 `stripe_connect_unlink_requests`（列至少包含）  
  `id`, `subject_type` (`merchant` | `brand`), `subject_id` (uuid), `merchant_id`（冗余可查询/RLS 辅助）, `requested_by_user_id`, `status`, `request_note` 或 `reason_code`, `rejected_reason` (text null), `reviewed_by_admin_id`, `reviewed_at`, `created_at`, `updated_at`，以及**幂等执行标记** `unbind_applied_at` 等（若与审批完成解耦）。
- [ ] **部分唯一约束**：`UNIQUE` 或部分索引保证 **同一 `subject` 在 `pending` 时仅一条**（Postgres 部分唯一索引或应用层+约束组合）。
- [ ] **RLS**：商家仅能 `SELECT/INSERT` 自己主体下的申请；管理员用 `is_admin()` 或现有 admin 读策略；Service Role 用于审批通过后的解绑与邮件。
- [ ] 将新邮件类型插入 **`email_type_settings` / 邮件类型枚举**（与 `20260321200000_email_system.sql` 等迁移风格一致，具体以现网最新迁移为准）。
- [ ] 可选：字段级注释、`COMMENT ON`。

### 5.2 预检与阻塞条件

- [ ] 定义**可机读**的阻塞条件列表（待结算/在途/争议/负余额 等），在**商家提交** Edge 或 **RPC** 中统一实现；不可判定的项在代码内 `TODO` + 文档备注。
- [ ] 若品牌与单店**预检数据源不同**（`merchant-withdrawal`、`merchant_earnings` 等），分支清晰。

### 5.3 Edge Functions / RPC（`deal_joy/supabase/functions/`）

- [ ] 商家：例如 `POST .../request-stripe-unlink`（或挂到 `merchant-withdrawal` 子路径），校验 JWT、主体、预检、`pending` 去重、写 `stripe_connect_unlink_requests`，触发「提交成功」邮件（`sendEmail`，新建模板）。
- [ ] 解绑执行：在 **Admin 通过** 路径中**事务或顺序**：先锁行/再 `UPDATE merchants` 或 `brands` 清 `stripe_account_id`、置 `stripe_account_status`、清可选邮箱/关联 `merchant_bank_accounts` 行（**与现网** `merchant-withdrawal` 中 stale clear、以及 **只做库** 的口径一致）；**不**在 v1 调 Stripe 删除 account。
- [ ] 与 **`merchant_brand`** 若品牌 Stripe 在独立表/字段，同步更新**同一套**解绑规则。

### 5.4 邮件模板（`deal_joy/supabase/functions/_shared/email-templates/`）

- [ ] 新建 merchant 向模板，如 `merchant/stripe-unlink-submitted.ts`、`...-approved.ts`、`...-rejected.ts`；**全英文**；`emailCode` 在 `email_logs` 中可区分（如 `M22`–`M24` 等未占用的编号，以 `email_type_settings` 实际为准）。
- [ ] 在 `sendEmail` 调用处传入 `referenceId` 为 `request_id`，便于 Email Log 检索。

### 5.5 Admin 后台（`admin/`）

- [ ] **统一审批** `admin/app/(dashboard)/approvals/page.tsx`：增加新 **Tab** 与 **抽屉** 组件（参考 `AfterSalesDrawer`、`RefundDisputeDrawer`）；`admin/components/approvals-page-client.tsx` 中 `TABS` / 计数 / `TYPE_LABELS` 扩展。
- [ ] **数据拉取**：在 `admin/app/(dashboard)/approvals/page.tsx` 的 `fetch` / Server 数据加载逻辑中增加对 `stripe_connect_unlink_requests` 的 `pending`/`history` 查询；**All Tab** 若用 `admin_pending_approvals_unified_page` RPC（`deal_joy/supabase/migrations/20260331150000_admin_pending_approvals_unified_rpc.sql` 等），需**迁移**扩展该 SQL（或 v1 先仅独立 Tab 查询、All 二期合并——实现时二选一，清单项注明）。
- [ ] **Server Actions**（`admin/app/actions/` 或 `approvals.ts`）：`approveStripeUnlink(id)` / `rejectStripeUnlink(id, reason)`：鉴权、写状态、**触发解绑**、发邮件、写 `merchant_activity_events`。
- [ ] **商家详情** `admin/app/(dashboard)/merchants/[id]/page.tsx` 侧栏**新卡片**（与现有「去审批中心」链接同风格）只读 + 链到 `?tab=stripe-unlink`（以实际 query 名为准）。

### 5.6 商家端 Flutter（`dealjoy_merchant/`）

- [ ] `dealjoy_merchant/lib/features/earnings/pages/payment_account_page.dart`：**解绑申请** 入口（按钮文案如 **Request to unlink Stripe**），表单/底部表单（原因 + 确认文案）；调用新 Edge 接口；成功 SnackBar + 依赖**刷新** `stripeAccountProvider` 与**申请状态**的 provider（若 v1 仅 `pending` 可拉一条 REST/RPC）。
- [ ] 品牌线：若品牌有独立 `dealjoy_merchant/lib/features/store/pages/brand_stripe_connect_page.dart`，同步入口或明确「仅单店/仅品牌」路由（与 3.1 一致）。

### 5.7 测试与上线

- [ ] Staging：全链路 提交 → 邮件（或关全局开关后仅日志）→ 审批通过 → DB 字段清空 → 商家端 **Refresh** 为未连接。
- [ ] 拒审理由展示与邮件**必填**校验。
- [ ] 与 **COMPLETED.md** 有冲突的目录（如 `orders` 等）不触碰；**商家端 / Admin / migrations** 按本规格新增，合并前按团队流程更新 COMPLETED 可选模块说明。

### 5.8 参考文件（不修改本清单内容时仅作开发指引）

- 统一审批：[`admin/app/(dashboard)/approvals/page.tsx`](../admin/app/(dashboard)/approvals/page.tsx)、[`approvals-page-client.tsx`](../admin/components/approvals-page-client.tsx)
- 邮件与日志：[邮件系统总览](2026-03-21-email-system.md)、`deal_joy/supabase/functions/_shared/email.ts`
- Connect 与解绑现网逻辑：`deal_joy/supabase/functions/merchant-withdrawal/index.ts`（`stripe_account_id` 清空、stale 处理）、`deal_joy/supabase/functions/merchant-brand/index.ts`（品牌）
- 管理端发信：`admin/lib/email.ts`（若审批走 Server Action 在 Next 内发信）
- 活动审计：`admin/lib/merchant-activity-*.ts`、`merchant_activity_events` 相关迁移

---

## 六、待产品后续拍板（不影响本 v1 文档结构）

- 「待结算/在途」的**精确定义**以你们财务/风控字段为准，实现清单中以第一次落地版本为准做文档脚注。
- **All** Tab 与统一 RPC 是否**一期**就合并新类型：建议研发评估工作量后二选一（见 5.5）。

---

**文档结束**
