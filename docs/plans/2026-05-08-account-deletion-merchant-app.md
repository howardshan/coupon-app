# 商家端账户删除功能开发计划书（Crunchy Plum Merchant）

> **文档版本**：2026-05-08（rev. 2026-05-09）  
> **关联文档**：[客户端账户删除计划书](./2026-05-08-deal-joy-account-deletion-customer.md) — **与本文档并行落地**同一阶段的账户删除能力。  
> **背景**：Merchant 因 Guideline **5.1.1(v)** 须提供应用内发起的账户删除。  
> **代码基线**：`dealjoy_merchant/`、`deal_joy/supabase/`（Edge Functions + migrations，与客户端共用后端）。

---

## 1. 目标与验收标准

### 1.1 合规目标（Apple）

- App 内提供**明确入口**发起**账户删除**（非仅 Sign Out、非仅「停用」）。
- 若删除流程有部分在网页完成，App 内须提供**直达完成删除页面的链接**。
- 允许确认步骤防误删；一般行业**不得**将「必须打电话/发邮件才能完成删除」作为唯一路径。
- **重新提审**：真机录屏（注册或演示账号登录 → 进入删除入口 → 完整确认流程），并在 **App Review Information → Notes** 中说明；Resolution Center 英文简述。

### 1.2 业务目标

- 删除行为与角色模型（店主 / 员工 / 品牌管理员）一致；**仅店主删号**触发自动闭店编排；**员工删号不关店**。
- **方案 A（整账号）** 与 **方案 B（仅撤销商家身份）** 在 UI 上并列，由用户选择（见 §5.2）。
- 与 **客户端**删号共用后端能力（见关联文档）；两端文案须说明「整账号删除」对另一 App 的影响。

### 1.3 Definition of Done（商家端）

| 检查项 | 说明 |
|--------|------|
| Settings 内可见删除入口 | 英文 UI；含 A/B 选择或分步说明 |
| 店主删号 | 未关闭店铺时先执行与 **`merchant-store/close`** 等价逻辑，再完成身份/关联清理 |
| 员工删号 | 仅处理 `merchant_staff` 等；**不关店** |
| 品牌管理员删号 | 允许直接删除，系统自动解除 `brand_admins` 等品牌侧关联（§5.1） |
| Stripe Connect | **不**在删号流程中断开或封禁 Stripe 侧账户；用户仍可通过 Stripe 官方渠道登录 Connect / Dashboard（§5.6） |
| 审核材料 | Review Notes + 录屏说明 |

---

## 2. 现状摘要（基于当前仓库）

| 模块 | 现状 |
|------|------|
| `SettingsPage` | 有 Sign Out、`Close Store`（`StoreService.closeStore()` → `merchant-store/close`）、`Leave Brand`；**无**账户删除 |
| `MerchantStatusCache` | `brand_admins` → `merchants.user_id`（店主）→ `merchant_staff`（员工） |
| 关店 | 已有完整业务语义；删号流程须**复用或编排调用**同一闭店能力 |

---

## 3. 产品策略（已确认）

### 3.1 方案 A — 整账号删除

- 删除 Supabase `auth.users`（及与计划一致的 `public.users` 等清理）；用户失去**含客户端在内的**同一登录身份。  
- 须与 [客户端计划书](./2026-05-08-deal-joy-account-deletion-customer.md) 中整账号数据策略一致。

### 3.2 方案 B — 仅撤销商家身份

- 解除 `merchants` / `merchant_staff` / `brand_admins` 等商家侧关联；必要时已含店主闭店编排。  
- **不删除** `auth.users`；用户仍可用同一邮箱登录 **Crunchy Plum（客户端）**。  
- UI 文案须与「Delete entire Crunchy Plum account」区分，避免误选。

### 3.3 用户选择方式

- 在发起删除流程时**明确提示**并让用户选择 **仅商家侧（B）** 或 **整账号（A）**。

---

## 4. 角色与行为矩阵（已冻结）

| 角色 | 识别方式（与现码一致） | 删除时的行为 |
|------|------------------------|--------------|
| 门店店主 | `merchants.user_id = auth.uid()` | 若店非 closed：先 **close 等价逻辑**；再清理店主身份；该店 `merchant_staff` **失效或删行**（不删他人 auth） |
| 门店员工 | `merchant_staff` 且非该店 `merchants.user_id` | **仅**解除/失效 staff；**不关店** |
| 品牌管理员 | `brand_admins` 命中 | **允许直接删除**：解除 `brand_admins` 等品牌侧关联；**不**等同于店主闭店（除非该用户同时是店主并按店主分支处理） |
| 多店主 | 同一 `user_id` 若关联多家店主店 | **全部**店铺按店主规则处理（关店 + 清理） |

**客户端消费者**侧数据与整账号删除的衔接见 **关联文档 §4–§6**。

---

## 5. 已确认（产品 / 法务）

