# App 强制更新闸门（运营 SOP）

## 发布顺序

1. 合并并应用 Supabase 迁移 `app_version_gate`（先于依赖该表的管理页与客户端逻辑上线亦可；旧 App 在拉表失败时不拦截）。  
2. 部署管理后台 `crunchyplum_website`（`/guanli/settings/app-version-gate`）。  
3. 发布需要包含闸门逻辑的新版 **用户端 / 商家端** App。

## 配置入口

- 管理后台：**Settings → App version gate**（`/guanli/settings/app-version-gate`）。  
- 用户端与商家端各一行：`consumer` / `merchant`，互不影响。

## 字段说明

| 字段 | 说明 |
| --- | --- |
| Force update | 总开关；关闭后无论版本均不拦截。 |
| Minimum supported version | 语义化版本，形如 `1.0` 或 `1.0.1`；**当前 App 版本低于该值**且开关打开时拦截。 |
| Dialog title / body | 可选；留空则 App 使用默认英文提示。 |
| iOS / Android URL | 可选；留空则使用各 App `.env` 中 `STORE_URL_*` 兜底（见各工程 `Env` / `dotenv` 说明）。 |

## 何时打开强制

- 后端或协议 **不兼容**、旧版会产生错误交易或安全风险时。  
- 避免仅为 UI 小改而长期强制，以免差评与客服压力。

## 应急

- 新包有严重问题：先在后台 **关闭 Force update**，再协调商店回滚或发修复包。  
- 若误配导致无法进入：可直接在 Supabase Table Editor 将 `force_update_enabled` 改为 `false` 或调低 `min_supported_version`。

## 客户端验证（手工）

- 开关关：任意版本可进入。  
- 开关开且最低版本高于当前安装版本：启动后全屏拦截，按钮可打开商店。  
- 开关开且当前版本不低于最低版本：正常进入。  
- 断网：应能进入（不拦截），除非后续实现「缓存强更」二期。
