# Post-Redemption Tipping (小费) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在团购券核销完成后，为配置了小费的 Deal 提供可选的小费收取、支付、签名留痕与三端可查能力，并与现有 Stripe、礼品（gift）、跨店核销及 `order_items` 收入模型兼容。

**Architecture:** Deal 级配置小费规则（是否启用、百分比或固定金额、三档预设 + 自选含 0）；核销仍由 `merchant-scan/redeem` 完成；小费作为**独立支付意图**在核销后发起，数据落在专用表并关联 `coupon_id` / `order_item_id`；签名以私有存储关联 `tip` 记录；Gift 场景默认由**持券核销方**（`coupons.current_holder_user_id` 对应用户）付款。**商家端 UI 与 Edge 鉴权**须与现有 `Permission` / `ROLE_PERMISSIONS`（`_shared/auth.ts`）及 `StoreInfo.hasPermission` / 底部 Tab 过滤逻辑一致，避免「无权限角色看到 Collect tip」或「有权限角色被前端误藏」。

**Tech Stack:** Supabase（PostgreSQL + RLS + Storage）、Deno Edge Functions、Stripe（PaymentIntent、Customer、已保存支付方式）、Flutter（`deal_joy` 用户端、`dealjoy_merchant` 商家端）、Admin（仓库内 `admin/` Next 订单详情；`dealjoy-cc` 为文档/工具子项目无订单 UI 代码）。

**文档版本:** v1.4  
**创建日期:** 2026-04-23  
**受众:** 产品、研发（DealJoy：Flutter 双端、Supabase Edge、可选 Admin）  
**状态:** v1 已交付 — 全链路代码已合入；税务口径仍以法务为准  
**当前阶段:** P0–P7 已完成（见 §十、§五 Sprint 标记）  

---

## 变更记录


| 版本   | 日期         | 变更内容                                                                                                                                             |
| ---- | ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| v1.0 | 2026-04-23 | 初版：产品流程、数据模型、分阶段任务、与现网代码对齐的注意点                                                                                                                   |
| v1.1 | 2026-04-23 | 对齐现网商家端 **V2.3 角色/权限**：`_shared/auth.ts`、`merchant-store` 下发、`StoreInfo` / `app_shell` Tab；明确小费能力按权限拆分；Sprint 与代码锚点增补                            |
| v1.2 | 2026-04-23 | 增加 **§十 开发进度跟踪**、§五 Sprint 状态约定；**P0 开放问题**工程默认决议写入 §3.2 / §4.2 / §九；启动 P1–P7 代码实现                                                               |
| v1.3 | 2026-04-23 | P1–P7 落地：`coupon_tips` 迁移与 RLS、Edge/Webhook、双端 Flutter、`admin` 订单小费展示、`user-order-detail`/`merchant-orders` 附加 `tip`、Deal 创建/编辑小费配置、curl 样例与测试修复 |
| v1.4 | 2026-04-27 | 新增 **§十一**：向核销方/持券人已保存卡扣款的产品与技术路径（off-session / 用户端确认 SCA / 商家端 UI 调整）；与 Gift、`payer_user_id` 口径对齐 |


---

## 一、背景与目标

### 1.1 问题

- 用户先购买券、到店核销，**核销后**才有小费场景；当前系统无小费配置与支付链路。
- 需支持商家配置、商家端向顾客展示选项与签名、支付成功后**商家端 / 用户端 / 管理端**订单信息可查证。
- 存在 **Gift**（持券人可与购买者不同）与**连续多张券核销**的体验与数据拆分问题。

### 1.2 目标（v1）

1. Deal 配置：是否收小费、类型（百分比 / 固定现金）、三档预设值、系统附加「自选」（含 0）。
2. 核销完成后（且 Deal 要求小费）：商家端可进入「收取小费」流程，展示金额选项 → 顾客确认 → **签名** → 发起支付。
3. 支付成功后持久化小费记录，并在三端订单/券详情中展示关键字段（金额、状态、时间、关联券/行项）。
4. Gift：默认由**实际付款完成小费的用户**承担（与产品约定：**持券人到店付小费**）；数据模型保留 `payer_user_id` 便于未来扩展「赠予者代付」。

### 1.3 非目标（可列 v2）

