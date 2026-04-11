# DealJoy 法律合规差距分析报告

> **日期**: 2026-04-09
> **分析范围**: 8 份法律文件 × 全部相关代码（用户端 + 商家端 + Supabase 后端 + Admin）
> **目的**: 识别系统实现与法律文件要求之间的差距，制定修改优先级

---

## 一、法律文件清单

| # | 文件 | 版本 | 适用对象 |
|---|------|------|---------|
| 1 | Terms of Service (ToS) | v6 | 用户 |
| 2 | Privacy Policy | v2 | 用户 + 商家 |
| 3 | Refund Policy | v2 | 用户 |
| 4 | Gift Terms | v3 | 用户 |
| 5 | Merchant Agreement | v3 | 商家 |
| 6 | Merchant Payment & Settlement Terms | v2 | 商家 |
| 7 | Merchant Terms of Use | v3 | 商家 |
| 8 | Advertising Terms | v3 | 商家 |

---

## 二、已实现的合规功能

| 功能 | 法律依据 | 实现位置 | 说明 |
|------|---------|---------|------|
| 法律文档版本管理 | ToS §2 | `legal_documents` + `legal_document_versions` 表 | 支持版本控制、发布管理 |
| APPEND-ONLY 审计日志 | 通用合规 | `legal_audit_log` 表 | SHA256 完整性校验、IP/UA/设备记录 |
| 用户同意追踪 | ToS §2 | `user_consents` 表 + ConsentBarrier 弹窗 | 注册时 + App 启动时检查待签文档 |
| 商家同意追踪 | Merchant Agmt §2 | AppShell consent 检查 | 启动时弹窗强制签字 |
| 营销 opt-in 独立于 ToS | Privacy Policy §8 | `register_screen.dart` 单独复选框 | `marketing_opt_in` 字段，默认 false |
| 分析数据 opt-in | Privacy Policy §8 | `register_screen.dart` 单独复选框 | `analytics_opt_in` 字段，默认 false |
| 退款双通道 | Refund Policy §3 | `create-refund` Edge Function | Store Credit（全额含服务费）/ 原支付方式（不含服务费） |
| 过期自动退款 | Refund Policy §5 | `auto-refund-expired` cron job | 批量处理，含 gifted 券特殊处理 |
| 赠送券基础流程 | Gift Terms §1-3 | coupon_gifts + 状态管理 | gifted 状态、过期退还给赠送者、C15 邮件 |
| 服务费不退（原支付方式） | Refund Policy §3 | `create-refund` 逻辑 | Store Credit 退全额，原支付方式不退服务费 |
| Store Credit + 混合支付 | Refund Policy §6 | `create-payment-intent` | 支持 Store Credit 抵扣 + 剩余 Stripe 扣款 |
| 购买数量限制 | ToS §7 | `create-payment-intent` | `max_per_account` 校验 |
| Stripe PCI DSS 合规 | ToS §11 | 全局 | 不存储完整卡号/CVV，仅 last-4 + token |
| RLS 行级安全 | 通用安全 | 主要表均有 RLS | 用户/商家仅可见自己的数据 |
| 占位符动态替换 | Merchant Agmt §6 | `render_legal_document()` RPC | 支持商家独立佣金率渲染 |
| Admin 法律文档管理 | ToS §2 | `admin/app/(dashboard)/settings/legal/` | 文档创建、编辑、发布、版本管理 |
| 税务计算 | ToS §11 | `metro_tax_rates` 表 | 按地区税率计算，计入 order_items |
| 邮件通知体系 | 多条 | `_shared/email.ts` | C2/C5-C8/C15/M8/A4 等邮件模板 |
| `requires_re_consent` 标志 | ToS §2 | `legal_documents.requires_re_consent` | 版本变更后强制重新签字 |

---

## 三、合规差距清单

### P0 — 法律强制要求（缺失可能导致法律风险）

#### 1. 年龄验证（18+）

| 项目 | 内容 |
|------|------|
| **法律依据** | ToS §4.2 "You must be at least 18 years of age"；Privacy Policy §10 COPPA 合规 |
| **当前状态** | 注册页面未收集出生日期（DOB），无法验证用户是否满 18 岁 |
| **风险** | 违反 COPPA（向未满 13 岁儿童收集数据），违反 ToS 自身条款 |
| **需要修改** | |

- **数据库**: `users` 表添加 `date_of_birth DATE` 字段
- **后端**: `handle_new_user()` trigger 从 metadata 读取 DOB
- **用户端**: `register_screen.dart` 添加日期选择器（注：受保护文件，需用户确认）
- **用户端**: `auth_repository.dart` 注册时传递 DOB metadata（注：受保护文件，需用户确认）
- **校验**: 后端拒绝 DOB 计算年龄 < 18 的注册

