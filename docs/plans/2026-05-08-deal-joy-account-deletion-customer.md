# 客户端（Crunchy Plum / deal_joy）账户删除功能开发计划书

> **文档版本**：2026-05-09  
> **关联文档**：[商家端账户删除计划书](./2026-05-08-account-deletion-merchant-app.md) — 同一阶段**并行**落地；共用 Supabase **Edge Function**（如 `account-delete`）中的用户级分支。  
> **背景**：Guideline **5.1.1(v)** 要求支持账户创建的应用提供账户删除；与商家端一并补齐可降低拒审风险。  
> **代码基线**：`deal_joy/lib/`、`deal_joy/supabase/`。

---

## 1. 目标与验收标准

### 1.1 合规目标（Apple）

- 应用在 **Profile（或合规区域）** 提供可发现的 **Delete account**（或等价英文）入口。  
- 完整删除流程可在 App 内发起并完成（或到达合规的网页完成页且 App 内提供**直达链接**）。  
- 与商家端一致：提审附 **真机录屏** + **Review Notes** 说明。

### 1.2 业务目标

- **整账号删除**：删除 `auth.users`（及计划内的 `public.users` 清理）后，用户无法再使用 **客户端 + 商家端**（同一 Auth）。删除前文案须引用商家端计划 **§3.2**。  
- **订单 / 券 / 支付记录**：与商家端已确认策略一致 — **匿名化保留**（见 §5）。  
- **Gift / 转赠券 / 未核销券**：按 §4 规则实现，避免资金与客诉风险。

### 1.3 Definition of Done（客户端）

| 检查项 | 说明 |
|--------|------|
| Profile 内删除入口 | 英文 UI；含不可恢复提示 |
| 调用统一后端 | 与商家端同一 Edge Function 的 `full`（及若产品需要「仅消费者数据」扩展，在 T0 命名） |
| 敏感模块 | 涉及 `features/auth/`、`payment_methods` 等 **COMPLETED 受保护文件** 时须事先授权 |
| 审核材料 | Review Notes + 录屏（登录 → Profile → Delete → 确认完成） |

---

## 2. 现状摘要

| 模块 | 现状 |
|------|------|
| Profile | `profile_screen.dart` 等；**无**「删除账户」入口 |
| Auth | Supabase Auth；`auth_repository` 等受保护 |
| 订单 / 券 / Gift | `features/orders/`（含 coupon、gift 逻辑）；多表与 `user_id` / `order_id` 关联 |
| 支付 | Stripe Customer / PaymentMethods；`payment_methods_screen` 等受保护 |

---

## 3. 与商家端的关系

| 场景 | 行为 |
|------|------|
| 用户仅在客户端发起 **整账号删除** | Edge Function `full`：清理消费者数据 + **若存在商家身份则一并按商家计划处理**（或由同一事务编排调用商家分支），避免残留店主/员工行 |
| 用户仅在商家端选 **仅商家身份（B）** | 客户端登录不受影响；客户端计划中的「整账号」仍独立可用 |
| 用户仅在商家端选 **整账号（A）** | 与客户端「整账号」一致；客户端须能处理「已从服务端删除」的登出态 |

**Stripe Connect（商家）**：按商家端计划 **§5.6** — 不在应用删号流程中强制断开 Stripe；商家仍可用 Stripe 官方渠道登录 Connect。**客户端删号**侧重 **Stripe Customer**、保存卡引用等（见 §6）。

---

## 4. 数据域与业务规则（须 T0 细化到表级）

以下每一项在开发前须定稿 **匿名化字段 / 保留主键 / 是否阻断删除**。

### 4.1 订单与支付

- **订单 `orders` / `order_items`**：匿名化 `user_id` 或保留不可识别引用；满足 **§5 匿名化保留**。  
- **退款 / 税务**：与现有 `tax_amount`、退款展示逻辑兼容（仅展示匿名化后的记录）。

### 4.2 优惠券与券状态

- **未核销券**：选项示例 — (a) 发起整账号删除前必须用完或退款完毕；(b) 自动触发与业务一致的退款/失效；(c) 匿名化持有关系。须与运营/法务一致。  
- **已核销 / 已退款**：通常仅匿名化关联用户字段。

### 4.3 Gift（赠送券）