- 赠予者远程代付小费、小费预付、与团购同一 PaymentIntent 合并扣款。
- 复杂分账（平台从小费抽成）的完整税务方案 — v1 可「全额进核销门店 Connect」占位，具体比例另表。

---

## 二、范围与依赖


| 包含（v1）                    | 不包含 / 后续                   |
| ------------------------- | -------------------------- |
| Deal 级小费配置与校验             | 多币种、非 USD                  |
| 核销后独立小费 PaymentIntent     | 无卡用户除当场绑卡/钱包外的「信用赊账」       |
| 签名采集与私密存储                 | OCR / 笔迹司法鉴定级存证            |
| 单券粒度小费记录 + 可选「会话级」UI 合并   | 强制改 `merchant-scan` 原子内扣小费 |
| `stripe-webhook` 同步小费支付状态 | Stripe Terminal 专用硬件流程     |


**文案语言：** 与现网一致，**用户可见 UI / 错误提示为英文**；本计划正文中文便于评审。

**关键依赖：** 已有 `users.stripe_customer_id`、`manage-payment-methods`、`create-payment-intent` 的存卡能力；核销逻辑在 `deal_joy/supabase/functions/merchant-scan/index.ts`；礼品字段见 `20260325000001_gift_feature.sql`（`current_holder_user_id` 等）。

**商家端权限（实现小费时的主战场）：** 权限单一来源为 Edge `resolveAuth()` 返回的 `permissions` 数组（与 `deal_joy/supabase/functions/_shared/auth.ts` 中 `ROLE_PERMISSIONS` 一致），经 `merchant-store` 下发到 Flutter `StoreInfo.permissions`；UI 侧用 `StoreInfo.hasPermission(...)`（见 `dealjoy_merchant/lib/features/store/models/store_info.dart`）及 `app_shell.dart` 的 Tab `requiredPermission` 过滤。**小费相关能力须按下列矩阵做前后端一致校验**（缺省建议：「收取小费」与核销同级 → 复用 `scan`；Deal 上配置小费规则 → 复用 `deals`；订单里看小费摘要 → 与现网订单 API 一致 → 复用 `orders`）。

---

## 三、产品规格摘要

### 3.1 Deal 配置（商家端 / Admin）

- `tips_enabled`（bool）。
- `tips_mode`: `percent` | `fixed`（命名以迁移与代码为准，枚举更佳）。
- `tips_presets`: 三个数值（百分比为 0–100 的数；固定金额为货币小数），服务端校验范围与单调性（可选）。
- 产品规则：**第四项「自选」**由系统 UI 追加，不占用三档 DB 字段；自选允许 0。

### 3.2 核销后流程（商家端为主）

1. `merchant-scan/redeem` 成功返回后，若 Deal `tips_enabled`，商家端展示「Collect tip」类入口（英文文案）。
2. 打开小费页：展示三档 + Custom；展示**计算后金额**。**v1 已决议（P0）：** 百分比小费以关联 `**order_items.unit_price`**（即购买时 Deal 的券面/成交价快照）为基数；无 `order_item` 时回退为 `**deals.discount_price`**。服务端按 Deal 配置重算可收区间并校验，不信任客户端裸金额。
3. 顾客确认 → 画布签名 → 提交：创建待支付小费记录 + 上传签名 → 调 Edge 创建 Stripe PaymentIntent → 客户端确认（PaymentSheet 或已有支付组件模式）。
4. 支付成功：Webhook 更新状态；商家端关闭弹窗并提示成功。

### 3.3 多张券连续核销

- **推荐 UX**：同一顾客会话内多张券核销后，提供「合并付一笔小费」向导：总金额由用户输入或按券拆分规则分配；**落库仍建议按 `order_item_id` 拆行**（或 `tip_allocations` 子表），便于与 `order_items` 维度报表对齐。
- **备选**：每核销一张立即提示小费（实现简单，体验略碎）。

### 3.4 三端展示字段（最小集）

- 小费金额、货币、状态（`pending` / `paid` / `failed` / `canceled`）、`paid_at`、关联 `coupon_id` & `order_item_id`、Stripe `payment_intent_id`（脱敏展示）、`payer_user_id`。
- 签名：**不在用户端公开展示 URL**；商家端 / 管理端受权可见；用户端可显示「Signed at …」状态而不暴露图像（除非产品要求）。

