# 账户删除功能开发计划书（商家端 + 客户端）

> **文档版本**：2026-05-08  
> **背景**：Crunchy Plum **Merchant** 因 Guideline **5.1.1(v)** 被拒（支持账户创建须提供账户删除）；**Customer** 端建议同步补齐以降低同类拒审风险。  
> **代码基线**：`dealjoy_merchant`（商家端）、`deal_joy`（客户端）、`deal_joy/supabase/`（Edge Functions + migrations）。

---

## 1. 目标与验收标准

### 1.1 合规目标（Apple）

- App 内提供**明确入口**发起**账户删除**（非仅 Sign Out、非仅「停用」）。
- 若删除流程有部分在网页完成，App 内须提供**直达完成删除页面的链接**。
- 允许确认步骤防误删；一般行业**不得**将「必须打电话/发邮件才能完成删除」作为唯一路径。
- **重新提审**：真机录屏（注册或演示账号登录 → 进入删除入口 → 完整确认流程），并在 **App Review Information → Notes** 中说明；Resolution Center 英文简述。

### 1.2 业务目标

- **商家端**：删除行为与现有角色模型（店主 / 员工 / 品牌管理员）一致，避免错误关店或遗留僵尸数据。
- **客户端**：若实施「整账号删除」，须与用户理解一致（订单/券/支付数据策略清晰）。
- **后端**：单一可信实现（推荐 Edge Function + service role），避免双 App 各写一套。

### 1.3 Definition of Done（摘要）

| 检查项 | 说明 |
|--------|------|
| 商家端可见「Delete account」类入口 | Settings 或 Account 分组，英文 UI |
| 店主删号 | 未关闭店铺时自动执行与「闭店」等价的业务后再完成删号关联逻辑 |
| 员工删号 | 仅解除 `merchant_staff` 等，**不**关店 |
| 品牌管理员 | 行为按 **§5 待确认项** 定稿后实现 |
| 客户端（若本迭代包含） | Profile 或合规区域提供删除入口 + 调用同一后端能力 |
| 审核材料 | Review Notes + 录屏说明 |

---

## 2. 现状摘要（基于当前仓库）

| 模块 | 现状 |
|------|------|
| 商家端 `SettingsPage` | 有 Sign Out、`Close Store`（`StoreService.closeStore()` → `merchant-store/close`）、`Leave Brand`；**无**账户删除 |
| 身份解析 `MerchantStatusCache` | `brand_admins` → `merchants.user_id`（店主）→ `merchant_staff`（员工） |
| 客户端 Profile | 无「删除账户」相关实现（检索无匹配） |
| 关店 | 已有完整业务语义（状态、deal、退款等），删号流程宜**复用或编排调用** |

---

## 3. 产品策略选项（须与法务/产品对齐）

### 3.1 「删除账户」的语义（二选一或组合）

**方案 A — 整账号删除（删除 Supabase `auth.users` 及合规清理）**

- 用户失去**消费者 + 商家**两侧登录身份（若共用同一 Auth 账号）。
- 最贴近苹果「Account deletion」表述；实现复杂度最高（订单匿名化、Stripe、聊天等）。

**方案 B — 仅撤销商家身份（不删 `auth.users`）**

- 解除 `merchants` / `merchant_staff` / `brand_admins` 等商家侧关联，必要时关店。
- 客户端仍可登录同一邮箱。**存在审核解读风险**：须在 Review Notes 明确，并建议仍提供 **方案 A** 作为「Delete my entire Crunchy Plum account」二级入口或并列入口。

**建议**：至少提供 **方案 A** 作为「Delete account」主路径之一；若上线 **方案 B**，命名须区分（例如 *Withdraw merchant access* vs *Delete account*）。

### 3.2 与客户端删除的关系

- 若采用 **方案 A**：任一端发起删除即全局失效，**须在两端删除确认文案中互相提示**。
- 若仅商家端做 **方案 B**：客户端删号（若后续做 A）时是否允许「保留商家资料」——通常 **不允许**（同一 Auth），除非未来拆分账号体系（本计划默认不拆分）。

---

## 4. 角色与行为矩阵（实现依据）

下表在 **§5 待确认** 定稿后冻结为开发契约。

| 角色 | 识别方式（与现码一致） | 删除账户时默认行为（草案） |
|------|------------------------|----------------------------|
| 门店店主 | `merchants.user_id = auth.uid()` | 若店非 closed：先执行 **与 `closeStore` 等价** 的逻辑；再清理店主身份及关联；处理员工记录（见下） |
| 门店员工 | `merchant_staff` 存在且非店主 | **仅**失效/删除该员工的 staff 行（及依赖数据）；**不关店** |
| 品牌管理员 | `brand_admins` 命中 | **待确认**：是否允许自删、是否需先移交品牌/移除管辖门店 |
| 客户端消费者 | `public.users` + 订单/券等 | **待确认**：匿名化 vs 级联删除范围 |

**店主关店后的员工处理（草案）**

- 该店所有 `merchant_staff`：**`is_active = false` 或删除行**（取决于外键与审计要求）；不在此流程删除他人 `auth.users`。

---

## 5. 待产品 / 法务确认项（请勾选或补充后更新本文档）

以下为实施前必须结论化的事项：

1. **品牌管理员（`brand_admins`）删号规则**  
   - [ ] 允许直接删除，系统自动解除品牌关系（具体数据规则？）  
   - [ ] 必须先移交品牌或移除管理员身份才可删除  
   - [ ] 其他：___________

