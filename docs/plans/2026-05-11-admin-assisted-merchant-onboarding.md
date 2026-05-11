# 后台代商家注册（商户入驻辅助）开发计划

**文档版本**: v1.1  
**创建日期**: 2026-05-11  
**影响范围**: Supabase Edge Functions、`deal_joy` 数据库与 RLS（按需）、Admin Portal（Next.js）、可选：`dealjoy_merchant` 文档或引导文案  
**相关文档**: [商家邮件与通知](./2026-03-21-email-system.md)、[统一审批中心](./2026-04-01-unified-approvals-page.md)、[分模块活动时间线](./2026-04-03-admin-per-entity-activity-timelines.md)

---

## 一、背景与动机

### 1.1 现状

- 商家端（`dealjoy_merchant`）入驻路径为：**Supabase Auth 建号** → **证件上传至 Storage** → 携带**商家本人 JWT** 调用 Edge Function `merchant-register` 写入 `merchants` / `merchant_documents` 等（见 `lib/features/merchant_auth/services/merchant_auth_service.dart`）。
- `merchant-register`（`deal_joy/supabase/functions/merchant-register/index.ts`）将 **`auth.getUser()` 得到的 `user.id` 固定为 `merchants.user_id`**，并据此做重复申请、品牌关联、活动日志与邮件。若后台管理员使用自己的会话调用该函数，会把商户错误地绑定到管理员账号。

### 1.2 目标

在**后台管理系统**中提供受控能力，由具备权限的运营/管理员**代为完成「账号就绪 + 入驻申请提交（至 pending）」**，降低商家在冷启动阶段的操作门槛，提高有效申请量。

### 1.3 非目标（本阶段明确不做或仅预留）

- **不**声称一键完成 **Stripe Connect**、**合同签署**、**deal 上架** 等后续链路；这些仍遵循现有商家端或独立运营流程（参见 `merchant-withdrawal`、`send-merchant-contract`、`merchant-deals` 等）。
- **不**要求替换商家端自助注册；两种入口长期并存。
- **不**在本计划中强制上线「全量操作审计中台」；仅在既有 `merchant_activity_events` 能力上约定字段语义（见第六节）。

---

## 二、方案概述

| 维度 | 做法 |
| --- | --- |
| 核心原则 | **调用者身份（管理员）** 与 **数据归属（目标商家 `user_id`）** 分离；写入逻辑与 `merchant-register` **语义对齐**，避免双轨业务规则。 |
| 推荐实现 | 新增 Edge Function（建议名：`admin-merchant-onboard` 或与现有 admin 命名规范统一），`Authorization` 为**管理员 JWT**；请求体包含**目标商家标识**（邮箱或已有 `user_id`）及与现网一致的申请表字段。 |
| 服务端实现 | 使用 **service role** 执行：`auth.admin` 创建或解析用户、`public.users` 补丁、`merchants` / `merchant_documents` / 连锁 `brands` + `brand_admins`、邮件与活动日志。入口内校验 **`users.role ∈ ('admin', 'super_admin')`**（与 `deal_joy/supabase/functions/platform-after-sales/index.ts` 中 `resolveAdmin` 类模式对齐）。 |
| 代码复用 | 将 `merchant-register` 中与「目标 `user_id`」无关的校验与插入逻辑抽取为 **`_shared/merchant_application_submit.ts`**（或同等模块），由 `merchant-register` 与 `admin-merchant-onboard` 共同调用，减少漂移。 |

---

## 三、现状依赖（只读梳理，便于开发对齐）

| 组件 | 路径 / 说明 |
| --- | --- |
| 商家端提交 | `dealjoy_merchant/lib/features/merchant_auth/services/merchant_auth_service.dart`：`submitApplication` → `functions.invoke('merchant-register')` |
| 入驻写入 | `deal_joy/supabase/functions/merchant-register/index.ts` |
| 管理员 JWT 校验参考 | `deal_joy/supabase/functions/platform-after-sales/index.ts`：`resolveAdmin`（`users.role`） |
| 代建 Auth 用户参考 | `deal_joy/supabase/functions/merchant-staff-mgmt/index.ts`：`auth.admin.createUser`、邮箱已存在分支 |
| 活动日志 | `deal_joy/supabase/functions/_shared/merchant_activity_log.ts`；现 `merchant-register` 使用 `actor_type: 'merchant_owner'` |
| 邮件 | `buildM1Email` / `buildM2Email` / `buildA2Email` + `sendEmail`（与现注册成功路径一致或可配置） |

---

## 四、功能范围与产品规则（需评审定稿）

### 4.1 后台表单与分支

1. **目标商家账号**
   - **分支 A — 新建账号**：输入联系邮箱、初始密码策略（二选一或组合）：平台生成临时密码 + **强制首次登录重置**；或仅创建用户并发送 **Recovery / Magic link**（推荐，减少明文密码在后台停留）。
   - **分支 B — 已有账号**：输入邮箱或 `user_id`；若已存在 `merchants` 记录，行为与现网「重新提交」一致（更新为 `pending`、清空 `rejection_reason`、替换证件记录）或明确禁止并提示（二选一，**建议与 `merchant-register` 一致：允许重新提交**）。