### 3.5 商家端角色与权限（对齐现网 V2.3）

以下角色与权限表以 `deal_joy/supabase/functions/_shared/auth.ts` 中 `ROLE_PERMISSIONS` 为准（`merchant-scan` 已 `requirePermission(auth, 'scan')`；`merchant-deals` 已 `requirePermission(auth, 'deals')`；`merchant-orders` 入口已 `requirePermission(auth, 'orders')`）。


| 角色 (`UserRole`)                               | `scan` | `orders` | `orders_detail` | `deals` | 与小费 v1 的对应关系（建议）                                                                                                                                                                  |
| --------------------------------------------- | ------ | -------- | --------------- | ------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `brand_owner` / `brand_admin` / `store_owner` | ✓      | ✓        | ✓               | ✓       | 可配置 Deal 小费；可核销后收取；订单中可见摘要                                                                                                                                                        |
| `regional_manager` / `manager`                | ✓      | ✓        | ✓               | ✓       | 同上                                                                                                                                                                                |
| `finance`                                     | ✗      | ✓        | ✓               | ✗       | **无扫码 Tab/无 `scan`**：不宜承担「柜台向顾客收小费」流程；可在订单/报表中看小费数据（与订单权限一致即可）                                                                                                                    |
| `service`                                     | ✓      | ✓        | ✓               | ✗       | **可核销与收小费**；**不可**在商家端编辑 Deal 小费配置（无 `deals`）— 配置由店长/老板完成                                                                                                                         |
| `cashier`                                     | ✓      | ✓        | ✗               | ✗       | 同上：可收小费，不可改 Deal 小费字段                                                                                                                                                             |
| `trainee`                                     | ✓      | ✗        | ✗               | ✗       | **与产品确认**：`auth` 注释为「只读扫码、不能核销」，但当前 `CouponVerifyPage` 未按角色隐藏「Confirm Redemption」；小费 v1 应 **要么** 在后端拒绝 `trainee` 的 `redeem`/收小费，**要么** 在前端与核销策略一致后，再决定 `trainee` 是否出现 Collect tip |


**Flutter 侧注意：**

- `dealjoy_merchant/lib/app_shell.dart`：底部 Tab 用权限字符串过滤（`scan` / `orders` / `analytics` 等与 Edge 对齐）；小费入口若挂在核销成功页或 Scan 子路由，应用 `storeProvider` → `hasPermission('scan')`（或与产品商定的新权限）包裹。
- `StoreInfo` 已有 `canScan`、`canManageDeals`、`canViewOrders`；若增加 `canCollectTips`，建议 **语义上等于 `canScan`**（除非产品单开 `tips` 权限，则须同步改 `_shared/auth.ts` 的 `Permission` 联合类型、`ROLE_PERMISSIONS`、`merchant-store` 文档说明）。
- `dealjoy_merchant/lib/features/deals/pages/deal_detail_page.dart` 等已有按权限隐藏区块的模式（如 `_hasPermission`），Deal 小费配置表单应复用同一模式，**仅 `deals` 为 true 时**展示可编辑小费字段。

---

## 四、技术设计

### 4.1 数据模型（建议）

**表 `deals` 扩展**（迁移，勿手改 `schema.sql` 主文件习惯与项目一致）：

- `tips_enabled`, `tips_mode`, `tips_preset_1`, `tips_preset_2`, `tips_preset_3`（或 `jsonb tips_presets` + 校验约束）。

**新表 `coupon_tips`（名称可调整）**：

- `id`, `coupon_id` FK, `order_item_id` FK（可空但建议尽量有）, `deal_id`, `merchant_id`（核销门店）, `payer_user_id`, `amount_cents`（或 `numeric`）, `currency`, `mode_snapshot`, `preset_label` / `custom`, `status`, `stripe_payment_intent_id`, `signature_storage_path`, `created_at`, `updated_at`, `paid_at`。
- 唯一约束：可考虑「每张券仅一笔成功小费」`UNIQUE (coupon_id) WHERE status = 'paid'`（PostgreSQL 部分唯一索引）— 与产品确认是否允许补付第二笔。

**Storage**：私有 bucket，路径如 `tips/{tip_id}/signature.png`；仅 service_role 或 signed URL 短时下发。

