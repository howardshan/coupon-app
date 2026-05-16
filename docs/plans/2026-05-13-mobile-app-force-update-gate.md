# 移动端强制更新闸门（远程可开关）开发计划

**文档版本**: v1.0  
**创建日期**: 2026-05-13  
**影响范围**: Supabase（`deal_joy/supabase/migrations`）、用户端 Flutter（`deal_joy`）、商家端 Flutter（`dealjoy_merchant`）、管理后台 Next.js（`crunchyplum_website/app/guanli`）  
**相关文档**: 与「删号跨端登出」远程信号模式可对照：`deal_joy/supabase/migrations/20260508200000_auth_force_logout_signals.sql`、`deal_joy/lib/shared/services/account_force_logout_listener.dart`（本功能为启动时拉配置，非 Realtime）

---

## 一、背景与动机

### 1.1 现状

- **用户端** `deal_joy` 与 **商家端** `dealjoy_merchant` 均已上架；重大功能迭代后，旧版本可能与后端契约不一致或存在安全/体验风险。
- 两端均已依赖 **同一 Supabase 项目**（`supabase_flutter`），且已包含 **`package_info_plus`**、**`url_launcher`**（见各自 `pubspec.yaml`），具备实现「读当前版本 + 跳转商店」的基础。
- **管理后台**位于独立仓库 **`crunchyplum_website`**，路径前缀 `/guanli`，已有「设置类」页面与 **Server Action + `getServiceRoleClient()`** 写库模式（参考 `app/guanli/(dashboard)/settings/referral/actions.ts` 与表 `referral_config` 的 RLS 设计）。

### 1.2 目标

1. 旧版本用户**进入应用后**（在浏览主业务前）若命中策略，则展示**不可跳过**的更新提示，主操作跳转至 **App Store / Google Play** 对应应用页。  
2. 是否启用强制、**最低可运行版本**、提示文案等可在 **管理后台** 配置并即时生效（依赖客户端下次拉取配置）。  
3. **用户端与商家端策略分离**（互不影响）。

### 1.3 非目标（本阶段明确不做）

- **不**替代应用商店自身的更新分发机制；仅做客户端闸门与运营配置。  
- **不**要求实现 Google Play **In-App Update** 原生「立即更新」流程（可选二期）；一期统一为打开商店链接即可。  
- **不**将强制更新作为「每次小版本必开」的默认产品策略（产品规则见第六节）。

---

## 二、方案概述

| 维度 | 做法 |
| --- | --- |
| 配置存储 | 新建表 `public.app_version_gate`（名称可评审微调），**每行对应一个应用**：`app_key ∈ ('consumer','merchant')`（或 `deal_joy` / `dealjoy_merchant` 与代码常量一致即可）。 |
| 客户端读配置 | 使用 **Supabase anon 会话** `from('app_version_gate').select().eq('app_key', ...).maybeSingle()`，**无需登录**；启动后尽早请求。 |
| 客户端写配置 | **仅** `service_role`（与 `referral_config` 一致）；匿名与业务 JWT **不可**写。 |
| 管理后台 | 在 `crunchyplum_website` 新增 `/guanli/settings/app-version-gate`（路径可微调），Server Action 校验管理员身份后 **`getServiceRoleClient()`** `upsert` / `update` 对应行。 |
| 版本比较 | 使用 `package_info_plus` 的 `version`（`x.y.z`），**按段数值比较** semver，禁止字符串直接比较。 |
| 失败策略 | 拉取失败（无网、5xx）：**默认不拦截**（避免误杀）；可选：读 `SharedPreferences` 缓存的「上次已知需强更」在短 TTL 内仍拦截（二期）。 |

---

## 三、数据模型（建议字段）

单表多行（每 app 一行），便于扩展与一次性迁移。

| 列名 | 类型 | 说明 |
| --- | --- | --- |
| `app_key` | `text` PK | `'consumer'` = 用户端，`'merchant'` = 商家端（与 Flutter 内常量一致）。 |
| `force_update_enabled` | `boolean` NOT NULL DEFAULT `false` | 总开关：为 `false` 时不展示强制闸门（无论版本）。 |
| `min_supported_version` | `text` NOT NULL DEFAULT `'0.0.0'` | 语义化版本；**当前版本低于该值**且开关为真时拦截。 |
| `message_title` / `message_body` | `text` nullable | 弹窗文案；可为英文主文案，或中英分栏（按产品定）。 |
| `ios_store_url` | `text` nullable | 完整 App Store 产品页 URL；空则 Flutter 使用 `.env` 或编译期常量兜底。 |
| `android_store_url` | `text` nullable | Play 商店或 `market://` 意图 URL；空则兜底。 |
| `updated_at` | `timestamptz` | 默认 `now()`。 |
| `updated_by` | `uuid` nullable FK → `public.users(id)` | 与 `referral_config` 一致，记录最后操作人。 |