---

#### 2. Paid Value 与 Promotional Value 分离

| 项目 | 内容 |
|------|------|
| **法律依据** | ToS §6.6 "Paid Value 在购买后至少 5 年内不会过期"；Refund Policy §5 |
| **当前状态** | 数据模型中 `unit_price` 是单一字段，未区分 paid_value 和 promotional_value |
| **风险** | 无法执行"Promotional Value 过期但 Paid Value 仍可退还"的法律要求 |
| **需要修改** | |

- **数据库**: `deals` 表添加 `paid_value NUMERIC` 和 `promotional_value NUMERIC`
- **数据库**: `order_items` 表添加 `paid_value` 和 `promotional_value` 快照字段
- **后端**: `auto-refund-expired` 在 promotional value 过期时只退 paid_value
- **后端**: `create-refund` 根据是否过期决定退全额还是仅 paid_value
- **前端**: Deal 详情页展示 paid value 和 promotional value 的区别

---

#### 3. Store Credit 完整生命周期

| 项目 | 内容 |
|------|------|
| **法律依据** | Refund Policy §6 全文 |
| **当前状态** | 有 `add_store_credit()` RPC 和余额，但缺少完整生命周期管理 |
| **风险** | 违反 Texas 无人认领财产法，用户资金保护不当 |
| **需要修改** | |

**3a. Store Credit 分类追踪**
- `store_credits` 表（或现有表）区分 `user_funded_balance`（用户退款所得）和 `platform_granted_balance`（平台赠送）
- 平台赠送部分在账户关闭时作废，用户退款部分不可作废

**3b. 账户关闭 30 天通知期**
- 用户请求关闭账户 → 设置 `account_closure_requested_at`
- 30 天内用户可使用/提取 Store Credit
- 30 天后自动执行关闭，平台赠送余额清零

**3c. 托管余额（Custodial Balance）**
- 新增 `custodial_balances` 表
- 30 天通知期过后，user_funded 余额转入 custodial_balances
- 领取时需身份验证（最后 4 位卡号 + 购买历史细节）

**3d. 3 年休眠检测 + TX 无人认领财产报告**
- 追踪 `users.last_login_at`、`users.last_transaction_at`
- 3 年无登录/交易 → 转入 custodial balance
- 再满 3 年 → 报告给 Texas Comptroller
- Cron job 定期检查

---

#### 4. Deal 有效期 ≤ 90 天强制约束

| 项目 | 内容 |
|------|------|
| **法律依据** | ToS §6.6, Merchant Agreement §5.1 |
| **当前状态** | 无数据库层面或前端/后端的 90 天校验 |
| **风险** | 商家可创建超过 90 天的 Deal，违反合同条款 |
| **需要修改** | |

- **数据库**: `deals` 表添加 `CHECK (validity_period_days <= 90)`（或等效约束）
- **后端**: `merchant-deals` Edge Function 校验有效期
- **商家端**: `deal_create_page.dart` / `deal_edit_page.dart` 前端校验（注：受保护文件中的非 Category 部分）
- **用户端**: Deal 详情页展示剩余有效天数警告

---

#### 5. Texas TDPSA 隐私权请求处理

| 项目 | 内容 |
|------|------|
| **法律依据** | Privacy Policy §9 全文 |
| **当前状态** | 无任何隐私权请求处理流程 |
| **风险** | 违反 Texas Data Privacy and Security Act，可能面临 AG 执法 |
| **需要修改** | |

- **知情权/访问权**: API 导出用户所有个人数据
- **更正权**: 允许用户修改个人信息
- **删除权**: 软删除 + 匿名化（排除法律保留的交易/税务记录）
- **数据可移植性**: JSON/CSV 导出功能
- **Admin 后台**: 隐私请求管理页面（接收、验证身份、处理、响应）
- **计时**: 45 天响应期 + 可延长 45 天
- **申诉**: 60 天内二次响应

---

#### 6. 数据保留策略自动化

| 项目 | 内容 |
|------|------|
| **法律依据** | Privacy Policy §11 |
| **当前状态** | 无自动化数据保留/删除/匿名化机制 |
| **风险** | 超期存储个人数据违反 TDPSA 最小化原则 |
| **需要修改** | |