- **送出的 gift**：接收方是否仍有效、发送方记录是否匿名化、`current_holder_user_id` 等字段如何迁移。  
- **收到的 gift**：持有人删除账号后券的归属（退回、失效或转匿名池）。  
- **注意**：`COMPLETED.md` 中 **Gift 相关文件** 可能受保护 — 若改 `coupons_provider` / `coupon_screen` / Edge Functions，须单独确认授权。

### 4.4 其他客户端数据（grep 与 schema 逐项核对）

| 域 | 说明 |
|----|------|
| `saved_deals` / 收藏 | 删除或匿名化 |
| `reviews` | 匿名化作者或按政策保留 |
| `friends` / `chat` / 会话 | 会话成员删除后的展示（占位用户 vs 级联） |
| `referral` / `users.referral_code` | 解除上下级或匿名化 |
| `push` / `device` token | 删除订阅与 token |
| `marketing_opt_in` / 邮件偏好 | 随用户行策略处理 |

---

## 5. 已对齐的跨端结论（来自商家端计划 §5）

| 事项 | 结论 |
|------|------|
| 订单/财务 | **匿名化保留** |
| 整账号 vs 仅商家 | 商家端 **A+B**；客户端主路径为 **整账号删除**（若产品仅需一种，可收敛为仅 `full`） |
| Stripe Connect（商家侧） | **不**强制断开；商家可继续用 **Stripe 官方登录** Connect |
| 并行交付 | 与商家端 **同一阶段**；本文档为客户端专用任务拆解 |

---

## 6. Stripe（客户端侧重）

- **Stripe Customer / 保存卡**：整账号删除时，在服务端按 Stripe API 规范 **detach / 删除 PaymentMethod** 或 **删除 Customer**（以你们合规策略为准），并清理 `public.users` 或侧表中的 `stripe_customer_id` 引用。  
- **与 §5.6 的关系**：商家 **Connect 账户**不因用户删 Crunchy Plum 账号而被 Stripe 侧强制关闭；客户端侧清理的是 **消费者支付身份** 与本 App 的绑定。

---

## 7. 技术方案概要

### 7.1 后端

- 与商家端 **同一 Edge Function**：消费者整账号路径 = `full` 中「用户级」段（orders/coupons/users/auth 等）。  
- **RLS / ON DELETE**：migration 列出所有 `REFERENCES users(id)` / `auth.users`，避免删用户事务失败。

### 7.2 客户端 App（`deal_joy`）

- **入口**：`Profile` → **Delete account**（具体子路径与 UI 稿一致）。  
- **流程**：说明后果（含商家端同一账号）→ 二次确认（可选密码重验）→ 调用 API → 成功 `signOut` → 登录页/欢迎页。  
- **可能涉及文件**（示例，以实际拆任务为准）：`profile_screen.dart`、auth 相关 provider/repository（**受保护须授权**）。

### 7.3 测试

- 覆盖：无券用户、有未核销券、有 gift 进出、有未完成订单、有保存卡；以及「仅删客户端账号但商家端 B 已选」的交叉场景（若保留双路径）。

---

## 8. 任务拆分

| 序号 | 任务 | 产出 |
|------|------|------|
| T0 | 表级规则定稿（§4 每一项） | 更新本文档附录或 Confluence |
| T1 | Edge Function 用户级删除/匿名化实现 | 与商家端 T1 联调 |
| T2 | 客户端 UI + 调用 + 错误处理 | 可测 IPA |
| T3 | 自动化 / 手测清单（含 Gift、券、订单） | QA 记录 |
| T4 | 与商家端 T4 联调 `full` | 双端一致 |
| T5 | Review Notes + 录屏脚本 | 提审材料 |

---

## 9. 风险与依赖

| 风险 | 缓解 |
|------|------|
| Gift/券 逻辑受保护无法改 | 提前列文件清单走授权；或仅后端匿名化不改 UI |
| 删号后 Edge 与 RLS 冲突 | 优先 service role 事务；集成测试 |
| 用户误删 | 强确认 + 可选冷静期（产品可选） |

---

## 10. 提审检查清单（客户端）

- [ ] 录屏含 Profile → Delete → 完成  
- [ ] Review Notes 说明与商家账号关系（若共享 Auth）  
- [ ] 版本 / Build 递增  
- [ ] 受保护文件已授权  

---

## 11. 文档维护

- **关联**：[商家端账户删除计划书](./2026-05-08-account-deletion-merchant-app.md)  
- **变更记录**  
  - 2026-05-09：初版；与商家端拆分；对齐并行交付与 Stripe §5.6。

---

**文档结束**
