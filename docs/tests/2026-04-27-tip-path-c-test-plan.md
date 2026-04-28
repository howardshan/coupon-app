# 路径 C 小费扣款 — 功能测试计划

> **范围：** `create-tip-payment-intent` 多分支 `flow`、持券人 `payer_user_id`、`confirm-tip-payment-session`、推送 `tip_confirm`、`deal_joy` 确认页、`dealjoy_merchant` Collect Tip 按 `flow` 分支、Webhook `paid` 一致性。  
> **关联文档：** [../plans/2026-04-23-post-redemption-tipping.md](../plans/2026-04-23-post-redemption-tipping.md) §十一；总清单可配合 [post-redemption-tipping-qa-checklist.md](./post-redemption-tipping-qa-checklist.md)。

**文档版本：** v1.1  
**编写日期：** 2026-04-27  
**建议环境：** Stripe **Test mode**、Supabase **Staging / 测试项目**、两台实体设备或「商户平板模拟器 + 用户手机」各一。

---

## 一、测试目标

1. 验证 **付款人 = 持券核销方**（`COALESCE(current_holder_user_id, user_id)`）写入 `coupon_tips.payer_user_id`，且 Stripe 扣款 Customer 对应该用户。
2. 验证 `**flow` 契约**：商户端仅在 `merchant_fallback` 时拿到并使用 `client_secret`；`requires_customer_action` 时响应中**无** `client_secret`。
3. 验证 **SCA 链路**：持券人收到推送（或从通知中心进入）→ 打开 `/tips/confirm/:tipId` → `confirm-tip-payment-session` → PaymentSheet → Webhook 后 `coupon_tips.status = paid`。
4. 验证 **后备路径**：无 Customer / 无默认卡 / off-session 失败后，商户端 PaymentSheet 仍可完成支付。
5. 验证 **幂等与防重**：同券短时间重复请求、已 `paid` 券、窗口内 `pending` 与 Stripe PI 状态组合行为符合预期。

---

## 二、前置条件

### 2.1 部署与配置


| 项              | 说明                                                                                                            |
| -------------- | ------------------------------------------------------------------------------------------------------------- |
| Edge 已部署       | `create-tip-payment-intent`、`confirm-tip-payment-session` 为当前分支构建；`send-push-notification` 可被 service role 调用 |
| `config.toml`  | `[functions.confirm-tip-payment-session] verify_jwt = true` 与线上一致                                             |
| Stripe Webhook | Test mode 指向 `stripe-webhook`，Signing secret 与 Supabase 环境变量一致                                                |
| 用户端构建          | `deal_joy` 含 `Stripe.urlScheme`、`AndroidManifest` 中 `crunchyplum` / `stripe-redirect`（若测 Android）             |
| FCM（测推送时）      | 持券人设备已登录、通知权限开启；可选：仅用通知中心 DB 记录 + 手动打开 App 内路由                                                                |


### 2.2 测试账号与数据


| 角色     | 用途                                                      |
| ------ | ------------------------------------------------------- |
| 商户账号 A | `dealjoy_merchant`，具备 `scan`，所属门店已绑定 Stripe Connect（测试） |
| 用户 U1  | 自用券：有 `stripe_customer_id` + **默认卡**                    |
| 用户 U2  | Gift 受赠人：核销后应为 `payer`；有/无默认卡各一套数据                      |
| 用户 U3  | 无保存卡或故意清空默认卡：用于 **merchant_fallback**                   |


### 2.3 Stripe 测试卡（官方文档为准）


| 目的                        | 建议                                                      |
| ------------------------- | ------------------------------------------------------- |
| off-session 成功            | 普通测试卡号（无需 3DS）                                          |
| 需 SCA / `requires_action` | 使用 Stripe 提供的 **需认证** 测试卡（如 3DS2 场景卡号，以 Dashboard 文档为准） |
| decline / 硬失败             | 使用 decline 类测试卡，验证是否进入后备或失败提示                           |


---

## 三、测试矩阵（按场景）