2. **申请表字段**  
   与 `merchant-register` 的 `RegisterRequest` 对齐：`company_name`、`contact_name`、`contact_email`、`phone`、`category`、`ein`、`address`、可选 `city` / `lat` / `lng`、`registration_type`、`brand_*`、`documents[]`。

3. **证件 `documents`**
   - **方案 1（推荐）**：后台上传文件至 `merchant-documents`，路径约定与商家端一致：`{targetUserId}/{documentType}/{filename}`（见 `MerchantAuthService.uploadDocument`），再将 signed URL 或持久化所需 URL 传入 Edge Function（与现 `file_url` 存储方式一致）。
   - **方案 2**：后台先上传到临时 bucket，Edge Function 用 service role **拷贝**到 `merchant-documents` 下目标路径；需额外清理策略。

4. **证件是否必填**  
   现 `validateRequest` **未强制** `documents.length > 0`。产品需明确：代注册是否必须齐套证件；若允许缺件，审批 SLA 与风控需同步。

### 4.2 成功后的商家侧体验

- 商家使用**自己的邮箱**登录商家端；应能看到 `pending` 申请与已关联材料（与自助路径一致）。
- 若使用「仅发 magic link / 重置邮件」：后台操作成功后需有明确 Toast/日志「邀请邮件已发送」。

### 4.3 合规与风控（产品 + 法务）

- 代填 EIN、执照等敏感信息：**建议**留存「商家授权记录」（纸质/电子签名链接、工单号或上传的授权书）引用号，可存在 `merchant_activity_events.metadata` 或后续专用表（本计划不强制表结构，仅列需求）。
- 权限：**仅 `super_admin` 可代建号** 或 **admin + super_admin** 均可，由角色矩阵定稿。

---

## 五、技术设计要点

### 5.1 新 Edge Function 契约（草案）

- **方法**: `POST`
- **Header**: `Authorization: Bearer <admin_access_token>`
- **Body（JSON）**（字段名可与前端统一为 camelCase，函数内映射 snake_case）:

```json
{
  "target": {
    "mode": "create_user | link_existing",
    "email": "merchant@example.com",
    "user_id": "uuid-optional-when-link_existing",
    "initial_password": "optional-only-if-product-requires"
  },
  "application": {
    "company_name": "...",
    "contact_name": "...",
    "contact_email": "...",
    "phone": "...",
    "category": "Restaurant",
    "ein": "12-3456789",
    "address": "...",
    "city": "...",
    "lat": null,
    "lng": null,
    "registration_type": "single",
    "brand_name": "...",
    "brand_logo_url": "...",
    "brand_description": "...",
    "documents": []
  },
  "audit": {
    "consent_reference": "optional-ticket-or-doc-id",
    "note": "optional-internal-note"
  }
}
```

- **响应**: 与现网类似返回 `merchant_id`、`status`、`brand_id`（若有多店）；错误码区分：`ADMIN_REQUIRED`、`EMAIL_EXISTS`、`ALREADY_MERCHANT`、`VALIDATION_ERROR` 等。

### 5.2 与 `merchant-register` 的行为对齐清单

- [ ] `users`：`role` 更新为 `merchant`；OAuth 无邮箱时用 `contact_email` 回填（与现逻辑一致）。
- [ ] `merchants`：插入或更新（含 `submitted_at`、`status: pending`、重新提交时清空 `rejection_reason`）。
- [ ] `merchant_documents`：重新提交时先删后插（与现一致）。
- [ ] `registration_type === 'multiple'`：`brands`、`brand_admins`、`merchants.brand_id`（与现一致；失败是否阻断需与现网一致或显式改进并文档化）。
- [ ] 邮件：M1/M2/A2 触发条件与现网一致；**收件人**必须为商家联系邮箱 / `auth` 用户邮箱，而非管理员。
- [ ] 活动日志：建议新增 `actor_type` 取值（如 `platform_admin`），`actor_user_id` 为**管理员** `user.id`，`metadata` 中带 `onboarded_user_id` / `merchant_id` / `consent_reference`。

### 5.3 数据库与 RLS

- 优先**不新增迁移**：新函数全程 service role 写入，与 `merchant-register` 相同。
- 若未来改为 RPC + 部分客户端直连，再评估 `merchants` 对 admin 的 `INSERT` policy；本阶段**不要求**。

### 5.4 Admin Portal

- 新页面或挂在「商家 / 审批」模块下：**代入驻表单** + 文件上传组件 + 提交结果展示（`merchant_id`、复制链接给商家登录说明）。
- 调用 `supabase.functions.invoke('admin-merchant-onboard', { body })`，会话为管理员登录态。
- **幂等与防重复提交**：前端按钮 loading；后端对已 `pending` 且短时间内重复请求可做 idempotency-key（可选二期）。

### 5.5 配置与密钥

- 确认 Supabase 项目中已部署新函数；生产环境限制 **仅后台 origin** 或依赖 JWT 即可（与现有 functions 策略一致即可）。

---

## 六、测试计划（概要）