**RLS**：付款人可读自己的 tip；商家按 `merchant_id` 与现有 `resolveAuth` 模式可读；管理端 service role 或专用 policy。

**Edge 小费 API 鉴权（建议）：** 与 `merchant-scan` 一致，调用 `resolveAuth` + `requirePermission(auth, 'scan')` 用于「创建待支付小费 / 创建 PaymentIntent / 上传签名元数据」等**柜台动作**；若后续存在「仅财务下载小费报表」的只读 API，可单独 `requirePermission(auth, 'finance')` 或 `orders`。避免未持有 `scan` 的角色通过 REST 绕过 App 直接创建小费会话。

### 4.2 Stripe

- 新建 Edge Function（示例名）`create-tip-payment-intent`：入参 `tip_id` 或 `coupon_id` + 金额 + 鉴权用户；校验 Deal 配置、券已 `used`、金额在允许范围；创建 **独立** `PaymentIntent`，`metadata` 含 `coupon_id`, `order_item_id`, `tip_id`, `merchant_id`。
- 使用已有 Stripe Customer；优先默认 PaymentMethod；必要时客户端确认（SCA）。
- **Connect**：明确小费 `transfer_data[destination]` 为**核销门店** `merchants.stripe_account_id`（与现网跨店逻辑区分：小费不走路径错误的 `reverse_transfer` 团购逻辑）。**v1 已决议（P0）：** 平台**不**从小费抽成（`application_fee_amount = 0`）；后续若抽成再改 Edge 与报表。
- `stripe-webhook`：处理 `payment_intent.succeeded` / `failed`，更新 `coupon_tips.status`（幂等：`tip_id` 或 `pi.id`）。

### 4.3 与核销解耦

- **禁止**在 `handleRedeem` 内同步等待小费支付（避免阻塞、避免部分失败难补偿）。
- 核销成功后仅返回「该 Deal 是否需小费」标志（可选：在 `redeem` 响应中 `deal.tips_enabled`），由客户端决定是否跳转小费流。

### 4.4 Gift

- 登录用户必须等于 `coupons.current_holder_user_id`（或你们定义的「可核销身份」）才可发起该券的小费支付（服务端强校验）。
- `payer_user_id` 记录实际扣款用户；`orders.user_id` 仅作「原购买者」报表字段保留。

---

## 五、实现任务（分 Sprint）

**Sprint 状态约定：** 每个 Sprint 标题行后缀 `【状态：未开始 | 进行中 | 已完成】`；完成后补 **完成日期** 与 **PR/commit**（可选）。子任务可用 `- [x]` 勾选。

### Sprint 0：口径冻结（0.5–1 天）【状态：已完成】2026-04-23

**Files:** 无代码 — 更新本计划或 PRD 附件。

- 确认百分比基数、是否允许每券多笔、平台是否从小费抽成、失败重试策略。
- 法务 / 税务一句话备案（北美小费常见为单独交易）。

**验收:** 书面结论写入「§3.2 计算基准」与「§4.2 Connect 分账」小节。

---

### Sprint 1：数据库与 RLS【状态：已完成】2026-04-23

**Files:**

- Create: `deal_joy/supabase/migrations/YYYYMMDDHHMMSS_tipping_schema.sql`
- Modify: `deal_joy/supabase/functions/_shared/...`（如有共享类型）

**Step 1:** 为 `deals` 增加小费字段 + 默认值（`tips_enabled = false`）。

**Step 2:** 创建 `coupon_tips`（及可选 `tip_redemption_sessions` 若做合并会话）。

**Step 3:** 索引：`(coupon_id)`, `(order_item_id)`, `(merchant_id, created_at)`, `(stripe_payment_intent_id)`。

**Step 4:** RLS policy + Storage bucket 策略草稿。

**Step 5:** 本地 `supabase db reset` 或 CI 迁移校验（以团队流程为准）。

**验收:** 迁移可应用；RLS 下买家/商家/他方不可越权读小费与签名。

---

### Sprint 2：Edge Functions【状态：已完成】2026-04-23

**Files:**