| ID    | 场景                                   | 主要断言                                                                                               |
| ----- | ------------------------------------ | -------------------------------------------------------------------------------------------------- |
| TC-01 | 自用券 + 有默认卡 + off-session 成功          | `flow` 为 `completed` 或 `processing`；商户端不弹 PaymentSheet；最终 DB `paid`                                |
| TC-02 | Gift 券 + 受赠人有默认卡 + off-session 成功    | `payer_user_id` = 受赠人；购买者设备**不应**能调 `confirm-tip-payment-session` 成功                               |
| TC-03 | 有 Customer 但无默认卡                     | `flow === merchant_fallback`，且响应含 `client_secret`；商户 PaymentSheet 成功                               |
| TC-04 | 用户无 `stripe_customer_id`             | 同 TC-03                                                                                            |
| TC-05 | off-session 触发 SCA                   | `flow === requires_customer_action`，且 JSON 中不得向商户返回可用 `client_secret`；推送 `data` 含 `tip_id`，不含密钥类字段 |
| TC-06 | TC-05 后持券人打开确认页                      | `confirm-tip-payment-session` 返回 `flow: ready` 与 `client_secret`；PaymentSheet 成功；Webhook `paid`    |
| TC-07 | 非持券人调用 `confirm-tip-payment-session` | HTTP 4xx / `forbidden`，不得返回 `client_secret`                                                        |
| TC-08 | 同券 10 分钟内商户**重复**提交（SCA 未完成）         | 返回与首次一致的 `flow` + 同一 `tip_id`（幂等），不重复创建多笔有效扣款                                                      |
| TC-09 | 已成功 `paid` 的券再次收小费                   | Edge 返回 `already_paid`（或等价错误码），商户端有明确英文提示                                                          |
| TC-10 | Webhook 重复投递                         | `coupon_tips` 仍为单条 `paid`，无重复记账                                                                    |
| TC-11 | 受赠人进入 Voucher Detail 展开 gifted 券     | 受赠人可展开并展示 QR；可左右切换同 deal 的多张券                                                                       |
| TC-12 | 赠予人进入同券 Voucher Detail 安全性校验         | 赠予人可见 gifted 文案，但**不可**展示/出示已赠出券的 QR                                                               |


---

## 四、详细测试步骤

### 4.1 TC-01 / TC-02：off-session 成功（自用 / Gift）

**步骤：**

1. 准备 Deal：`tips_enabled = true`，预设合法；券状态为 `used`，核销门店 = 商户 A。
2. 商户端进入 Collect Tip，选金额（+ 可选签名），提交。
3. 抓包或打日志：记录 `create-tip-payment-intent` 响应 JSON。

**期望：**

- 响应含 `flow` ∈ `completed` | `processing`，含 `tip_id`、`stripe_payment_intent_id`。
- `**flow` 不为 `merchant_fallback` 时**，商户端**不**调用 `Stripe.presentPaymentSheet`（可断点或观察无支付弹窗）。

1. Supabase 表 `coupon_tips`：`payer_user_id` 等于持券人（Gift 下为受赠人 `COALESCE(holder, user_id)`）。
2. Stripe Dashboard → PaymentIntent：`customer` 为持券人 Stripe Customer；`metadata.type = tip`，`transfer_data.destination` 为核销门店 Connect。
3. 等待 Webhook（或同步已成功）：`coupon_tips.status = paid`。

**Gift 额外步骤：** 用购买者账号尝试调用 `confirm-tip-payment-session`（若已知 `tip_id`）：应失败。

---

### 4.2 TC-03 / TC-04：merchant_fallback（无默认卡 / 无 Customer）

**步骤：**

1. 使用 U3 或清空默认支付方式后的持券人，核销并发起小费。
2. 观察 `create-tip-payment-intent` 响应。

**期望：**

- `flow === merchant_fallback`，`client_secret` 非空。
- 商户端进入 PaymentSheet，使用测试卡完成支付。
- Webhook 后 `paid`；PI metadata 仍为 `type=tip`。

---

### 4.3 TC-05 / TC-06：requires_customer_action + 用户端确认

**步骤：**

1. 使用会触发 **authentication_required** / `requires_action` 的测试卡作为默认卡（见 Stripe 文档）。
2. 商户发起小费。

**期望（商户侧）：**

- `flow === requires_customer_action`；响应体**不包含** `client_secret` 字段（或为空，以产品安全要求为准：**不得**可供 PaymentSheet 使用）。
- UI 展示英文提示：已发送至顾客手机、请在 Crunchy Plum App 内批准（与 `collect_tip_page` 文案一致即可）。

**期望（用户侧）：**

1. 持券人设备：收到推送 **或** 在 App 通知中心点击该条通知（`action=tip_confirm`）。
2. 应导航至 `/tips/confirm/:tipId`（路径与路由一致）。
3. 页面自动或重试后调 `confirm-tip-payment-session`：成功时进入 PaymentSheet，完成 3DS。
4. Webhook：`coupon_tips.status = paid`。

**负例（TC-07）：** 另一登录用户伪造 `tip_id` 调用 `confirm-tip-payment-session`：拒绝。

---

### 4.4 TC-08：幂等（重复提交）

**步骤：**

1. 在 TC-05 未完成用户确认前，商户端再次点击「Continue to payment」或等价重试。