| 数据类型 | 保留期限 | 操作 |
|---------|---------|------|
| 账户信息 | 活跃期 + 关闭后 3 年 | 匿名化 |
| 交易记录 | 7 年 | 7 年后归档/匿名化 |
| 客服沟通 | 3 年 | 删除 |
| 位置数据 | 仅会话期间 | 不持久化 |
| 商家账户数据 | 关系结束后 7 年 | 匿名化 |
| Google Analytics | 14 个月 | Google 自动处理 |

- 新增 Cron Job 定期扫描并执行保留策略

---

### P1 — 商业运营必须（影响商家结算与核心业务）

#### 7. 商家结算系统（T+7）

| 项目 | 内容 |
|------|------|
| **法律依据** | Merchant Agreement §6, Payment Terms §2 |
| **当前状态** | 完全未实现自动结算 |
| **影响** | 无法按合同约定向商家打款 |
| **需要修改** | |

- **新增表**: `merchant_settlements`
  ```
  settlement_id, merchant_id, period_start, period_end,
  gross_transaction_value, commission_rate, commission_amount,
  refunds_deducted, chargebacks_deducted, rolling_reserve_withheld,
  other_deductions, net_settlement_amount,
  status (pending|scheduled|disbursed|failed),
  disbursement_date, stripe_transfer_id
  ```
- **结算公式**: `Net = GTV - Commission - Refunds - Chargebacks - Rolling Reserve - Other`
- **扣款优先级**: 退款/Chargeback > 佣金 > 准备金 > 其他
- **条件**: Stripe 活跃、无冻结/调查、正余额
- **负余额**: 向下期滚转，30 天未恢复 → 发催款通知
- **Cron Job**: 每日计算 T+7 到期的结算，通过 Stripe Connect Transfer 打款

---

#### 8. 滚动准备金（Rolling Reserve）

| 项目 | 内容 |
|------|------|
| **法律依据** | Merchant Agreement §6.6, Payment Terms §6 |
| **当前状态** | 完全未实现 |
| **影响** | 无法在退款/Chargeback 时从准备金中扣除 |
| **需要修改** | |

- **新增表**: `rolling_reserves`
  ```
  reserve_id, merchant_id, order_item_id,
  amount ([RESERVE_RATE]% of GTV),
  reserved_at, release_eligible_date (reserved_at + 90 days),
  released_date, status (reserved|released|forfeited)
  ```
- **每笔交易**: 扣留 [RESERVE_RATE]% 进入准备金
- **90 天后**: 自动释放（无未决争议时）
- **终止后**: 可持有最长 180 天
- **180 天后**: 未领取 → 报告 TX 无人认领财产
- **可调整**: Admin 可根据风险提高准备金比率（chargeback ratio 高、退款量大、疑似欺诈等）

---

#### 9. Chargeback 追踪与自动响应

| 项目 | 内容 |
|------|------|
| **法律依据** | Merchant Agreement §9, ToS §11.5 |
| **当前状态** | `stripe-webhook` 仅记录 dispute，无后续处理 |
| **影响** | 无法执行合同中的 chargeback 政策（商家通知、比率监控、自动暂停） |
| **需要修改** | |

**9a. Chargeback 记录表**
```
chargebacks: chargeback_id, merchant_id, order_item_id,
amount, network_fee, stripe_dispute_id, reason,
status (received|under_review|won|lost),
merchant_notified_at, evidence_submitted_at
```

**9b. Webhook 增强**（`charge.dispute.created`）
- 创建 chargeback 记录
- 通知商家（邮件 + Dashboard 告警）
- 从结算中扣除（金额 + 网络费用）
- 用户端：标记/暂停发起 chargeback 的用户账户

**9c. 比率监控**
- 计算商家 chargeback ratio（月度）
- 接近阈值时告警
- 超阈值 → 自动暂停结算 + Admin 通知

**9d. 用户 Chargeback 政策**
- 未先联系客服直接发起 chargeback → 违反 ToS §11.5
- 账户暂停/终止
- 30 天窗口允许申请退还未使用的 Paid Value

---

#### 10. 佣金变更 30 天通知

| 项目 | 内容 |
|------|------|
| **法律依据** | Merchant Agreement §6.4 |
| **当前状态** | Admin 可修改佣金率，但无通知机制 |
| **影响** | 未经通知变更佣金违反合同 |
| **需要修改** | |

- Admin 修改 `merchants.commission_rate` 时：
  - 自动发送邮件通知商家
  - 记录变更日期 + 生效日期（30 天后）
  - 30 天内商家可选择终止（邮件/Dashboard 链接）
  - 30 天后自动生效新费率

---

#### 11. 1099-K 税务报告

| 项目 | 内容 |
|------|------|
| **法律依据** | Merchant Agreement §11.2, Payment Terms §8 |
| **当前状态** | 无 1099-K 生成/展示 |
| **影响** | 无法满足 IRS 税务申报要求 |
| **需要修改** | |