- Create: `deal_joy/supabase/functions/create-tip-payment-intent/index.ts`
- Create: `deal_joy/supabase/functions/submit-tip-signature/index.ts`（或与 create 合并，视 payload 大小）
- Modify: `deal_joy/supabase/functions/stripe-webhook/index.ts`
- Modify（可选，若产品单开 `tips` 权限）: `deal_joy/supabase/functions/_shared/auth.ts` — 新增 `Permission` 枚举值并写入需收小费的角色集合
- Reference: `deal_joy/supabase/functions/manage-payment-methods/index.ts`, `deal_joy/supabase/functions/merchant-scan/index.ts`（只读对齐校验逻辑）

**Step 0（权限）：** 与产品确认 v1 是否**复用 `scan`** 作为收小费权限；确认 `trainee` 是否允许收小费/核销。若不允许多 `redeem`，则在 `merchant-scan` 的 `redeem` 分支增加 `role === 'trainee'` 拒绝，或在 Flutter 侧禁用按钮与之一致。

**Step 1:** `create-tip-payment-intent`：鉴权 → 读 coupon + deal → 校验 `used`、金额 → 写 `coupon_tips` `pending` → 创建 PI。

**Step 2:** Webhook 更新 `paid` / `failed`，日志与幂等。

**Step 3:** 签名：先上传拿 `path` 再关联 `coupon_tips`（或 base64 仅内网 — 不推荐大 body）。

**验收:** Postman/curl 可走通 pending → succeeded；重复 webhook 不双计。

---

### Sprint 3：商家端 Flutter（`dealjoy_merchant`）— **权限与扫码模块为主**【状态：已完成】2026-04-23

**Files:**

- Modify: `dealjoy_merchant/lib/features/scan/...`（核销成功后续流程、**权限门控**）
- Modify: `dealjoy_merchant/lib/features/scan/pages/redemption_success_page.dart`（Collect tip 入口、`StoreInfo` / `ref.watch(storeProvider)`）
- Modify: `dealjoy_merchant/lib/features/scan/pages/coupon_verify_page.dart`（若 Sprint 2 对 `trainee` 禁核销，需与此处按钮状态一致）
- Modify: `dealjoy_merchant/lib/features/store/models/store_info.dart`（可选：`canCollectTips` 或文档化复用 `canScan`）
- Modify: `dealjoy_merchant/lib/app_shell.dart`（仅当 Tab/路由与小费相关时需评估；一般小费挂在 Scan 子路由则依赖 `scan` Tab 已可见）
- Create: `dealjoy_merchant/lib/features/tips/...`（screen、widgets、repository）
- Reference: `dealjoy_merchant/lib/features/scan/services/scan_service.dart`、`dealjoy_merchant/lib/features/dashboard/widgets/shortcut_grid.dart`（若 Dashboard 增加快捷入口则需 `permissions` 参数）

**Step 1:** 核销响应解析 `tips_enabled`（若后端 Sprint 2 增加字段）。

**Step 2:** 小费选项 UI + 自定义金额 + 签名板（可选用成熟 package）；**所有「向顾客展示并确认」的页面**用 `hasPermission('scan')`（或 `tips`）包裹，避免 finance-only 账号通过深链打开。

**Step 3:** 调 Edge 完成 PI + Stripe 确认（与现有 Stripe 初始化方式一致）。

**Step 4:** 订单详情 / 核销历史处展示小费摘要（读 DB 或新 API）；展示条件与 `canViewOrders`（及产品设计是否要求 `orders_detail`）一致 — 现网 `merchant-orders` 仅校验 `orders`，cashier 可看详情接口，与之一致即可。

**Step 5（回归）：** 用 **cashier / service / manager / finance / trainee** 各至少一账号冒烟：可见 Tab、Collect tip 入口、Deal 编辑页小费字段是否符合 §3.5。

**验收:** 真机或 staging 完整走通一单；Gift 场景用两账号测持券人支付；**无权限角色看不到收小费入口且接口 403**。

---

### Sprint 4：用户端 Flutter（`deal_joy`）【状态：已完成】2026-04-23

**Files:**

- Modify: `deal_joy/lib/features/orders/...` 或订单详情相关 `presentation/screens`
- Create: `deal_joy/lib/features/tips/...`（若顾客也可在自己 App 内查看/补付 — 以产品为准）

**Step 1:** 订单/券详情展示小费块（英文）。

**Step 2:** 若产品要求用户端也可发起小费，复用与商家端同一套 API（注意鉴权差异：用户 JWT vs 商家 `resolveAuth`）。