2. **「删除账户」默认语义**  
   - [ ] 仅方案 A（整账号）  
   - [ ] 仅方案 B（仅商家身份）+ 审核备注策略  
   - [ ] A + B 并列（两个入口，文案区分）

3. **一个 `user_id` 是否可对应多个 `merchants` 店主**（若 DB 允许）  
   - [ ] 删号时关闭/处理所有关联店  
   - [ ] 禁止删号直至仅剩一家或手动处理  
   - [ ] 当前业务不存在多店主：___________

4. **客户端是否与本迭代一并上线删除**  
   - [ ] 是（推荐长期合规）  
   - [ ] 否（仅商家端，接受客户端后续被拒风险）

5. **订单 / 券 / 财务记录**  
   - [ ] 删号后匿名化保留（满足税务/争议）  
   - [ ] 其他策略：___________

6. **Stripe Connect / Customer**  
   - [ ] 删号前必须断开或封禁 Connect 账户的规则  
   - [ ] 委托法务/财务确认后再写入本文档 §7

---

## 6. 技术方案概要

### 6.1 后端（推荐）

- **新建 Edge Function**（名称待定，如 `account-delete` 或按现有命名规范）：
  - 输入：JWT（本人操作）；可选 `scope`: `full` | `merchant_only`（若产品选双方案）。
  - 使用 **service role** 在单事务或有序步骤中执行：
    1. 校验身份与角色（**服务端重算**，不信任客户端）。
    2. 店主分支：若未 closed → 调用与 **`merchant-store/close`** 相同的核心逻辑（抽取共享模块或内部 HTTP 调用，避免两套闭店逻辑分叉）。
    3. 员工分支：仅更新/删除 `merchant_staff`（及必要审计）。
    4. 品牌管理员分支：按 §5.1 实现。
    5. 若 `full`：删除或匿名化 `public.users`、调用 Supabase Admin **删除 auth 用户**、处理 Stripe 侧（若适用）。
  - 输出：统一 JSON（成功 / 可展示错误码）。

- **数据库**  
  - 核对 `merchants`、`merchant_staff`、`users`、`brand_admins` 等 **ON DELETE / RLS**，必要时新增 migration（避免删用户时违反 FK）。

### 6.2 商家端（`dealjoy_merchant`）

- **入口**：`SettingsPage` → Account 分组或独立 **Privacy / Data** → **Delete account**。
- **流程**：说明文案（英文）→ 二次确认（可选再验证密码，视 Auth 能力）→ 调用 Edge Function → 成功则 `signOut` + 导航至登录页。
- **关键文件参考**：  
  - `lib/features/settings/pages/settings_page.dart`  
  - `lib/features/store/services/store_service.dart`（`closeStore` 行为对齐）

### 6.3 客户端（`deal_joy`，若纳入本迭代）

- **入口**：`Profile` 合规区域 **Delete account**（具体路径与 UI 与产品一致）。
- **注意**：`COMPLETED.md` 中 **auth / payment_methods** 等受保护文件——若删号需改 `auth_repository` 或支付相关，须按仓库规则 **事先确认**。
- **关键参考**：`lib/features/profile/presentation/screens/profile_screen.dart`、auth 相关 providers。

### 6.4 推送与第三方

- 删号成功后：清理设备推送 token、邮件订阅偏好等（按现有集成逐项列出任务）。

---

## 7. 风险与依赖

| 风险 | 缓解 |
|------|------|
| 方案 B  alone 可能仍被质疑不符合「删除账户」 | 提供方案 A 或在 Review Notes 中清晰定义 + 法务背书 |
| 闭店与删号两套逻辑不一致 | 闭店逻辑单一来源（共享函数或服务） |
| Stripe / 未结清款项 | 删号前校验与明确错误提示 |
| RLS / FK 导致事务失败 | 预先 migration + 集成测试 |
| 受保护模块修改受限 | 提前列文件清单走 `/protected` 确认流程 |

---

## 8. 任务拆分（建议迭代顺序）

| 序号 | 任务 | 产出 |
|------|------|------|
| T0 | 确认 §5 全部选项 | 更新本文档「已确认」节 |
| T1 | 后端删号 API（含角色分支 + 店主闭店编排） | Edge Function + 必要 migration |
| T2 | 商家端 UI + 调用 + 错误处理 | 可测 APK/IPA |
| T3 | 集成测试（店主 / 员工 / 品牌管理员） | 测试用例或 Maestro 脚本 |
| T4 | 客户端删号（若 T0 选定） | 同上 |
| T5 | Review Notes 模板 + 录屏脚本 | 提审材料 |
| T6 | （可选）管理后台 / 审计日志查询 | 运营支持 |

---

## 9. 提审检查清单

- [ ] 真机录屏涵盖：登录 → 进入删除入口 → 确认至完成（或到达合规网页并完成）
- [ ] App Review Information → Notes 附录屏链接或说明
- [ ] Resolution Center 英文简短回复
- [ ] 版本号 / Build 递增
- [ ] 若修改受保护文件，已有书面授权记录

---

## 10. 文档维护

- **负责人**：___________  
- **变更记录**：在 PR 或本文档末尾追加日期与摘要。  
- §5 全部确认后，将结论同步至 `COMPLETED.md` 或内部 Wiki（若团队有规范）。

---

**文档结束**
