# deal_joy 用户端：App Store 审核拒绝项修复计划书

> **文档版本**：2026-05-06  
> **关联提交**：Crunchy Plum iOS 1.0 审核（Submission ID 以 App Store Connect 为准）  
> **依据**：Apple 拒绝信 Guideline **5.1.1(v)**、**2.1(a)**；代码基线 `deal_joy/lib/core/router/app_router.dart` 等。

---

## 1. 背景与问题陈述

### 1.1 Guideline 5.1.1(v) — 非账户功能不得强制注册/登录

**审核描述**：应用在用户浏览商品前要求注册；注册/登录仅可用于账户型功能（如加购、结账等）。

**代码侧根因**：`GoRouter.redirect` 在 `!isLoggedIn` 时，除 `/auth/*` 与 `/onboarding` 外，将绝大多数路径重定向至 `/auth/login`（并带 `redirect` 参数），导致**未登录无法进入 Deals 首页等浏览路径**。

**参考位置**：`deal_joy/lib/core/router/app_router.dart` 中 `redirect` 的 `if (!isLoggedIn) { ... }` 分支。

### 1.2 Guideline 2.1(a) — Profile 登录回流异常

**审核描述**：启动后被迫登录；进入 Profile 再次要求登录，点击登录回到起始页且无法完成登录体验。

**代码侧可能成因（组合）**：

1. **登录成功后硬编码跳转首页**：`LoginScreen` 在 `authNotifierProvider` 成功后执行 `context.go('/home')`，覆盖 `redirect` query 的预期行为。
  - 参考：`deal_joy/lib/features/auth/presentation/screens/login_screen.dart`
2. **Profile 游客入口未携带 `redirect=/profile`**：`ProfileScreen` 使用 `context.push('/auth/login')`。
  - 参考：`deal_joy/lib/features/profile/presentation/screens/profile_screen.dart`
3. **「有 session 但 `currentUserProvider` 为 null」**：`currentUserProvider` 查询 `users` 表失败时 `return null`，Profile 会走 `_GuestProfileBody`，表现为「已登录仍像游客」。
  - 参考：`deal_joy/lib/features/auth/domain/providers/auth_provider.dart`

---

## 2. 目标与验收标准（Definition of Done）

### 2.1 功能目标


| 编号  | 目标              | 说明                                                               |
| --- | --------------- | ---------------------------------------------------------------- |
| G1  | **游客可浏览**非账户型内容 | 至少：首页 Deals、搜索、Deal 详情、商家/品牌页、法律文档等                              |
| G2  | **账户型功能**仍可要求登录 | 结账、订单、券、写评价（若绑定订单）、个人资料编辑、支付方式等                                  |
| G3  | **登录回流正确**      | 从 Profile 发起的登录，成功后回到 Profile（或 `redirect` 指定路径）                 |
| G4  | **消除假游客态**      | 存在有效 `session` 时，Profile 不应因 `users` 行缺失而长期显示完全游客 UI（需降级展示或触发修复） |


### 2.2 测试验收（提审前必测）

1. **卸载重装** → 冷启动：未登录应能进入 `**/home`**（或产品约定的落地页），**不**被全局踢到 `/auth/login`。
2. 未登录打开 `**/deals/:id`**、`**/merchant/:id`**、`**/brand/:brandId**`、`**/search**`：可浏览（若个别接口 401，页面需优雅降级，不得死循环跳转登录）。
3. 未登录点 **结账 / 订单 / 券列表** 等：应引导登录或展示明确拦截，登录后回到**原意图路径**。
4. **Profile → Sign In / Register**：登录成功后回到 `**/profile`**，且展示已登录主体（非 `_GuestProfileBody`）。
5. **iPad**（含 iPad Air 类设备或模拟器）重复 1–4；横竖屏切换无异常。
6. **首次安装 Onboarding**：仍应先 `/onboarding`（与现有 `isFirstLaunchProvider` 逻辑一致），完成后进入可浏览态而非强制登录浏览。

---

## 3. 路由层放开方案（核心）

### 3.1 设计原则

1. **路由层（`redirect`）**：只负责「是否允许进入该 URL」，不做业务细粒度判断（避免 redirect 过于复杂）。
2. **页面 / Provider 层**：对「加购、发起支付、提交订单、发消息」等动作做 **CTA 级登录门禁**（`context.push('/auth/login?redirect=...')` 或弹 Sheet）。
3. `**redirect` query**：继续用于登录后回到深层链接；**禁止**在 `LoginScreen` 内写死 `go('/home')` 覆盖该约定。