**验收:** 登录用户可见本人已付小费记录；不可见他人签名图像（除非产品另有规定）。

---

### Sprint 5：管理端（`admin/`）【状态：已完成】2026-04-23

**Files:** `admin/app/(dashboard)/orders/[id]/page.tsx`（`order_items` + `coupon` 展示处；`coupon_tips` 经 service role 查询）。

**Step 1:** 管理订单详情增加小费行：金额、状态、PI id、 payer、核销门店。

**Step 2:** 受控展示签名（内网管理员）。

**验收:** 角色权限正确；无签名 URL 泄漏到浏览器控制台以外渠道。

---

### Sprint 6：Deal 配置编辑【状态：已完成】2026-04-23

**Files:**

- `dealjoy_merchant` Deal 创建/编辑表单（**仅 `canManageDeals` / `deals` 权限**展示与提交小费配置；`service`/`cashier` 进入 Deal 页须不可改小费字段）
- `dealjoy_merchant/lib/features/deals/pages/deal_detail_page.dart`（及关联 editor，与现有 `_hasPermission` 模式对齐）
- `deal_joy/supabase/functions/merchant-deals/index.ts`（PATCH/POST body 扩展 + 小费字段**数值/枚举服务端校验**；现网入口已统一 `requirePermission(auth, "deals")`，`cashier`/`service` 等**无法调用**该 Edge — Flutter 隐藏表单仅为 UX，不能替代鉴权）
- 若有 Admin 维护 deals：以仓库内 `admin/` 对应表单为准（`dealjoy-cc` 无 Deal 维护 UI）

**Step 1:** 表单字段 + 校验 + API payload。

**Step 2:** 老 Deal 默认 `tips_enabled=false` 回归测。

**验收:** 配置可保存、可回显；非法预设被服务端拒绝；**无 `deals` 权限账号**请求更新小费字段时 **HTTP 403**。

---

### Sprint 7：测试、观测与文档【状态：已完成】2026-04-23

**Files:**

- 集成测试或最小 e2e 脚本（按仓库惯例）
- `docs/curl/...` 可选：小费相关 curl 样例

**Step 1:** 单元/集成：金额校验、RLS、Webhook 幂等。

**Step 2:** 日志字段 `tip_id` 贯穿 Edge 与 webhook。

**Step 3:** 更新内部 README 或 API 列表（若项目有）。

**验收:** 测试清单全绿；staging 支付报表人工抽查一笔。

---

## 六、风险与缓解


| 风险                                          | 缓解                                                                                                                                 |
| ------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| Store Credit 用户无保存卡                         | 小费流引导当场绑卡 / Apple Pay；无法支付则允许跳过并记 `skipped`（若产品允许）                                                                                 |
| SCA 导致 off_session 失败                       | 当面 PaymentSheet 确认                                                                                                                 |
| 跨店团购资金逻辑与小费混淆                               | 小费 PI 单独 metadata + 独立 transfer 目标账户                                                                                               |
| 签名 GDPR / 存储成本                              | 保留期政策 + 压缩图像 + 仅关联 tip 行                                                                                                           |
| 角色权限漂移（Flutter Tab 与 Edge `Permission` 不一致） | 以 `_shared/auth.ts` 为唯一真相；`StoreInfo` 便捷 getter 与 `requirePermission` 使用同一字符串；新增权限时同步 `merchant-brand` / `merchant-store` 若存在硬编码列表 |
| `trainee` 能否核销/收小费与注释不一致                    | Sprint 2 Step 0 产品裁定 + 前后端统一拦截                                                                                                     |


---

## 七、验收标准（总）

1. Deal 可配置小费；未启用时全链路无回归。
2. 核销成功后可完成小费支付；Stripe 与 DB 状态一致。
3. 每张券（或拆分行）可在三端订单信息中查到小费关键字段。
4. Gift：持券人可付；购买者不可误扣（除非未来单独功能）。
5. Webhook 与重复投递安全；无未授权读签名。
6. **商家端权限：** `cashier`/`service` 可收小费但不可编辑 Deal 小费配置；`finance` 不可依赖 Scan 收小费；无 `deals` 不可改小费字段；无 `scan`（或未来 `tips`）不可调小费 Edge API。

---

## 八、主要代码锚点（便于跳转）


