# Post-Redemption Tipping (小费) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在团购券核销完成后，为配置了小费的 Deal 提供可选的小费收取、支付、签名留痕与三端可查能力，并与现有 Stripe、礼品（gift）、跨店核销及 `order_items` 收入模型兼容。

**Architecture:** Deal 级配置小费规则（是否启用、百分比或固定金额、三档预设 + 自选含 0）；核销仍由 `merchant-scan/redeem` 完成；小费作为**独立支付意图**在核销后发起，数据落在专用表并关联 `coupon_id` / `order_item_id`；签名以私有存储关联 `tip` 记录；Gift 场景默认由**持券核销方**（`coupons.current_holder_user_id` 对应用户）付款。

**Tech Stack:** Supabase（PostgreSQL + RLS + Storage）、Deno Edge Functions、Stripe（PaymentIntent、Customer、已保存支付方式）、Flutter（`deal_joy` 用户端、`dealjoy_merchant` 商家端）、Admin（`dealjoy-cc` 若订单展示在此）。

**文档版本:** v1.0  
**创建日期:** 2026-04-23  
**受众:** 产品、研发（DealJoy：Flutter 双端、Supabase Edge、可选 Admin）  
**状态:** 规划稿 — 实现前需与产品/法务确认税务与小费分账口径  

---

## 变更记录

| 版本 | 日期 | 变更内容 |
| ---- | ---- | -------- |
| v1.0 | 2026-04-23 | 初版：产品流程、数据模型、分阶段任务、与现网代码对齐的注意点 |

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

| 包含（v1） | 不包含 / 后续 |
| ---------- | ------------- |
| Deal 级小费配置与校验 | 多币种、非 USD |
| 核销后独立小费 PaymentIntent | 无卡用户除当场绑卡/钱包外的「信用赊账」 |
| 签名采集与私密存储 | OCR / 笔迹司法鉴定级存证 |
| 单券粒度小费记录 + 可选「会话级」UI 合并 | 强制改 `merchant-scan` 原子内扣小费 |
| `stripe-webhook` 同步小费支付状态 | Stripe Terminal 专用硬件流程 |

**文案语言：** 与现网一致，**用户可见 UI / 错误提示为英文**；本计划正文中文便于评审。

**关键依赖：** 已有 `users.stripe_customer_id`、`manage-payment-methods`、`create-payment-intent` 的存卡能力；核销逻辑在 `deal_joy/supabase/functions/merchant-scan/index.ts`；礼品字段见 `20260325000001_gift_feature.sql`（`current_holder_user_id` 等）。

---

## 三、产品规格摘要

### 3.1 Deal 配置（商家端 / Admin）

- `tips_enabled`（bool）。
- `tips_mode`: `percent` | `fixed`（命名以迁移与代码为准，枚举更佳）。
- `tips_presets`: 三个数值（百分比为 0–100 的数；固定金额为货币小数），服务端校验范围与单调性（可选）。
- 产品规则：**第四项「自选」**由系统 UI 追加，不占用三档 DB 字段；自选允许 0。

### 3.2 核销后流程（商家端为主）

1. `merchant-scan/redeem` 成功返回后，若 Deal `tips_enabled`，商家端展示「Collect tip」类入口（英文文案）。
2. 打开小费页：展示三档 + Custom；展示**计算后金额**（百分比基于何种基准 — **需产品拍板**：常见为「券面值 / 实付 / 固定档位」；v1 建议在规格中锁定一种并在服务端统一计算，防篡改）。
3. 顾客确认 → 画布签名 → 提交：创建待支付小费记录 + 上传签名 → 调 Edge 创建 Stripe PaymentIntent → 客户端确认（PaymentSheet 或已有支付组件模式）。
4. 支付成功：Webhook 更新状态；商家端关闭弹窗并提示成功。

### 3.3 多张券连续核销

- **推荐 UX**：同一顾客会话内多张券核销后，提供「合并付一笔小费」向导：总金额由用户输入或按券拆分规则分配；**落库仍建议按 `order_item_id` 拆行**（或 `tip_allocations` 子表），便于与 `order_items` 维度报表对齐。
- **备选**：每核销一张立即提示小费（实现简单，体验略碎）。

### 3.4 三端展示字段（最小集）

