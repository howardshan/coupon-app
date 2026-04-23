# Post-Redemption Tipping — QA 测试清单

> 对应实现计划：[../plans/2026-04-23-post-redemption-tipping.md](../plans/2026-04-23-post-redemption-tipping.md)  
> 适用场景：**生产 Supabase + Stripe 测试模式（沙盒）**、无真实顾客、应用尚未对公众上线时的联调与验收。

---

## 前置条件（开始前一次性确认）

- [ ] 生产 Supabase 迁移已应用：`coupon_tips` 表、`deals` 上 `tips_*` 字段、RLS、`tip-signatures` Storage bucket 存在且可访问策略符合预期
- [ ] 以下 Edge Functions 已部署且为预期版本：  
  `create-tip-payment-intent`、`merchant-scan`、`stripe-webhook`、`user-order-detail`、`merchant-orders`、`merchant-deals`
- [ ] Stripe **测试模式**：Edge 环境变量为 `sk_test_*`；Dashboard → Webhooks（**Test mode**）中 endpoint 指向 `stripe-webhook`，且 **Signing secret** 与 Supabase 中配置一致
- [ ] 商家端 `dealjoy_merchant`、用户端 `deal_joy`、管理端 `admin/`（若使用）均为连接该 Supabase 的**当前构建**

---

## A. Deal 配置（商家端 + `merchant-deals`）

- [ ] **新建 Deal**：创建流程中含「Tipping (after redemption)」；关闭小费时整单可成功提交
- [ ] **开启小费**：`Percent` 与 `Fixed USD` 各保存一次；三档合法预设可保存并回显
- [ ] **非法值**：开启小费但预设全空、百分比 >100、非数字等，服务端拒绝（HTTP 4xx 或明确错误信息）
- [ ] **无 `deals` 权限角色**（如仅 `cashier` / `service`）：前端不可编辑小费配置；直接调用更新接口应 **403**

---

## B. 核销与小费入口（商家端 `dealjoy_merchant`）

- [ ] **未启用小费的 Deal**：核销成功后**不出现**「Collect tip」类入口（与产品一致）
- [ ] **已启用小费**：核销成功后出现 **Collect tip**（或产品定稿英文文案）
- [ ] **`trainee`**：不可核销（或确认按钮不可用）；不可完成收小费
- [ ] **具备 `scan` 的角色**：可核销并进入收小费流程
- [ ] **无 `scan`、仅有订单类权限**（如 `finance`）：不应通过正常导航完成「向顾客收小费」；若通过深链访问，接口应 **403**

---

## C. 收小费支付流程（商家端 + Stripe 沙盒）

- [ ] 选择**一档预设金额**，PaymentSheet（或当前集成方式）可完成支付
- [ ] **自定义金额**：在允许范围内成功；**明显超过服务端规则**时被拒绝
- [ ] **Percent 模式**：小费不超过与基数相关的上限（与计划书 §3.2 一致）
- [ ] **Fixed 模式**：不超过与预设相关的上限
- [ ] 支付成功：端上成功提示；**同一券仅一条 `paid` 小费**（部分唯一索引）
- [ ] **签名（若启用）**：提交后 `coupon_tips.signature_storage_path` 有值，且无前端报错

---

## D. Webhook 与数据库

- [ ] Stripe **Test mode** Webhook 日志中可见对应 **PaymentIntent** 事件
- [ ] 成功后：`coupon_tips.status = paid`，`paid_at`、`stripe_payment_intent_id` 等字段符合预期
- [ ] **失败/取消**（测试卡或取消流程）：状态为 `failed` / `canceled`（与实现一致）；在允许前提下可再次发起新的小费尝试

---

## E. 用户端（`deal_joy`）

- [ ] 登录有权查看该订单的用户，订单详情中对**已付小费**的券展示 Tip 行（金额、支付日期等英文展示）
- [ ] **未付小费**：无错误占位，仅不展示小费行
- [ ] **不暴露**签名图片的公开 URL（仅状态/金额类信息）

---

## F. 商家订单详情（`merchant-orders`）

- [ ] 商家端订单详情中，对应券行展示**已付小费**摘要（与接口返回的 `tip` 一致）

---

## G. 管理端（`admin/`）

- [ ] 管理员打开订单详情：可见 **Tip (paid)** 区块（金额、货币、时间、PI 尾号等）
- [ ] 若有签名：说明为私有存储 / 无公开 URL，符合内网审计预期

---

## H. Gift（若本迭代需覆盖）

- [ ] 赠券后由**持券方**核销，小费由**实际付款用户**完成（与 `payer_user_id` / 持券逻辑一致）
- [ ] 用户端仅展示**当前登录用户**有权查看的订单与小费信息

---

## I. 回归与稳定性（抽样）

- [ ] **非小费**下单、支付、列表/详情无异常
- [ ] **同一订单多张券**：逐张核销后，小费互不串单；每张券独立收小费或跳过符合 v1 设计

---

## 建议执行顺序

1. 完成 **前置条件**  
2. **B → C → D**（核销 + 支付 + Webhook 写库闭环）  
3. **A**（配置与权限）  
4. **E、F、G**（三端展示）  
5. **H、I**（Gift 与回归）

---

## 备注

- 切 Stripe **Live** 前，需在 Live 模式单独配置 Webhook 与 `sk_live_*`，并同步更新 Supabase Secrets；与客户端发版节奏对齐，避免混用 test/live。  
- 本清单为手工 QA 用；自动化测试可按仓库惯例在 `dealjoy_merchant` / `deal_joy` 中增量补充。