### 3.2 实现策略（推荐）

在 `app_router.dart` 的 `!isLoggedIn` 分支中引入 `**isPublicPath(String path, GoRouterState state)`**（或等价辅助函数），规则为：

1. **前缀白名单**：路径以某前缀开头则放行。
2. **精确白名单**：少量完全匹配路径。
3. **默认**：不在白名单 → `return '/auth/login?redirect=...'`（保留现有 `Uri.encodeComponent(currentPath)` 行为）。

> **注意**：`matchedLocation` 对带 path 参数的路由通常为 **规范化路径**（如 `/deals/xxx`），实现时以 `state.matchedLocation` 与 `state.uri.path` 实测为准，避免 `/deals` 无尾段时匹配失败。

### 3.3 未登录「公开访问」白名单（详细清单）

下列路径在 **未登录** 时应 `**redirect` 返回 `null`**（允许进入）。按 **前缀** 与 **精确** 分组，便于编码。

#### A. 启动 / 引导 / 认证页（原有逻辑保持）


| 类型  | 路径或规则         | 说明                                   |
| --- | ------------- | ------------------------------------ |
| 精确  | `/splash`     | Auth loading                         |
| 精确  | `/onboarding` | 首次安装引导（与 `isFirstLaunchProvider` 协同） |
| 前缀  | `/auth/`      | 登录、注册、OTP、忘记密码、重置密码、手机号等             |


#### B. 主壳底部四 Tab（强烈建议整包放行）


| 前缀         | 说明                                                |
| ---------- | ------------------------------------------------- |
| `/home`    | Deals 首页 — **审核核心路径**                             |
| `/chat`    | 聊天列表；内部再对「进入会话 / 发送消息」做门禁                         |
| `/cart`    | 购物车；可对「去结账」做门禁                                    |
| `/profile` | Profile；游客展示 `_GuestProfileBody`，登录按钮带 `redirect` |


> 放行四 Tab 可避免「用户以为能点 Tab，却被全局重定向」的割裂体验，并与 Apple「浏览不必登录」一致。

#### C. 浏览 / 发现 / 详情（公开）


| 前缀           | 说明                                                           |
| ------------ | ------------------------------------------------------------ |
| `/search`    | 搜索页                                                          |
| `/deals/`    | Deal 详情（含 `/deals/:id`）                                      |
| `/merchant/` | 商家详情、相册、静态子路径（含 `/merchant/:id/photos`、`**/merchant/scan`**） |
| `/brand/`    | 品牌聚合页（含 `/brand/:brandId`）                                   |


> `**/merchant/scan`**：若扫码核销涉及账户权限，采用 **进入页面可预览 + 解析结果前要求登录**（页面级），路由仍可放行以避免「一点击 Tab 就踢登录」。

#### D. 法律与营销落地


| 前缀        | 说明               |
| --------- | ---------------- |
| `/legal/` | 法律文档（隐私政策、服务条款等） |
| 精确        | `/invite`        |


#### E. 客服（建议公开 — 利于合规展示与支持）


| 前缀         | 说明              |
| ---------- | --------------- |
| `/support` | 客服入口            |
| 精确         | `/support/chat` |


#### F. 可选公开（产品决策，二选一写进计划）


| 路径            | 方案 A（公开）        | 方案 B（登录门禁）                |
| ------------- | --------------- | ------------------------- |
| `/welcome`    | 未登录可看开屏广告（采用）   | 仅登录后展示（不推荐，易与「冷启动体验」冲突）   |
| `/gift/claim` | 允许打开落地页，领取动作前登录 | 全程需登录（若领取必须绑定账户，可选 B）（采用） |


决策：/welcome采用方案A；/gift/claim采用方案B（gift功能全程需要登录）。

**建议**：`/gift/claim` 若业务上领取必须账户，**路由可放行落地页**，**点击 Claim 前** `redirect` 到登录并带回 `redirect=/gift/claim?...`。

---

## 4. 未登录仍保持「登录门禁」的路径（详细清单）

下列路径在未登录时应 **重定向到** `/auth/login?redirect=...`（或等价），**不允许**直接进入（除非产品明确改为「可进但操作拦截」— 不推荐与下列敏感路径混用）。

### 4.1 结账与支付成功页


| 路径模式                      | 说明           |
| ------------------------- | ------------ |
| `/checkout/:dealId`       | 单 deal 结账    |
| `/checkout-cart`          | 购物车结账        |
| `/order-success/:orderId` | 支付成功页        |
| `/tips/confirm/:tipId`    | 小费 3DS 等支付相关 |