- 小费金额、货币、状态（`pending` / `paid` / `failed` / `canceled`）、`paid_at`、关联 `coupon_id` & `order_item_id`、Stripe `payment_intent_id`（脱敏展示）、`payer_user_id`。
- 签名：**不在用户端公开展示 URL**；商家端 / 管理端受权可见；用户端可显示「Signed at …」状态而不暴露图像（除非产品要求）。

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

### 4.2 Stripe

- 新建 Edge Function（示例名）`create-tip-payment-intent`：入参 `tip_id` 或 `coupon_id` + 金额 + 鉴权用户；校验 Deal 配置、券已 `used`、金额在允许范围；创建 **独立** `PaymentIntent`，`metadata` 含 `coupon_id`, `order_item_id`, `tip_id`, `merchant_id`。
- 使用已有 Stripe Customer；优先默认 PaymentMethod；必要时客户端确认（SCA）。
- **Connect**：明确小费 `transfer_data[destination]` 为**核销门店** `merchants.stripe_account_id`（与现网跨店逻辑区分：小费不走路径错误的 `reverse_transfer` 团购逻辑）。
- `stripe-webhook`：处理 `payment_intent.succeeded` / `failed`，更新 `coupon_tips.status`（幂等：`tip_id` 或 `pi.id`）。

### 4.3 与核销解耦

- **禁止**在 `handleRedeem` 内同步等待小费支付（避免阻塞、避免部分失败难补偿）。
- 核销成功后仅返回「该 Deal 是否需小费」标志（可选：在 `redeem` 响应中 `deal.tips_enabled`），由客户端决定是否跳转小费流。

### 4.4 Gift

- 登录用户必须等于 `coupons.current_holder_user_id`（或你们定义的「可核销身份」）才可发起该券的小费支付（服务端强校验）。
- `payer_user_id` 记录实际扣款用户；`orders.user_id` 仅作「原购买者」报表字段保留。

---

## 五、实现任务（分 Sprint）

### Sprint 0：口径冻结（0.5–1 天）

**Files:** 无代码 — 更新本计划或 PRD 附件。

- 确认百分比基数、是否允许每券多笔、平台是否从小费抽成、失败重试策略。
- 法务 / 税务一句话备案（北美小费常见为单独交易）。

**验收:** 书面结论写入「§3.2 计算基准」与「§4.2 Connect 分账」小节。

---

### Sprint 1：数据库与 RLS

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

### Sprint 2：Edge Functions

**Files:**

- Create: `deal_joy/supabase/functions/create-tip-payment-intent/index.ts`
- Create: `deal_joy/supabase/functions/submit-tip-signature/index.ts`（或与 create 合并，视 payload 大小）
- Modify: `deal_joy/supabase/functions/stripe-webhook/index.ts`
- Reference: `deal_joy/supabase/functions/manage-payment-methods/index.ts`, `deal_joy/supabase/functions/merchant-scan/index.ts`（只读对齐校验逻辑）

**Step 1:** `create-tip-payment-intent`：鉴权 → 读 coupon + deal → 校验 `used`、金额 → 写 `coupon_tips` `pending` → 创建 PI。

**Step 2:** Webhook 更新 `paid` / `failed`，日志与幂等。

**Step 3:** 签名：先上传拿 `path` 再关联 `coupon_tips`（或 base64 仅内网 — 不推荐大 body）。

**验收:** Postman/curl 可走通 pending → succeeded；重复 webhook 不双计。

---

### Sprint 3：商家端 Flutter（`dealjoy_merchant`）

**Files:**

- Modify: `dealjoy_merchant/lib/features/scan/...`（核销成功后续流程）
- Create: `dealjoy_merchant/lib/features/tips/...`（screen、widgets、repository）
- Reference: `dealjoy_merchant/lib/features/scan/services/scan_service.dart`

**Step 1:** 核销响应解析 `tips_enabled`（若后端 Sprint 2 增加字段）。

**Step 2:** 小费选项 UI + 自定义金额 + 签名板（可选用成熟 package）。

**Step 3:** 调 Edge 完成 PI + Stripe 确认（与现有 Stripe 初始化方式一致）。

**Step 4:** 订单详情 / 核销历史处展示小费摘要（读 DB 或新 API）。

**验收:** 真机或 staging 完整走通一单；Gift 场景用两账号测持券人支付。

---

### Sprint 4：用户端 Flutter（`deal_joy`）