**约束建议**：对 `min_supported_version` 使用 `CHECK` 简单校验 `^\d+\.\d+\.\d+`（可选），避免录入非法字符串。

**初始数据**：迁移中 `INSERT ... ON CONFLICT DO NOTHING` 两行，`force_update_enabled = false`，`min_supported_version = '0.0.0'`。

---

## 四、RLS 与安全

对齐 `referral_config` 模式（见 `deal_joy/supabase/migrations/20260429140000_referral_system.sql`）：

1. `ENABLE ROW LEVEL SECURITY`。  
2. **SELECT**：`USING (true)`，允许 **anon + authenticated** 读取（用户未登录也需能拉配置）。  
3. **INSERT / UPDATE / DELETE**：仅 **`TO service_role`** 允许（或仅 `service_role` 可写、禁止 authenticated 写），确保 App 内无法篡改闸门。  
4. **管理后台**仅通过服务端 **`SUPABASE_SERVICE_ROLE_KEY`** 写入，**不得**把 service key 下发到浏览器；沿用 `getServiceRoleClient()`（`crunchyplum_website/lib/supabase/service.ts`）。

**Realtime**：不需要加入 `supabase_realtime` publication（启动时 REST 拉取即可；若需秒级生效可二期订阅该表，非必须）。

---

## 五、Flutter 实现要点（双端复用思路）

### 5.1 共用能力（建议）

- 在各自工程内新增小模块（或若未来抽出 package 再议）：  
  - `version_compare.dart`：`int compareSemver(String a, String b)`。  
  - `app_version_gate_repository.dart`：封装 Supabase `select`。  
  - `app_version_gate_provider.dart`（Riverpod）：`AsyncValue<AppVersionGateState>`，`forceBlocked` / `message` / `storeUrls`。  
- **用户端** `app_key` 固定 `consumer`；**商家端** 固定 `merchant`（与 DB 一致）。

### 5.2 调用时机

| App | 建议挂载点 | 说明 |
| --- | --- | --- |
| `deal_joy` | `lib/main.dart` 在 `Supabase.initialize` 成功之后、`runApp` 之前**或** `lib/app.dart` 中 `MaterialApp.router` 外层包一层 `Consumer` + 根据 gate 状态切换子树 | 须在 **go_router 主导航** 展示前完成首次判定，避免用户先进入首页再被挡。若放 `main.dart`，需注意已在 `UncontrolledProviderScope` 内可读 Riverpod。 |
| `dealjoy_merchant` | `lib/main.dart` 的 `DealJoyMerchantApp` 根部或首帧 `addPostFrameCallback` 前发起请求 | 与现有 `AccountForceLogoutListener` 的 `addPostFrameCallback` 并存时注意顺序：**先版本闸门，再绑定删号监听** 或并行均可，但闸门为阻塞 UI 时应优先。 |

### 5.3 UI 行为

- 全屏 `Scaffold`：`barrierDismissible: false` 的等价体验（无返回关闭）；**系统返回键**在 Android 上建议 `PopScope(canPop: false)` 或仅允许退出应用（按产品）。  
- 主按钮：`url_launcher.launchUrl(Uri.parse(...), mode: LaunchMode.externalApplication)`。  
- **iOS**：必须使用 **HTTPS App Store 链接**；从 App Store Connect 复制。  
- **文案**：说明「需更新以继续使用」，避免暗示绕过 IAP 等违规表述。

### 5.4 环境变量（建议）

- 在 `.env` / 构建配置中保留 **兜底商店 URL**（当 DB 字段为空时使用），避免迁移遗漏导致按钮无效。

### 5.5 测试矩阵（手工）

- 开关关：任意版本可进。  
- 开关开、`min` 高于当前：拦截 + 跳转可用。  
- 开关开、当前 ≥ `min`：不拦截。  
- 无网 / Supabase 超时：不拦截（默认策略）。  
- 商家端与用户端分别改 DB 一行，互不影响。

---

## 六、管理后台（`crunchyplum_website`）