### 4.2 订单、券、售后、退款


| 路径模式                                                    | 说明           |
| ------------------------------------------------------- | ------------ |
| `/orders`                                               | 订单列表         |
| `/order/:orderId`                                       | 订单详情         |
| `/coupon/:couponId`                                     | 单券           |
| `/coupons`                                              | 券列表（含 query） |
| `/voucher/:orderId`                                     | 券包/凭证聚合      |
| `/refund/:orderId`                                      | 退款申请         |
| `/after-sales/:orderId`、`/after-sales/:orderId/request` | 售后时间线 / 申请表  |
| `/my-after-sales`                                       | 我的售后列表       |


### 4.3 评价与「我的」内容


| 路径模式              | 说明           |
| ----------------- | ------------ |
| `/to-review`      | 待评价          |
| `/my-reviews`     | 我的评价         |
| `/review/:dealId` | 写评价（通常绑定订单项） |


### 4.4 Profile 子页（账户设置）


| 路径模式                       | 说明                                        |
| -------------------------- | ----------------------------------------- |
| `/profile/edit`            | 编辑资料                                      |
| `/profile/store-credit`    | Store credit                              |
| `/profile/payment-methods` | **受保护模块**（见 COMPLETED），路由仍应门禁；实现变更需遵守仓库规则 |
| `/profile/change-password` | 改密码                                       |
| `/profile/change-phone`    | 改手机                                       |
| `/profile/billing-address` | 账单地址                                      |
| `/profile/referral`        | 邀请                                        |


### 4.5 收藏与浏览历史（账户型）


| 路径            | 说明                |
| ------------- | ----------------- |
| `/collection` | 收藏夹 — 建议门禁（与账户同步） |
| `/history`    | 历史 — 建议门禁         |


### 4.6 聊天子路由（除 Tab 根 `/chat` 外）


| 路径模式                    | 说明   |
| ----------------------- | ---- |
| `/chat/search`          | 搜索用户 |
| `/chat/friends`         | 好友列表 |
| `/chat/friend-requests` | 好友请求 |
| `/chat/notifications`   | 通知列表 |
| `/chat/:conversationId` | 会话详情 |


> **说明**：放行 `**/chat`** 根路径时，子路由仍按上表门禁，避免游客窥视私信。

---

## 5. 非路由层修改计划（与路由配套）

### 5.1 `LoginScreen` 登录成功跳转

- **修改**：登录成功后优先 `context.go(redirectQuery)`，校验 `redirect` 非空、不以 `/auth` 开头、非循环路径，再 fallback `/home` 或 `/welcome`（与产品一致）。
- **禁止**：无条件 `context.go('/home')`。

### 5.2 `ProfileScreen` 游客登录入口

- **修改**：`onLogin` 使用  
`context.push('/auth/login?redirect=${Uri.encodeComponent('/profile')}')`  
（注册入口同理，若存在）。

### 5.3 `currentUserProvider` 降级策略

- **修改**：`session != null` 且 `users` 表 `.single()` 失败时，不返回 `null`；返回基于 `authState.session.user` 与 `userMetadata` 构造的最小 `UserModel`，或触发一次性修复流程（需评估 RLS 与触发器）。
- **目的**：避免审核员看到「已登录仍显示 Sign in」的假象。

### 5.4 页面级 CTA 门禁（分批落地）

在下列页面/按钮处增加「未登录 → 带 redirect 去登录」：

- `DealDetailScreen`：立即购买 / 加购（**注意**：`deal_detail_screen.dart` 为 COMPLETED 受保护文件时，**不得直接改**；需用户明确授权或把门禁上移到未保护层 — **见第 7 节**）。
- `CartScreen`：去结账。
- `CheckoutScreen`：入口已由路由门禁覆盖时可简化。
- `ChatDetailScreen`：发送消息、拉取历史（若 API 必须 JWT）。

---

## 6. 实施阶段与任务拆分


| 阶段  | 内容                                                        | 产出            |
| --- | --------------------------------------------------------- | ------------- |
| P0  | `app_router.dart`：实现 `isPublicPath` + 调整 `!isLoggedIn` 分支 | 游客可浏览白名单路径    |
| P1  | `login_screen.dart`：`redirect` 优先跳转                       | 修复「回起始页」      |
| P2  | `profile_screen.dart`：游客按钮带 `redirect=/profile`           | 修复 Profile 回流 |
| P3  | `auth_provider.dart`（`currentUserProvider`）：降级用户          | 消除假游客         |
| P4  | 购物车 / 聊天等 CTA 门禁与回归测试                                     | 无业务漏洞         |
| P5  | 版本号递增、App Review Notes 英文说明、录屏 iPad                       | 重新提审          |