| # | 事项 | 结论 |
|---|------|------|
| 5.1 | 品牌管理员删号 | 允许直接删除；自动解除品牌关系；管理员≠店主 |
| 5.2 | 删除语义 | **A + B 并列**；流程中让用户选择仅商家或整账号 |
| 5.3 | 多 `merchants` 店主 | 删号时**关闭/处理所有**关联店 |
| 5.4 | 客户端删号文档 | **单独计划书**：[客户端账户删除计划书](./2026-05-08-deal-joy-account-deletion-customer.md)；与商家端**同一阶段并行开发/发布** |
| 5.5 | 订单/财务记录 | 删号后 **匿名化保留**（税务/争议） |
| 5.6 | Stripe Connect | **不**在应用删号流程中要求断开或封禁 Stripe Connect 账户；**商家仍可通过 Stripe 官方登录**使用其 Connect / Express Dashboard（与 Stripe 侧账户生命周期独立）。应用侧须清理的是 **本产品中与商家账号的绑定关系**（如 `merchants` 上字段、会话），避免已删用户仍从 App 内发起收款操作；具体字段以 T1 数据库审计为准 |

---

## 6. 技术方案概要（商家端）

### 6.1 后端（与客户端共用）

- **Edge Function**（如 `account-delete`）：`scope` = `merchant_only` | `full`（与客户端对齐命名）。
- 步骤要点：服务端重算角色 → 店主则 close → staff / brand_admin 分支 → **`full` 时执行与「从客户端发起整账号删除」同一套用户级流水线**（不得仅删商家表而跳过消费者域）。
- **`full` 与客户端计划书对齐范围（须同一实现、任一入口复用）**：  
  - [客户端 §4](./2026-05-08-deal-joy-account-deletion-customer.md)：订单匿名化、未核销券退款/失效、Gift 送出/接收/退回失败 Fallback（§4.2 等价）与**幂等**、§4.4 其它域（或其实际定稿附录）。  
  - [客户端 §6](./2026-05-08-deal-joy-account-deletion-customer.md)：Stripe **Customer / PaymentMethods** 处理顺序；**不**关闭商家 Connect（本文 §5.6）。
- **`merchant_only`（B）**：仅处理商家侧关联与闭店编排；**不**执行客户端 §4 消费者券/订单流水线（用户仍保留客户端登录）。
- **Stripe**：不在此函数内调用「关闭 Stripe Connect 账户」类 API；`full` 时消费者 **Customer** 清理见客户端 §6。

### 6.2 商家端 App（`dealjoy_merchant`）

- **入口**：`SettingsPage` → Account 或 **Privacy / Data** → 删除流程。  
- **流程**：英文说明（A/B 差异、整账号对客户端影响）→ 二次确认 → 调 Edge Function → 成功则 `signOut` 并导航登录页。  
- **参考文件**：`lib/features/settings/pages/settings_page.dart`、`lib/features/store/services/store_service.dart`。

### 6.3 推送与本地

- 删号成功后：清理本机持久化门店 ID、推送 token 等（与 `StoreService` / 推送集成对齐）。

---

## 7. 风险与依赖

| 风险 | 缓解 |
|------|------|
| A/B 文案不清导致误删整账号 | 强确认文案 + 二次输入或显式勾选 |
| 闭店与删号逻辑分叉 | 闭店唯一来源（与 `merchant-store/close` 共享） |
| 整账号与客户端数据不一致 | 共用 Edge Function 用户分支；双文档对齐评审 |
| 受保护文件 | 改前按 `COMPLETED.md` 确认 |

---

## 8. 任务拆分

| 序号 | 任务 | 产出 |
|------|------|------|
| T0 | §5 已确认 | 本文档 rev.2026-05-09 |
| T1 | 后端删号 API（角色 + close + `merchant_only`/`full`） | Edge Function + migrations |
| T2 | 商家端 UI（A/B 选择 + 调用 + 错误处理） | 可测构建 |
| T3 | 集成测试（店主 / 员工 / 品牌管理员 / A / B） | 自动化或清单 |
| T4 | 与客户端 T1 联调 `full` / `merchant_only` | 两端一致行为 |
| T5 | Review Notes + 录屏脚本 | 提审材料 |

---

## 9. 提审检查清单

- [ ] 真机录屏：登录 → 删除入口 → 选 B 或 A → 完成确认  
- [ ] App Review Information → Notes  
- [ ] Resolution Center 英文回复  
- [ ] 版本 / Build 递增  
- [ ] 受保护文件已获授权（如有）  

---

## 10. 文档维护

- **关联**：[客户端账户删除计划书](./2026-05-08-deal-joy-account-deletion-customer.md)  
- **变更记录**  
  - 2026-05-09：拆分为商家专用计划书；确认 5.4 并行客户端独立文档、5.6 Stripe 策略；§4 矩阵冻结。  
  - 2026-05-10：§6.1 显式对齐客户端 `full` = 共用 §4–§6 用户级流水线；区分 `merchant_only` 不跑消费者域。

---

**文档结束**