**Files:**

- Modify: `deal_joy/lib/features/orders/...` 或订单详情相关 `presentation/screens`
- Create: `deal_joy/lib/features/tips/...`（若顾客也可在自己 App 内查看/补付 — 以产品为准）

**Step 1:** 订单/券详情展示小费块（英文）。

**Step 2:** 若产品要求用户端也可发起小费，复用与商家端同一套 API（注意鉴权差异：用户 JWT vs 商家 `resolveAuth`）。

**验收:** 登录用户可见本人已付小费记录；不可见他人签名图像（除非产品另有规定）。

---

### Sprint 5：管理端（`dealjoy-cc`）

**Files:** 订单详情相关页面（搜索 `order_items`、`coupon` 展示处）。

**Step 1:** 管理订单详情增加小费行：金额、状态、PI id、 payer、核销门店。

**Step 2:** 受控展示签名（内网管理员）。

**验收:** 角色权限正确；无签名 URL 泄漏到浏览器控制台以外渠道。

---

### Sprint 6：Deal 配置编辑

**Files:**

- `dealjoy_merchant` Deal 创建/编辑表单
- `deal_joy/supabase/functions/merchant-deals/index.ts`（或实际维护 deals 的 Edge 路由）
- 若有 Admin 维护 deals：`dealjoy-cc` 对应表单

**Step 1:** 表单字段 + 校验 + API payload。

**Step 2:** 老 Deal 默认 `tips_enabled=false` 回归测。

**验收:** 配置可保存、可回显；非法预设被服务端拒绝。

---

### Sprint 7：测试、观测与文档

**Files:**

- 集成测试或最小 e2e 脚本（按仓库惯例）
- `docs/curl/...` 可选：小费相关 curl 样例

**Step 1:** 单元/集成：金额校验、RLS、Webhook 幂等。

**Step 2:** 日志字段 `tip_id` 贯穿 Edge 与 webhook。

**Step 3:** 更新内部 README 或 API 列表（若项目有）。

**验收:** 测试清单全绿；staging 支付报表人工抽查一笔。

---

## 六、风险与缓解

| 风险 | 缓解 |
| ---- | ---- |
| Store Credit 用户无保存卡 | 小费流引导当场绑卡 / Apple Pay；无法支付则允许跳过并记 `skipped`（若产品允许） |
| SCA 导致 off_session 失败 | 当面 PaymentSheet 确认 |
| 跨店团购资金逻辑与小费混淆 | 小费 PI 单独 metadata + 独立 transfer 目标账户 |
| 签名 GDPR / 存储成本 | 保留期政策 + 压缩图像 + 仅关联 tip 行 |

---

## 七、验收标准（总）

1. Deal 可配置小费；未启用时全链路无回归。
2. 核销成功后可完成小费支付；Stripe 与 DB 状态一致。
3. 每张券（或拆分行）可在三端订单信息中查到小费关键字段。
4. Gift：持券人可付；购买者不可误扣（除非未来单独功能）。
5. Webhook 与重复投递安全；无未授权读签名。

---

## 八、主要代码锚点（便于跳转）

| 区域 | 路径 |
| ---- | ---- |
| 核销 | `deal_joy/supabase/functions/merchant-scan/index.ts`（`handleRedeem`） |
| 下单支付 | `deal_joy/supabase/functions/create-payment-intent/index.ts` |
| 卡管理 | `deal_joy/supabase/functions/manage-payment-methods/index.ts` |
| Webhook | `deal_joy/supabase/functions/stripe-webhook/index.ts` |
| 商家扫码服务 | `dealjoy_merchant/lib/features/scan/services/scan_service.dart` |
| 礼品迁移 | `deal_joy/supabase/migrations/20260325000001_gift_feature.sql` |
| 项目规范 | `.claude/skills/dealjoy-context/SKILL.md` |

---

## 九、开放问题（实现前建议关闭）

1. 百分比小费的计算基数（券原价 / 实付 / 固定表外字段）。
2. 同一券是否允许「小费失败」后无限重试直至一笔 `paid`。
3. 平台是否从小费抽取费用；若抽，Stripe 字段如何表达。
4. 合并小费会话是否 v1 必做，或 v1 仅 per-coupon。

---

*本计划由研发根据当前仓库结构整理；开放问题以产品/法务最终结论为准。*