---

## 7. 受保护文件与合规实施说明（必读）

根据仓库根目录 `**COMPLETED.md`**：

- `**deal_joy/lib/features/auth/` 整个目录**为已完成模块，禁止在未经用户明确确认的情况下修改。**  
**其中包含 `**login_screen.dart`**、`**register_screen.dart**` 等。

**因此**：

- 若实施 **P1（LoginScreen）** 或任何 `features/auth/` 下文件修改，须 **先向用户说明原因并取得明确确认** 后再改。
- **可选替代方案**（减少触碰受保护目录）：仅在 `app_router` 完成白名单；登录成功跳转改为在 `**authNotifierProvider` 监听处**（若位于非 auth 目录）或通过 **Shell 层 wrapper** 处理 — 需评估架构侵入性；**仍可能**触及 auth 相关代码。

`**deal_detail_screen.dart`** 在 COMPLETED 中列为受保护：**不得在未经授权时**为加购/购买加登录门禁。可行替代：

- 在 **未保护** 的父级 Widget、`HomeScreen` 跳转参数、或 `CheckoutScreen` 入口统一拦截；
- 或由 `**go_router` 的 `redirect` 对 `/checkout/`* 门禁** 覆盖「从详情一键购买」路径。

`**payment_methods_screen.dart`** 等为受保护：路由层保持 `**/profile/payment-methods` 门禁** 即可，避免修改该文件。

---

## 8. 给 App Review 的备注草稿（英文，可贴 App Store Connect）

```text
We addressed Guideline 5.1.1(v) and 2.1(a).

- Guests can now browse deals, search, deal details, and merchant/brand pages without signing in.
- Sign-in is required only for account-based actions (checkout, orders, coupons, account settings, etc.).
- Fixed the Profile sign-in loop: signing in from Profile returns to Profile after authentication.
- Fixed an edge case where an authenticated session could still show the guest Profile UI.

Tested on iPhone and iPad (clean install).
```

---

## 9. 风险与回滚


| 风险                         | 缓解                                                      |
| -------------------------- | ------------------------------------------------------- |
| 公开路由后某页直接调需 JWT 的 API 导致报错 | 页面 `AsyncValue` 错误态 + 登录引导，不全局 redirect 死循环             |
| Onboarding 后仍跳登录           | 明确 `isFirstLaunch` 完成后默认 `go('/home')` 而非 `/auth/login` |
| 改动 auth 受保护目录引发流程回归        | 完整跑一遍邮箱 / Google / Apple 登录与密码重置                        |


**回滚**：保留 `app_router` 修改前的分支或 tag；白名单可开关（`kDebugMode` 下日志打印当前 path 是否 public）。

---

## 10. 附录：当前 `go_router` 路由一览（便于核对白名单）

> 摘自 `deal_joy/lib/core/router/app_router.dart`（以代码为准，实施时 diff 核对）。

- `/welcome`、`/onboarding`、`/splash`
- `/auth/login`、`/auth/register`、`/auth/verify-otp`、`/auth/forgot-password`、`/auth/reset-password`、`/auth/phone`
- Shell：`/home`、`/chat`、`/cart`、`/profile`
- `/profile/edit`、`/profile/store-credit`、`/profile/payment-methods`、`/profile/change-password`、`/profile/change-phone`、`/profile/billing-address`、`/profile/referral`
- `/invite`
- `/merchant/scan`、`/brand/:brandId`、`/merchant/:id`、`/merchant/:id/photos`
- `/search`、`/deals/:id`
- `/checkout/:dealId`、`/checkout-cart`、`/order-success/:orderId`
- `/coupon/:couponId`、`/after-sales/...`、`/my-after-sales`
- `/orders`、`/to-review`、`/my-reviews`、`/order/:orderId`、`/voucher/:orderId`
- `/collection`、`/history`、`/refund/:orderId`、`/coupons`、`/gift/claim`
- `/tips/confirm/:tipId`
- `/support`、`/support/chat`
- `/chat/search`、`/chat/friends`、`/chat/friend-requests`、`/chat/notifications`、`/chat/:conversationId`
- `/review/:dealId`
- `/legal/:slug`

---

**文档结束**