| 区域                    | 路径                                                                                                 |
| --------------------- | -------------------------------------------------------------------------------------------------- |
| 核销                    | `deal_joy/supabase/functions/merchant-scan/index.ts`（`handleRedeem`）                               |
| 下单支付                  | `deal_joy/supabase/functions/create-payment-intent/index.ts`                                       |
| 卡管理                   | `deal_joy/supabase/functions/manage-payment-methods/index.ts`                                      |
| Webhook               | `deal_joy/supabase/functions/stripe-webhook/index.ts`                                              |
| 商家扫码服务                | `dealjoy_merchant/lib/features/scan/services/scan_service.dart`                                    |
| 商家权限模型                | `deal_joy/supabase/functions/_shared/auth.ts`（`ROLE_PERMISSIONS` / `requirePermission`）            |
| 门店上下文与 permissions 下发 | `deal_joy/supabase/functions/merchant-store/index.ts`                                              |
| Flutter 权限便捷方法 / Tab  | `dealjoy_merchant/lib/features/store/models/store_info.dart`、`dealjoy_merchant/lib/app_shell.dart` |
| Deal 页权限隐藏示例          | `dealjoy_merchant/lib/features/deals/pages/deal_detail_page.dart`                                  |
| 核销成功页                 | `dealjoy_merchant/lib/features/scan/pages/redemption_success_page.dart`                            |
| 礼品迁移                  | `deal_joy/supabase/migrations/20260325000001_gift_feature.sql`                                     |
| 项目规范                  | `.claude/skills/dealjoy-context/SKILL.md`                                                          |


---

## 九、开放问题（实现前建议关闭）

1. ~~百分比小费的计算基数~~ **已决议（P0）：** 见 §3.2 — `order_items.unit_price` 优先，否则 `deals.discount_price`。
2. ~~同一券是否允许多笔失败重试~~ **已决议（P0）：** 允许同一券多条 `coupon_tips` 为 `pending`/`failed`，**仅允许一条 `paid`**（部分唯一索引 `UNIQUE (coupon_id) WHERE status = 'paid'`）；失败后可再发起直至成功一笔。
3. ~~平台是否从小费抽取费用~~ **已决议（P0）：** v1 不抽成；见 §4.2。
4. ~~合并小费会话~~ **已决议（P0）：** v1 **不做**合并会话 UI，仅 **per-coupon**；后续可加 `tip_redemption_sessions`。
5. ~~`trainee` 核销/收小费~~ **已决议（P0）：** **不允许**核销与收小费；`merchant-scan/redeem`（及 verify 如需）拒绝 `trainee`；`CouponVerifyPage` 隐藏确认核销；小费 Edge 拒绝 `trainee`。

---

## 十、开发进度跟踪


| 阶段  | 说明                                  | 状态  | 完成日期       | PR / 备注                                                                    |
| --- | ----------------------------------- | --- | ---------- | -------------------------------------------------------------------------- |
| P0  | Sprint 0 口径冻结                       | 已完成 | 2026-04-23 | 见 §九 已决议                                                                   |
| P1  | Sprint 1 DB / RLS / Storage         | 已完成 | 2026-04-23 | 迁移 `20260423120000_post_redemption_tipping.sql`                            |
| P2  | Sprint 2 Edge + Webhook + redeem 扩展 | 已完成 | 2026-04-23 | `create-tip-payment-intent`、`merchant-scan`、`stripe-webhook`               |
| P3  | Sprint 3 商家端 Flutter                | 已完成 | 2026-04-23 | `dealjoy_merchant` tips + scan + `merchant-orders` 行级 `tip`                |
| P4  | Sprint 4 用户端 Flutter                | 已完成 | 2026-04-23 | `user-order-detail` + `deal_joy` 订单详情英文展示                                  |
| P5  | Sprint 5 管理端                        | 已完成 | 2026-04-23 | `admin/app/(dashboard)/orders/[id]/page.tsx`（service role 读 `coupon_tips`） |
| P6  | Sprint 6 Deal 配置                    | 已完成 | 2026-04-23 | `merchant-deals` + Deal 创建/编辑表单                                            |
| P7  | Sprint 7 测试与收尾                      | 已完成 | 2026-04-23 | Scan 相关单测、`docs/curl/tipping/`                                             |


*每完成一个阶段：更新本表「状态/完成日期」、递增文档版本、在「变更记录」追加一行。*