**期望：**

- 返回同一业务结果（同一 `tip_id`、仍为 `requires_customer_action` 或 Stripe 当前状态对应 `flow`），**不**产生第二笔并列 `pending` 扣款意图（与实现「10 分钟窗口 + PI 状态」一致）。
- 若实现为 `409 pending_exists`，商户端英文提示可接受（与 `TipPaymentService` 映射一致）。

---

### 4.5 TC-09：已付小费不可再付

**步骤：**

1. 对已完成 `paid` 的券再次发起 Collect Tip。

**期望：**

- Edge 返回冲突/业务错误；商户端 SnackBar 可读；DB 仍仅一条 `paid` 索引约束满足。

---

### 4.6 TC-10：Webhook 幂等

**步骤：**

1. Stripe Dashboard → Webhook → 对同一 `payment_intent.succeeded` **Replay** 一次。

**期望：**

- `coupon_tips` 无重复更新异常；`paid_at` 等字段一致或可幂等覆盖，无重复财务副作用。

---

### 4.7 TC-11 / TC-12：Gift 券 QR 可见性与安全回归

**步骤（TC-11，受赠人）：**

1. 购买者将 2 张同 deal 券赠送给受赠人并完成领取（`current_holder_user_id = 受赠人`）。
2. 受赠人进入 `My Coupons -> Unused -> Voucher Detail`。
3. 点击 `Gifted (2)` 对应区域，尝试展开并进入 QR 弹层。

**期望（TC-11）：**

- 页面出现可点击的券列表（`Tap to show QR code`）。
- 可打开并展示每张券 QR，且支持左右滑动切换 2 张券。
- 不出现 403 / 空列表 / 仅有 Gifted 文案但无法出示的问题。

**步骤（TC-12，赠予人）：**

1. 赠予人进入同一券的 `Voucher Detail`。
2. 验证状态展示与可点击入口。

**期望（TC-12）：**

- 赠予人可看到 `Gifted` 状态与 Gift 信息文案（符合产品语义）。
- 赠予人**不能**进入可出示 QR 的路径（无可用 QR 弹层、无可核销码出示）。

---

## 五、推送与深链（可选专项）


| 步骤           | 期望                                                     |
| ------------ | ------------------------------------------------------ |
| 前台收到 FCM     | 通知标题/正文为英文；点击进 `/tips/confirm/:tipId`                  |
| 应用进程被杀死后点击通知 | 冷启动仍能解析 `tip_id` 并导航（若当前实现依赖 `rootNavigatorKey`，以实机为准） |
| 未登录点击通知      | 应先走登录/redirect，再进入确认页（与 `go_router` redirect 策略一致）     |


---

## 六、数据库与 Stripe 对账检查清单

测试执行人在每个用例结束后勾选：

- `coupon_tips.payer_user_id` 与场景持券人一致  
- `coupon_tips.stripe_payment_intent_id` 与 Stripe Dashboard PI id 一致  
- `coupon_tips.merchant_id` 为核销门店  
- PI `metadata.tip_id` / `coupon_id` 与表一致  
- `stripe-webhook` 日志无重复报错

---

## 七、回归范围（路径 C 不应破坏）

- 未启用小费的 Deal：核销后仍**无** Collect tip 入口  
- `trainee`：仍不可收小费（Edge 403）  
- 订单详情 / Admin 小费展示：仍能看到已付金额（与 P3–P5 一致）  
- 税务/订单其他模块：本次改动**不涉及**受保护税务链路（见仓库 `CLAUDE.md`）
- Gift 券：受赠人可出示，赠予人不可出示（TC-11/TC-12）

---

## 八、通过标准

- §三矩阵中 **TC-01～TC-07** 在 Staging 全部按「期望」通过；**TC-08～TC-12** 至少抽样通过且无阻塞缺陷。  
- 无 `**client_secret` 泄露到商户端** 的安全回归问题。  
- 与 [post-redemption-tipping-qa-checklist.md](./post-redemption-tipping-qa-checklist.md) 合并签字前，再跑一遍 **D 节 Webhook** 与 **H 节 Gift**。

---

## 九、缺陷记录模板（复制使用）


| 缺陷 ID | 用例 ID | 复现步骤 | 实际结果 | 期望结果 | 严重级别     | 状态   |
| ----- | ----- | ---- | ---- | ---- | -------- | ---- |
| BUG-  | TC-   |      |      |      | P0/P1/P2 | Open |


---

*测试执行时以 Stripe / Supabase 官方文档与当前仓库实现为准；卡号与 3DS 行为以 Stripe Test mode 说明为准。*