| 类型 | 内容 |
| --- | --- |
| 单元 / 集成（函数内） | `create_user` / `link_existing`；邮箱已存在；已是 merchant 的更新路径；`documents` 空与非空；`multiple` 品牌创建失败时的行为与现网对齐 |
| 安全 | 非 admin JWT 调用返回 403；无 JWT 401；不可伪造 `target.user_id` 越权绑定他人（`link_existing` 仅允许服务 role 在校验邮箱匹配后执行） |
| E2E | Admin 提交 → DB `merchants.user_id` 为目标用户 → 商家端登录可见申请 → 审批流与现网一致 |

---

## 七、交付里程碑（建议）

| 阶段 | 交付物 | 说明 |
| --- | --- | --- |
| M1 | `_shared` 抽取 + `merchant-register` 回归 | 行为与现网完全一致，补充最小回归用例（手动或自动化） |
| M2 | `admin-merchant-onboard` + Supabase 部署配置 | 含管理员鉴权、`create_user` / `link_existing`、邮件与活动日志 |
| M3 | Admin Portal UI | 表单、上传、错误提示、操作指引文案 |
| M4 | 文档与运营手册 | 内部 SOP：何时用代注册、如何取得授权、如何发登录邀请 |

---

## 八、风险与缓解

| 风险 | 缓解 |
| --- | --- |
| 逻辑双份导致与 `merchant-register` 不一致 | **强制**共享模块单一路径写入 |
| 管理员误绑邮箱 | `link_existing` 严格校验邮箱与 `user_id` 一致性；敏感操作仅 `super_admin` |
| 商家从未收到密码 / 无法登录 | 默认走 **邮件邀请 / 重置链接**，后台不展示长期有效明文密码 |
| 活动日志语义混淆 | 区分 `actor_type`，便于时间线与合规追溯 |

---

## 九、开放问题（排期前需闭环）

1. `registration_type === 'multiple'` 时品牌创建失败「不阻断注册」是否仍为产品接受？是否与审批规则冲突？  
2. 代注册时 **M1 欢迎邮件** 文案是否需区分「由平台代为提交」？  
3. 是否记录 **`audit.consent_reference`** 的存储位置（仅日志 vs 独立表）？  
4. 已有 **消费者** 账号同邮箱升维为商家时，购物车/订单等侧影响是否需产品说明？

---

## 十、修订记录

| 版本 | 日期 | 作者 | 说明 |
| --- | --- | --- | --- |
| v1.0 | 2026-05-11 | — | 初版，基于当前 `deal_joy` / `dealjoy_merchant` 代码结构整理 |
| v1.1 | 2026-05-11 | — | 实施闭环：见「十一、已决产品/技术默认项」 |

---

## 十一、已决产品/技术默认项（实施阶段）

以下为开发落地时采用的默认决策，便于与法务/运营后续迭代对照。

1. **连锁 `multiple` 品牌创建失败**：仍**不阻断**入驻主流程（与既有 `merchant-register` 行为一致）。
2. **M1/M2 邮件**：代提交与自助提交**共用**现有模板与触发条件；不在首版单独加「代提交」文案。
3. **`consent_reference` / 内部备注**：写入 `merchant_activity_events.detail` 的 JSON 字符串（字段含 `source: "admin_merchant_onboard"`、`consent_reference`、`admin_user_id`、`onboarded_user_id` 等）。
4. **权限**：`admin-merchant-onboard` 与后台 API 路由均允许 **`admin` 与 `super_admin`**（与 `platform-after-sales` 的 `resolveAdmin` 一致）。管理台 `guanli` 布局已允许 `super_admin` 进入与 `admin` 相同的侧栏导航。
5. **两阶段账号**：Edge Function 支持 `action: "create_account_only"`，便于先拿到 `target_user_id` 再上传 `merchant-documents` 后提交（`submit_application` 在已有用户时用 `link_existing`）。
6. **管理 UI 位置**：实现在 monorepo 的 **`crunchyplum_website`**（路径 `/guanli/merchants/onboard`），与现有「管理后台」同一应用；详细操作见 [`docs/sop/admin-assisted-merchant-onboarding-sop.md`](../sop/admin-assisted-merchant-onboarding-sop.md)。

---

## 十二、实现索引（代码入口）

| 组件 | 路径 |
| --- | --- |
| 共享写入与校验 | `deal_joy/supabase/functions/_shared/merchant_application_submit.ts` |
| 管理员 JWT 解析 | `deal_joy/supabase/functions/_shared/admin_resolve.ts` |
| 商家自助注册（薄封装） | `deal_joy/supabase/functions/merchant-register/index.ts` |
| 管理员代入驻 | `deal_joy/supabase/functions/admin-merchant-onboard/index.ts` |
| Functions 网关 JWT | `deal_joy/supabase/config.toml` → `[functions.admin-merchant-onboard]` |
| 管理台页面 | `crunchyplum_website/app/guanli/(dashboard)/merchants/onboard/` |
| 辅助 API（lookup / 上传证件） | `crunchyplum_website/app/api/guanli/merchant-onboard/` |