### 6.1 页面与导航

- 新增设置页：例如 **`/guanli/settings/app-version-gate`**。  
- 在 `components/sidebar.tsx` 的 Settings 分组中增加入口（与 Splash、Referral 等并列）。  
- UI：**两个 Tab 或两个卡片**：「用户端 Crunchy Plum」「商家端 Merchant」，分别加载/保存对应 `app_key` 行。

### 6.2 Server Actions

- 新建 `app/guanli/(dashboard)/settings/app-version-gate/actions.ts`（路径随项目惯例）。  
- **读取**：`getServiceRoleClient()` `select` 两行（或单次 `select` 再按 key 拆分）。  
- **保存**：校验 `min_supported_version` 格式；`update` 对应 `app_key`；`revalidatePath`。  
- **权限**：与 `referral/actions.ts` 的 `requireAdmin` 对齐；若站内惯例为 `admin` **与** `super_admin` 均可操作，则与 `app/guanli/(dashboard)/merchants/page.tsx` 等页一致扩展角色判断，避免 super_admin 无法保存。

### 6.3 运营说明（可写在页面底部）

- 应急：新版本包有严重问题时，**先关闭 `force_update_enabled`**，再协调商店回滚/热修。  
- 建议仅在不兼容或高风险阶段打开强制，与「每次发版必强制」区分。

---

## 七、实施任务分解（建议顺序）

| 序号 | 任务 | 产出 / 验收 |
| --- | --- | --- |
| 1 | **Supabase 迁移**：建表、约束、种子两行、RLS、`COMMENT` | `supabase db reset` 或 CI 迁移通过；anon 可读、authenticated 不可写、service_role 可写。 |
| 2 | **用户端 Flutter**：Repository + Provider +  semver 工具 + 全屏页 + `main`/`app` 集成 | 调低/调高 `min_supported_version` 与开关，行为符合第五节矩阵。 |
| 3 | **商家端 Flutter**：同上（复制微调 `app_key` 与兜底 URL） | 同上。 |
| 4 | **管理后台**：设置页 + actions + sidebar 链接 | super_admin/admin 可保存；保存后 App 下次冷启动或重新拉取可见（可文档说明刷新间隔）。 |
| 5 | **文档 / 运维**：在内部 Wiki 或 `docs/sop` 补充「何时打开强制、如何填版本号、商店链接从哪里复制」 | 运营可独立操作，无需改代码发版（除兜底 URL 变更外）。 |

---

## 八、风险与依赖

| 风险 | 缓解 |
| --- | --- |
| 配置错误导致全员无法进入 | 保留总开关；DB 手改一行即可恢复；管理页显著提示。 |
| 商店链接错误或地区差异 | 使用官方产品页 URL；两端兜底 `.env`。 |
| 审核人员使用旧包测试 | 保持默认 `force_update_enabled = false`；或审核期临时将 `min_supported_version` 设为足够低。 |
| 双仓库发布顺序 | 先合并并部署 **迁移**，再发管理页，再发 App（App 需兼容「表不存在」的旧后端时，应在代码里 catch 并视为不拦截——仅当迁移未上线时短暂存在）。 |

---

## 九、可选二期（不在一期范围）

- 拉取失败时读取本地缓存的「强更」状态（短 TTL）。  
- Android Play **In-App Update**（`in_app_update`）。  
- `recommended_version` + 可关闭的软提示弹窗。  
- Supabase **Realtime** 订阅配置表，配置变更后提示用户重启（边际收益有限）。

---

## 十、参考路径速查

| 组件 | 路径 |
| --- | --- |
| 用户端入口 | `coupon-app/deal_joy/lib/main.dart`、`coupon-app/deal_joy/lib/app.dart` |
| 商家端入口 | `coupon-app/dealjoy_merchant/lib/main.dart` |
| 删号登出监听（全屏不可关弹窗参考） | `coupon-app/deal_joy/lib/shared/services/account_force_logout_listener.dart` |
| Referral 配置表与 RLS 范例 | `coupon-app/deal_joy/supabase/migrations/20260429140000_referral_system.sql` |
| 管理端 Server Action 范例 | `crunchyplum_website/app/guanli/(dashboard)/settings/referral/actions.ts` |
| 管理端侧边栏 | `crunchyplum_website/components/sidebar.tsx` |

---

**文档维护**：实施过程中若表名、路由或 `app_key` 枚举变更，请同步更新本节与迁移文件名。