- **方案 A**: 利用 Stripe Connect 自动生成 1099-K（推荐）
- **方案 B**: 自行计算年度 GTV（毛额），生成 1099-K 报告
- 商家 Dashboard 展示/下载 1099-K
- 年度自动生成 + 邮件通知

---

### P2 — 合规完善（提升合规程度与用户体验）

#### 12. 法律条款变更邮件通知

| 项目 | 内容 |
|------|------|
| **法律依据** | ToS §2 "notify via in-app notification BEFORE taking effect" |
| **当前状态** | 仅有 App 内 ConsentBarrier 弹窗，无邮件通知 |
| **需要修改** | |

- Admin 发布新版法律文档时 → 自动发送邮件给所有受影响用户/商家
- 邮件包含：变更摘要、生效日期、查看完整文档的链接
- `legal_audit_log` 记录通知发送时间

---

#### 13. 账户终止/暂停完整工作流

| 项目 | 内容 |
|------|------|
| **法律依据** | ToS §18, Merchant Agreement §12-13 |
| **当前状态** | 无完整的暂停/终止流程 |
| **需要修改** | |

**用户端**:
- 用户自助删除账户入口（Profile Settings）
- 账户删除前确认 Store Credit 处理方式
- 平台终止用户 → 取消 license，标记账户

**商家端**:
- 商家 30 天提前通知终止
- 平台终止商家（便利/违约两种路径）
- 终止后自动退款所有未兑换 coupon
- 禁用 Dashboard 访问
- 结算最终清算 + 180 天准备金持有

---

#### 14. 已兑换 Deal 退款人工审查

| 项目 | 内容 |
|------|------|
| **法律依据** | Refund Policy §4 |
| **当前状态** | `used` 状态只允许 Store Credit 退款，无 case-by-case 审查 |
| **需要修改** | |

- Admin 后台添加退款审查队列
- 用户提交已兑换退款申请 → 状态变为 `refund_review`
- Admin 批准/拒绝 + 记录原因
- 批准后执行退款（仅退给购买者）

---

#### 15. 赠送券重新发送限制

| 项目 | 内容 |
|------|------|
| **法律依据** | Gift Terms §2 "One re-delivery allowed" |
| **当前状态** | 未实现重发限制 |
| **需要修改** | |

- `coupon_gifts` 表添加 `resend_count INTEGER DEFAULT 0`
- UI 中限制最多重发 1 次
- 超过 1 次时显示"已达最大重发次数"

---

#### 16. 广告系统完善

| 项目 | 内容 |
|------|------|
| **法律依据** | Advertising Terms §1-9 全文 |
| **当前状态** | 仅有 `ad_recharges` 充值基础功能，其余未实现 |
| **需要修改** | |

这是一个完整的独立模块，包含：
- CPC/CPM 广告计费引擎
- 实时/准实时扣费
- 零余额自动暂停投放
- 无效流量（bot/click farm）检测与排除
- 30 天争议窗口 + Admin 审查
- Ad Credit 退款规则（平台停服/商家善意关闭/违约终止 30 天窗口）
- 广告内容审核流程

**建议**: 作为独立项目分期实施

---

#### 17. 商家注册完成后记录同意

| 项目 | 内容 |
|------|------|
| **法律依据** | Merchant Agreement §2 |
| **当前状态** | 注册向导 Step 5 勾选了同意，但未调用 `recordConsent()` |
| **需要修改** | |

- `merchant_register_page.dart` 注册成功后调用 `recordConsent()` 记录：
  - `merchant-agreement`
  - `merchant-terms-of-use`
  - `privacy-policy`
- consentMethod: `'registration'`, triggerContext: `'merchant_registration'`

---

#### 18. 多账户检测

| 项目 | 内容 |
|------|------|
| **法律依据** | ToS §5.4 |
| **当前状态** | 无多账户检测机制 |
| **需要修改** | |

- 追踪设备指纹 / 支付方式 last-4 / IP 地址
- 关联账户检测逻辑
- Admin 后台标记可疑关联账户
- 自动/手动暂停关联账户

---

### P3 — 运营级功能（可后续迭代）

#### 19. 离平台交易检测

| 法律依据 | Merchant TOU §4 |
|---------|----------------|
| **需要修改** | 用户举报入口 + 交易模式分析 + 清算损害金额计算（3x 佣金或 $1,000 取较大值） |

#### 20. 商家数据安全事件冻结