---

## 十一、v2 方向：向核销方 / 持券人「已保存支付方式」扣款（产品与实现要点）

> **产品目标：** 商家端仅选金额 + 采集签名；**实际扣款用户 = 实际持券到店并被服务的一方**（与购买人可不同，如 Gift）。**不向**商家平板上重新输卡作为唯一路径。

### 11.1 谁该被扣款（数据规则）

| 场景 | 小费付款人（`payer_user_id` / Stripe Customer 来源） |
| ---- | -------------------------------------------------- |
| 普通购券自用后核销 | `coupons.user_id`（持券人 = 购买人） |
| 赠券后由受赠人核销 | 新券行的 `coupons.user_id` 已为受赠人；若有并行字段则用 **`COALESCE(coupons.current_holder_user_id, coupons.user_id)`** 与 Gift / in-app 赠送口径对齐 |

**Edge 侧必须在发起扣款前解析并写入 `coupon_tips.payer_user_id`**（勿沿用「谁在商家 App 点按钮」）。

### 11.2 前置条件（不满足则降级）

1. **`users.stripe_customer_id`** 已存在（下单绑卡流程已有，见迁移 `20260321000002_stripe_customer_id.sql`）。
2. Stripe Customer 上存在 **可调度的支付方式**：常用做法是 **`invoice_settings.default_payment_method`**（用户端「默认卡」已与 `manage-payment-methods` 对齐）。
3. **合规 / 协议：** 用户是否在下单或账户条款中同意「到店核销后可按商户提示金额扣小费」类授权 — **须产品/法务裁定**；Stripe **MIT / off_session** 规则与此相关。

### 11.3 推荐技术路径（择一或组合）

**路径 A — 服务端 Off-session 扣款（首选尝试）**

1. `create-tip-payment-intent`（或拆分为 `charge-tip-off-session`）用 **service role**：
   - 解析 `payer_user_id`；
   - 读 `users.stripe_customer_id`，拉取默认 `payment_method`；
   - `paymentIntents.create({ customer, payment_method, off_session: true, confirm: true, transfer_data: … })`（Connect 与现 PI 一致）。
2. 若返回 **`authentication_required`** / `card_declined` 等：
   - **降级路径 B** 或标记 `coupon_tips.status = requires_action`，勿静默失败。

**路径 B — 用户端（deal_joy）确认（应对 SCA）**

1. 商家端提交金额 + 签名后，后端创建 **`pending` PI**（或 PaymentIntent `requires_confirmation`），并向 **`payer_user_id`** 发 **推送 / 短信链接 / App 内 Deep link**。
2. 用户打开 **deal_joy**，用 **同一 Stripe Customer** 走 **`presentPaymentSheet`** 或 **authenticatePaymentIntent** 完成 3DS。
3. Webhook 照旧把 `coupon_tips` 置 `paid`。

**路径 C — 混合**

- 先试路径 A；失败自动切换路径 B（商家 UI 展示「已向顾客手机发送确认」）。

### 11.4 商家端（dealjoy_merchant）改动摘要

- **移除**「在本机 PaymentSheet 上让顾客输入卡号」作为主路径（当前 `collect_tip_page.dart`）。
- 改为：**提交金额 + 签名** → 调用新/改版 Edge → 展示状态：**Processing / Sent to customer / Paid / Failed**。
- 权限与路由不变（仍为商户发起）。

### 11.5 用户端（deal_joy）改动摘要（若走路径 B/C）

- 新增「待确认小费」入口：Deep link + **Stripe confirm**（或 PaymentSheet with `client_secret`）。
- **可选**：列表展示「某门店向你收取 $x 小费」待确认项。

### 11.6 风险（计划文档 §六已部分提及）

| 风险 | 说明 |
| ---- | ---- |
| **SCA** | 欧盟卡 / 部分美国卡 off-session 常失败，路径 B 几乎是标配兜底 |
| **无默认卡** | 须明确产品：**禁止扣款**并提示顾客在用户端绑卡，或临时允许路径「当面 PaymentSheet」作为后备 |
| **Gift 误绑购买者** | 必须用 §11.1 解析 payer，严禁用工单的 `orders.user_id` 代替持券人 |

---

*本计划由研发根据当前仓库结构整理；税务等仍以法务最终结论为准。*