| 法律依据 | Merchant TOU §5.5 |
|---------|-------------------|
| **需要修改** | Admin 一键冻结商家所有待结算款项 + Ad Credit，需商家提供补救证据后解冻 |

#### 21. 评价操纵检测

| 法律依据 | Merchant TOU §8 |
|---------|----------------|
| **需要修改** | 异常评价模式检测（短时间大量好评、同 IP/设备等）+ Admin 审查 + FTC 合规提醒 |

#### 22. Deal 提交审核流程

| 法律依据 | Merchant Agreement §5 |
|---------|---------------------|
| **需要修改** | Deal 状态增加 `pending_review` → Admin 审核 → 发布/拒绝/要求修改 |

#### 23. Cookie 同意横幅（Web 端）

| 法律依据 | Privacy Policy §7 |
|---------|-------------------|
| **需要修改** | Admin 后台或未来 Web 版添加 Cookie 同意横幅 + Analytics opt-out 链接 |

---

## 四、建议执行顺序

### 第一阶段：法律强制（P0）

```
#1  年龄验证 (DOB)          → 注册流程改造
#4  Deal ≤ 90 天约束         → DB + 前后端校验
#2  Paid/Promotional 分离    → 数据模型 + 退款逻辑
#3  Store Credit 完整生命周期 → 新增表 + Cron Job
#5  TDPSA 隐私权请求         → Admin 后台 + API
#6  数据保留自动化            → Cron Job
```

### 第二阶段：商业运营（P1）

```
#7  T+7 结算引擎             → 新增表 + Stripe Connect
#8  滚动准备金               → 新增表 + 结算集成
#9  Chargeback 追踪          → Webhook 增强 + 比率监控
#17 商家同意记录             → 注册流程修复（快速修复）
#10 佣金变更通知             → Admin 操作钩子
#11 1099-K 税务报告          → Stripe Connect 集成
```

### 第三阶段：合规完善（P2）

```
#12 条款变更邮件通知
#13 账户终止/暂停工作流
#14 已兑换退款审查
#15 赠送券重发限制
#18 多账户检测
#16 广告系统完善（独立项目）
```

### 第四阶段：运营优化（P3）

```
#19-23 按业务优先级排序
```

---

## 五、涉及的关键文件

### 需要修改的现有文件

| 文件 | 修改内容 | 受保护? |
|------|---------|--------|
| `deal_joy/lib/features/auth/presentation/screens/register_screen.dart` | 添加 DOB 字段 | **是** |
| `deal_joy/lib/features/auth/data/repositories/auth_repository.dart` | 注册传 DOB | **是** |
| `deal_joy/supabase/functions/create-refund/index.ts` | Paid/Promo value 分离逻辑 | 否 |
| `deal_joy/supabase/functions/auto-refund-expired/index.ts` | Paid value 过期退款逻辑 | 否 |
| `deal_joy/supabase/functions/stripe-webhook/index.ts` | Chargeback 处理增强 | 否 |
| `dealjoy_merchant/lib/features/deals/pages/deal_create_page.dart` | 90天校验 | **部分受保护** |
| `dealjoy_merchant/lib/features/deals/pages/deal_edit_page.dart` | 90天校验 | **部分受保护** |
| `dealjoy_merchant/lib/features/merchant_auth/pages/merchant_register_page.dart` | 添加 recordConsent | 否 |

### 需要新增的数据库对象

| 对象 | 类型 | 用途 |
|------|------|------|
| `custodial_balances` | 表 | 托管余额追踪 |
| `merchant_settlements` | 表 | 商家结算记录 |
| `rolling_reserves` | 表 | 滚动准备金 |
| `chargebacks` | 表 | Chargeback 记录 |
| `users.date_of_birth` | 列 | 年龄验证 |
| `users.last_login_at` | 列 | 休眠检测 |
| `users.account_closure_requested_at` | 列 | 账户关闭流程 |
| `deals.paid_value` / `deals.promotional_value` | 列 | 价值分离 |
| `order_items.paid_value` / `order_items.promotional_value` | 列 | 购买时快照 |
| `deals.validity_period_days CHECK (<=90)` | 约束 | 有效期限制 |
| `coupon_gifts.resend_count` | 列 | 重发限制 |

---

## 六、风险评估摘要

| 风险等级 | 差距数量 | 关键风险 |
|---------|---------|---------|
| **高** (P0) | 6 | COPPA 违规、TX 无人认领财产违规、TDPSA 违规 |
| **中** (P1) | 5 | 商家结算违约、税务申报缺失 |
| **低** (P2) | 7 | 合规完善度不足、用户体验缺陷 |
| **最低** (P3) | 5 | 运营效率，非强制合规 |
