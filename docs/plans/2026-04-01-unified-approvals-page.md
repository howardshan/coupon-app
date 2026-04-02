# 后台管理系统 — 统一审批中心开发计划

**文档版本**: v1.2
**创建日期**: 2026-04-01
**最后更新**: 2026-04-02
**目标路由**: `/approvals`
**影响范围**: Admin Portal (Next.js)，不涉及 Flutter 端或 Supabase 后端 schema 变更

---

## 变更记录

| 版本 | 日期 | 变更内容 |
|-----|------|---------|
| v1.0 | 2026-04-01 | 初稿 |
| v1.2 | 2026-04-02 | 根据用户确认更新：① `/after-sales` 整合后完全删除；② 原有页面审批按钮全部移除；③ Deal 上架支持批量审批；④ 补充两种退款流程的区别说明 |

---

## 一、背景与问题

### 现有审批流的分布现状

当前 admin portal 中，需要管理员介入的审批流共有 **4 种**，分散在不同页面：

| 审批类型 | 数据来源 | 触发状态 | 当前入口 | 存在问题 |
|---------|---------|---------|---------|---------|
| 商家注册申请 | `merchants` + `merchant_documents` | `status = 'pending'` | `/merchants` 列表 + `/merchants/[id]` | 与已批准/已拒绝商家混在同一列表，需手动识别 |
| Deal 上架申请 | `deals` | `deal_status = 'pending'` | `/deals` 列表（需手动筛选）+ `/deals/[id]` | 无专属待审队列，容易遗漏；无批量操作 |
| 核销后退款争议仲裁 | `refund_requests` | `status = 'pending_admin'` | **Next.js admin 后台完全缺失** | 商家拒绝后升级至管理员的争议，admin portal 无任何入口 |
| 售后仲裁申请 | `after_sales_requests` | `status = 'awaiting_platform'` | `/after-sales` 独立页 | 已有独立页，但需整合至统一入口后删除 |

### 核心痛点

1. **分散跳转**：4 种审批类型分布在至少 3 个不同页面，高峰期来回切换效率低，容易漏单
2. **信息不完全**：
   - 商家注册：营业执照/证件图片集中在 `/merchants/[id]` 内，需跳转新页才能看
   - Deal 审批：完整配置（套餐、图片、使用规则）需跳转 `/deals/[id]` 查看
   - 退款争议：目前 admin portal 根本没有展示入口，是实际存在的功能空白
   - 售后申请：双方图片证据和 timeline 已在现有抽屉展示，但页面孤立
3. **缺乏全局视角**：没有统一的「待处理数量」汇总，管理员无法一眼判断当前积压情况

---

## 二、两种退款流程的区别

> 本项目存在两套独立的用户投诉/退款流程，二者触发场景和处理机制不同，在审批中心中作为独立 Tab 分开处理。

| 维度 | 核销后退款争议（`refund_requests`） | 售后仲裁申请（`after_sales_requests`） |
|-----|----------------------------------|--------------------------------------|
| **触发时机** | 券核销后 **24 小时内** | 券核销后 **7 天内** |
| **申请粒度** | 订单级别 | Coupon 级别（单张券） |
| **典型场景** | 刚被扫码核销，服务出问题，要求立即退款 | 体验完服务后，对质量/体验不满意，提出正式投诉 |
| **举证能力** | 仅文字理由（`user_reason`，最少 10 字），无图片 | 结构化原因码 + 详细描述（最少 20 字）+ **双方图片证据** |
| **退款细粒度** | 支持通过 `refund_items` JSONB 指定具体商品（部分退款） | 整张 coupon 退款 |
| **升级路径** | 商家拒绝 → **自动**升级管理员（`pending_admin`） | 商家拒绝 → **用户主动**发起平台仲裁（`awaiting_platform`） |
| **SLA 追踪** | 无截止时间字段 | 有 `expires_at` + `escalated_at` 时间戳 |
| **完整 Timeline** | 无 | 有 `timeline` JSONB 记录所有操作 |
| **定性** | "快速退款通道"，诉求直接 | "正式投诉机制"，流程严谨 |

---

## 三、目标

1. 新建 `/approvals` 统一审批中心页面，聚合全部 4 类待审批申请
2. 侧边栏导航新增 Approvals 入口，显示实时待审批总数角标
3. 每类申请提供**右侧抽屉（Drawer）**形式的完整详情，**所有审批操作均在新页面内完成，无需跳转**
4. 补全 `refund_requests` 在 admin portal 的管理员仲裁功能（当前完全缺失）
5. **Deal 上架审批支持批量操作**（多选后一键批量通过 / 批量拒绝）
6. 整合完成后**删除** `/after-sales` 独立页面
7. **移除**原有 `/merchants/[id]`、`/deals/[id]`、`/after-sales` 页面中的审批操作按钮，避免功能重叠

---

## 四、数据层分析

### 4.1 各类申请的数据库查询

**商家注册申请（列表）**
```sql
SELECT id, name, category, contact_name, contact_email, phone, created_at
FROM merchants
WHERE status = 'pending'
ORDER BY created_at ASC;   -- 先进先出
```

**商家注册申请（抽屉详情追加查询）**
```sql
SELECT id, document_type, file_url, file_name, uploaded_at
FROM merchant_documents
WHERE merchant_id = $1
ORDER BY uploaded_at ASC;
```

**Deal 上架申请**
```sql
SELECT
  d.id, d.title, d.description, d.original_price, d.discount_price,
  d.discount_label, d.image_urls, d.stock_limit, d.deal_status,
  d.expires_at, d.created_at,
  d.dishes, d.package_contents, d.usage_notes, d.usage_days,
  d.validity_type, d.validity_days, d.max_per_person, d.is_stackable,
  m.name AS merchant_name, m.address AS merchant_address,
  di.image_url, di.is_primary
FROM deals d
JOIN merchants m ON m.id = d.merchant_id
LEFT JOIN deal_images di ON di.deal_id = d.id
WHERE d.deal_status = 'pending'
ORDER BY d.created_at ASC;
```

**核销后退款争议（管理员仲裁队列）**
```sql
SELECT
  rr.id, rr.refund_amount, rr.refund_items, rr.user_reason,
  rr.merchant_reason, rr.merchant_decided_at, rr.status, rr.created_at,
  o.id AS order_id,
  m.name AS merchant_name,
  u.full_name AS user_name, u.email AS user_email
FROM refund_requests rr
JOIN orders o ON o.id = rr.order_id
JOIN merchants m ON m.id = rr.merchant_id
JOIN users u ON u.id = rr.user_id
WHERE rr.status = 'pending_admin'
ORDER BY rr.created_at ASC;
```

**售后仲裁申请**
```sql
-- 沿用现有 view_merchant_after_sales_requests 视图
-- 详情通过现有 /api/platform-after-sales/[id] API 获取
SELECT id, status, reason_code, reason_detail, refund_amount,
       store_name, user_name, created_at, expires_at
FROM view_merchant_after_sales_requests
WHERE status = 'awaiting_platform'
ORDER BY created_at ASC;
```

### 4.2 待审批数量汇总（用于 Sidebar 角标）

```typescript
// 使用 Promise.all 并行查询，减少加载时间；加 5 分钟缓存避免频繁查库
const [merchantCount, dealCount, refundCount, afterSalesCount] = await Promise.all([
  serviceClient.from('merchants').select('id', { count: 'exact', head: true }).eq('status', 'pending'),
  serviceClient.from('deals').select('id', { count: 'exact', head: true }).eq('deal_status', 'pending'),
  serviceClient.from('refund_requests').select('id', { count: 'exact', head: true }).eq('status', 'pending_admin'),
  serviceClient.from('after_sales_requests').select('id', { count: 'exact', head: true }).eq('status', 'awaiting_platform'),
])
const totalPending = (merchantCount.count ?? 0) + (dealCount.count ?? 0)
                   + (refundCount.count ?? 0) + (afterSalesCount.count ?? 0)
```

### 4.3 新增 Server Actions

在 `admin/app/actions/approvals.ts`（新建）中添加**退款争议仲裁**所需的 actions：

```typescript
// 管理员批准退款争议（触发实际退款）
export async function approveRefundDispute(requestId: string, adminReason?: string): Promise<void>

// 管理员最终拒绝退款争议
export async function rejectRefundDispute(requestId: string, adminReason: string): Promise<void>
```

操作逻辑：
- `approveRefundDispute`：
  1. `requireAdmin()` 验证身份
  2. 更新 `refund_requests` 字段：`status = 'approved_admin'`、`admin_decision = 'approved'`、`admin_reason`、`admin_decided_at = now()`、`admin_decided_by = currentUserId`
  3. 调用 `admin-refund` Edge Function 执行实际退款（**开发前须先阅读该函数接口，确认兼容性**）
  4. `revalidatePath('/approvals')`

- `rejectRefundDispute`：
  1. `requireAdmin()` 验证身份
  2. 更新 `refund_requests` 字段：`status = 'rejected_admin'`、对应决策字段
  3. 可选：发送邮件通知用户（参考现有邮件模板体系，如有对应模板则调用）
  4. `revalidatePath('/approvals')`

在 `admin/app/actions/admin.ts`（已有）中新增**批量 Deal 审批** actions：

```typescript
// 批量上架多个 deal
export async function batchApproveDeal(dealIds: string[]): Promise<{ success: string[]; failed: string[] }>

// 批量拒绝多个 deal（所有 deal 使用同一条拒绝原因）
export async function batchRejectDeal(dealIds: string[], reason: string): Promise<{ success: string[]; failed: string[] }>
```

---

## 五、UI 设计

### 5.1 页面整体布局

```
┌──────────────────────────────────────────────────────────────────┐
│  Approvals                                      [Total: 24]       │
│  ─────────────────────────────────────────────────────────────   │
│  [All (24)] [Merchants (3)] [Deals (8)] [Refund Disputes (5)] [After-Sales (8)]  │
│  ─────────────────────────────────────────────────────────────   │
│                                                                   │
│  ← Deal tab 时显示批量操作栏 →                                     │
│  ☐ Select All    [Batch Approve ▶]  [Batch Reject ▶]             │
│  ─────────────────────────────────────────────────────────────   │
│  TYPE      SUMMARY           SUBMITTER    SUBMITTED    ACTION     │
│  ☐ [Deal]  Summer BBQ...     TopWok       2h ago       [Review]   │
│  ☐ [Deal]  Family Dinner...  TopWok       3h ago       [Review]   │
│  [Merch]   Green Garden...   Jane Doe     4h ago       [Review]   │
│  [Refund]  $28.00 dispute    U***r        1d ago  ⚠️  [Review]   │
│  ...                                                              │
└──────────────────────────────────────────────────────────────────┘
                                         ↓ 点击 Review 按钮
                              ┌──────────────────────────────┐
                              │  右侧抽屉滑出（max-w-2xl）     │
                              │  Deal Review: Summer BBQ Combo │
                              │  ──────────────────────────── │
                              │  图片画廊 / 套餐 / 使用规则    │
                              │  驳回历史                     │
                              │  ──────────────────────────── │
                              │  [Approve & Publish]          │
                              │  [Reject with reason]         │
                              └──────────────────────────────┘
```

### 5.2 Tab 设计

| Tab | 数据条件 | 特殊功能 |
|-----|---------|---------|
| **All** | 4 类合并，按 `created_at ASC`（最老优先） | 无 |
| **Merchant Applications** | `merchants.status = 'pending'` | 无 |
| **Deal Reviews** | `deals.deal_status = 'pending'` | **支持多选 + 批量审批** |
| **Refund Disputes** | `refund_requests.status = 'pending_admin'` | 无 |
| **After-Sales** | `after_sales_requests.status = 'awaiting_platform'` | 无 |

每个 Tab 标签右侧显示该类型数量角标（红色，数量为 0 时不显示）。

### 5.3 列表行设计

每行统一字段：

| 字段 | 说明 |
|-----|-----|
| 多选框 | 仅在 Deal Reviews tab 显示，用于批量操作 |
| 类型标签 | `Merchant` / `Deal` / `Refund Dispute` / `After-Sales`，不同颜色区分；All tab 显示，其余 tab 可省略 |
| 摘要 | 商家名 / Deal 标题 / 退款金额+商家名 / 原因类型 |
| 申请人 | 商家联系人 / 商家名 / 用户（脱敏，格式 `U***r`）|
| 提交时间 | 相对时间（"2h ago"）；hover 显示绝对时间 |
| 超时警告 | 超过 24 小时未处理显示 ⚠️ 图标，行背景浅红色 |
| 操作 | "Review" 按钮，点击开启详情抽屉 |

### 5.4 Deal 批量审批交互流程

```
1. 进入 Deal Reviews tab
2. 勾选多个 deal（支持"Select All"全选当前页）
3. 点击 [Batch Approve] 或 [Batch Reject]
   - Batch Approve：弹出确认框，显示"Approve X deals?"，确认后调用 batchApproveDeal()
   - Batch Reject：弹出输入框，填写统一拒绝原因（所有选中 deal 使用同一条原因），
                   提交后调用 batchRejectDeal()
4. 操作完成后显示结果摘要："X approved, Y failed"
5. 列表自动刷新（router.refresh()）
```

### 5.5 各类型详情抽屉内容

#### 商家注册申请抽屉
```
[基本信息卡]
  商家名 / 公司名 / 类别 / EIN
  联系人 / 联系邮箱 / 电话
  地址 / 申请时间

[证件材料（重点展示区）]
  每张证件：类型标签 + 图片（点击可在新标签页全屏查看）
  支持类型：Business License / Health Permit / Storefront Photo / Owner ID 等

[审批操作区]
  [Approve] → 确认弹窗 → approveMerchant()
  [Reject]  → 必填拒绝原因 → rejectMerchant()

[辅助链接]
  "View Full Profile →" 跳转 /merchants/[id]（只读，无审批按钮）
```

#### Deal 上架申请抽屉
```
[Deal 头部]
  图片画廊（主图 + deal_images，支持翻页）
  标题 / 原价 / 折扣价 / 折扣标签 / 库存上限

[套餐与菜品]
  dishes[] 列表：名称 / 数量 / 小计
  package_contents 套餐说明

[使用规则]
  usage_notes（文字） / usage_days（可用星期）
  max_per_person / validity_type + validity_days / is_stackable

[商家信息]
  商家名 / 地址

[驳回历史]
  若有历史驳回记录，展示记录列表（复用现有 RejectionHistory 组件）

[审批操作区]
  [Approve & Publish] → setDealActive(id, true)
  [Reject]            → 必填原因（min 10字）→ rejectDeal(id, reason)

[辅助链接]
  "View Full Deal →" 跳转 /deals/[id]（只读，无审批按钮）
```

#### 核销后退款争议仲裁抽屉（全新功能）
```
[争议概览]
  退款申请金额 / 申请时间
  订单 ID（点击跳转 /orders/[id]）
  商家名 / 核销门店
  用户（脱敏）/ 核销时间

[争议商品明细]
  解析 refund_items JSONB，逐行展示：
  商品名 | 数量 | 单价 | 申请退款金额
  底部汇总：Total refund $XX.XX

[双方陈述]
  用户申请理由（user_reason）
  商家拒绝理由（merchant_reason）+ 商家拒绝时间

[仲裁操作区]
  [Approve & Refund]  → 确认弹窗（显示"Refund $XX.XX to user?"）→ approveRefundDispute()
  [Final Rejection]   → 必填 admin 拒绝理由（min 10字）→ rejectRefundDispute()
```

#### 售后仲裁申请抽屉（从 /after-sales 迁移）
```
[申请概览]
  原因类型（reason_code，格式化显示）/ 详细说明
  退款金额 / 申请时间 / SLA 剩余时间
  门店名 / 用户（脱敏）

[用户证据]
  user_attachments 图片列表（可点击查看）

[商家反馈]
  merchant_feedback 文字
  merchant_attachments 图片列表

[处理 Timeline]
  timeline JSONB 展开，逐条显示操作记录

[仲裁操作区]
  [Approve & Refund]   → 简短备注（可选）→ 调用现有平台仲裁 API
  [Reject with evidence] → 必填原因 + 必传图片证据 → 调用现有平台仲裁 API
```

---

## 六、文件变更清单

### 6.1 新建文件

| 文件路径 | 类型 | 说明 |
|---------|-----|------|
| `admin/app/(dashboard)/approvals/page.tsx` | Server Component | 并行查询4张表，传递数据给 Client Component |
| `admin/components/approvals-page-client.tsx` | Client Component | 主页面：Tab 切换、列表渲染、批量选择状态、抽屉状态管理 |
| `admin/components/approvals/merchant-drawer.tsx` | Client Component | 商家注册详情抽屉；点击后懒加载 merchant_documents |
| `admin/components/approvals/deal-drawer.tsx` | Client Component | Deal 详情抽屉；复用 RejectionHistory 组件 |
| `admin/components/approvals/refund-dispute-drawer.tsx` | Client Component | 退款争议仲裁抽屉（全新功能） |
| `admin/components/approvals/after-sales-drawer.tsx` | Client Component | 从现有 after-sales-page-client.tsx 提取抽屉逻辑 |
| `admin/app/actions/approvals.ts` | Server Actions | approveRefundDispute / rejectRefundDispute |
| `admin/app/api/approvals/merchant/[id]/route.ts` | API Route | 懒加载商家证件详情（使用 service role client） |

### 6.2 修改文件

| 文件路径 | 改动内容 |
|---------|---------|
| `admin/app/(dashboard)/layout.tsx` | 并行查询4张表待审批总数，传给 Sidebar；加缓存（revalidate: 300） |
| `admin/components/sidebar.tsx` | adminNav 新增 Approvals 链接；接受 `pendingCount` prop 显示角标 |
| `admin/app/actions/admin.ts` | 新增 `batchApproveDeal()` 和 `batchRejectDeal()` |
| `admin/app/(dashboard)/merchants/[id]/page.tsx` | **移除** `<MerchantReviewActions>` 审批组件；保留页面其余内容（基本信息、员工管理、收入数据等） |
| `admin/app/(dashboard)/deals/[id]/page.tsx` | **移除** `<DealReviewActions>` 审批组件；保留页面其余内容（Deal 详情展示、驳回历史查看） |

### 6.3 删除文件

| 文件路径 | 原因 |
|---------|------|
| `admin/app/(dashboard)/after-sales/page.tsx` | 功能已完整迁移至 `/approvals` After-Sales tab，原页面删除 |
| `admin/components/after-sales-page-client.tsx` | 抽屉逻辑已提取至 `approvals/after-sales-drawer.tsx`，原文件删除 |

> **删除前确认**：sidebar.tsx 中移除 after-sales 导航项（如有）；layout 中移除相关引用。

---

## 七、实现步骤（分阶段）

### Phase 1：数据层 + Sidebar 角标

**目标**：侧边栏出现 "Approvals" 入口，角标显示实时待审批总数

1. 修改 `admin/app/(dashboard)/layout.tsx`：并行查询4张表的待审批数量，加 5 分钟缓存，传给 Sidebar
2. 修改 `admin/components/sidebar.tsx`：接受 `pendingCount: number` prop，在 Approvals 链接旁显示红色角标
3. 新建 `admin/app/(dashboard)/approvals/page.tsx`：暂渲染标题和数量统计，验证数据通路

**验收标准**：sidebar 显示 "Approvals" + 角标数字；点击可进入页面；数字与各表实际 pending 数量一致

---

### Phase 2：统一列表（Tab 切换 + 行渲染）

**目标**：5 个 tab 均可切换，列表正确展示，超时高亮

1. 完善 `admin/app/(dashboard)/approvals/page.tsx`：根据 `tab` search param 查询对应表，支持分页（每页 20 条）
2. 新建 `admin/components/approvals-page-client.tsx`：
   - Tab 组件（URL search param 联动）
   - 统一列表行渲染（类型标签、摘要、申请人、时间、超时 ⚠️ 高亮）
   - Deal tab 的多选 checkbox 框架（操作逻辑后续实现）
   - 行点击 / Review 按钮事件占位

**验收标准**：5 个 tab 数据正确；切换时 URL 参数变化；超过 24h 的行背景高亮

---

### Phase 3：商家注册 + Deal 审批抽屉

**目标**：点击行后抽屉滑出，包含完整信息，可在抽屉内完成审批

1. 新建 `admin/app/api/approvals/merchant/[id]/route.ts`：
   - 验证 admin 身份
   - 使用 service role client 读取 `merchants` 完整字段 + `merchant_documents`
   - 返回 JSON

2. 新建 `admin/components/approvals/merchant-drawer.tsx`：
   - 点击触发，内部 fetch API route 懒加载详情
   - 展示基本信息 + 证件图片列表
   - 操作按钮调用现有 `approveMerchant()` / `rejectMerchant()`（来自 `admin.ts`）
   - 操作成功后关闭抽屉 + `router.refresh()`

3. 新建 `admin/components/approvals/deal-drawer.tsx`：
   - Deal 列表查询时已携带详情字段，无需独立 API，直接使用列表数据
   - 展示图片画廊（支持翻页）、套餐、使用规则、驳回历史（复用 RejectionHistory）
   - 操作按钮调用现有 `setDealActive()` / `rejectDeal()`（来自 `admin.ts`）
   - 操作成功后关闭抽屉 + `router.refresh()`

4. **移除** `/merchants/[id]` 中的 `<MerchantReviewActions>` 组件引用
5. **移除** `/deals/[id]` 中的 `<DealReviewActions>` 组件引用

**验收标准**：商家/Deal 抽屉完整展示信息；approve/reject 成功后列表刷新、角标减少；原有 [id] 页面审批按钮已消失

---

### Phase 4：Deal 批量审批

**目标**：Deal Reviews tab 支持多选 + 批量通过/拒绝

1. 在 `admin/app/actions/admin.ts` 新增：
   - `batchApproveDeal(dealIds: string[])`：循环调用现有 `setDealActive(id, true)` 逻辑，返回成功/失败列表
   - `batchRejectDeal(dealIds: string[], reason: string)`：循环调用现有 `rejectDeal(id, reason)` 逻辑

2. 在 `approvals-page-client.tsx` 完善 Deal tab 的批量操作 UI：
   - checkbox 全选 / 单选状态管理
   - 顶部操作栏：选中数量显示、[Batch Approve] / [Batch Reject] 按钮
   - 确认弹窗（Approve）/ 原因输入弹窗（Reject）
   - 操作完成后显示结果摘要 toast

**验收标准**：可多选 Deal；批量 approve/reject 成功执行；结果摘要正确；列表刷新

---

### Phase 5：退款争议仲裁抽屉（补全功能空白）

**目标**：首次在 admin portal 中实现退款争议的管理员仲裁功能

1. 新建 `admin/app/actions/approvals.ts`，实现 `approveRefundDispute` 和 `rejectRefundDispute`
   - **开发前先阅读 `admin-refund` Edge Function 接口，确认与 `refund_requests` 表的兼容性**

2. 新建 `admin/components/approvals/refund-dispute-drawer.tsx`：
   - 展示争议概览、`refund_items` JSONB 商品明细、双方陈述
   - Approve：确认弹窗（显示退款金额）→ `approveRefundDispute()`
   - Reject：必填原因（min 10字）→ `rejectRefundDispute()`

**验收标准**：Refund Dispute 行点击后抽屉正确展示 refund_items 明细和双方陈述；approve 后实际触发退款；reject 后状态变为 `rejected_admin`

---

### Phase 6：售后申请整合 + 删除 /after-sales

**目标**：After-Sales tab 完整可用，原 /after-sales 页面删除

1. 新建 `admin/components/approvals/after-sales-drawer.tsx`：
   - 从 `after-sales-page-client.tsx` 中提取抽屉部分逻辑（展示 + 操作）
   - 保留现有 API 调用（`/api/platform-after-sales/[id]` + `POST`）不改动
   - 在 `approvals-page-client.tsx` 中集成此 Drawer

2. **删除** `admin/app/(dashboard)/after-sales/page.tsx`
3. **删除** `admin/components/after-sales-page-client.tsx`
4. 移除 sidebar 中 after-sales 导航项（如有）
5. 检查并清理 layout 中的相关引用

**验收标准**：After-Sales tab 审批操作功能与原页面等同；`/after-sales` 路由返回 404；sidebar 无残留链接

---

### Phase 7：收尾与验收

**目标**：全功能集成测试，角标实时准确

1. 端到端测试 4 类审批流（每类至少走一次完整的 approve + reject 流程）
2. 验证每次审批操作后角标数字正确减少
3. 验证分页在各 tab 正确工作
4. 检查原有 `/merchants`、`/deals` 页面功能不受影响

**验收标准**：见第九节验收标准总览

---

## 八、关键技术决策

### 8.1 抽屉详情数据加载方式

**方案：点击后懒加载（参考现有 `/after-sales` 模式）**

- 列表页仅查询摘要字段，减少初始加载数据量
- 用户点击 "Review" 后，客户端发起 fetch 加载完整详情
- 商家注册：新建 API route `/api/approvals/merchant/[id]`（需读 merchant_documents，使用 service role）
- Deal：列表查询时已包含完整字段（dishes、usage_notes 等），点击后直接使用，无需独立 API
- 退款争议：列表查询已包含 refund_items，直接使用
- 售后申请：复用现有 `/api/platform-after-sales/[id]` API

### 8.2 All tab 的混合排序

将 4 类数据在 JS 层合并后按 `created_at ASC` 排序，初期采用此方案。若数据量增大导致性能问题，后续可考虑创建 Supabase VIEW 或 RPC 函数统一查询。

### 8.3 批量 Deal 审批的实现

`batchApproveDeal` 和 `batchRejectDeal` 在 Server Action 内部串行处理每个 dealId（循环调用已有单条逻辑），而非并行，以避免数据库连接数过高。返回 `{ success: string[], failed: string[] }` 供前端显示结果摘要。

### 8.4 退款争议退款执行路径

Phase 5 开发前必须先确认 `admin-refund` Edge Function 的调用接口：
- 若接口接受 `refund_request_id`，直接调用
- 若接口接受 `order_id` + `amount`，从 `refund_requests` 表读取后传入
- 若接口与本流程完全不兼容，在 Server Action 中参考 `create-refund` Edge Function 实现退款逻辑

### 8.5 Sidebar 角标缓存

Layout 层加入 Next.js `unstable_cache` 或路由段 `revalidate = 300`（5分钟），避免每次页面渲染都触发4个数据库查询。审批操作的 Server Action 中调用 `revalidatePath('/')` 强制使缓存失效，确保角标在操作后能及时更新。

---

## 九、不在本次开发范围内

- 审批通知推送（新申请进入时主动通知管理员）— 依赖通知系统
- 审批 SLA 自动升级机制 — 依赖 cron job 配置
- 商家端 Flutter App 中 `admin_refund_requests_page.dart` 的调整 — 保留现状
- Merchant / After-Sales / Refund Dispute 的批量操作 — 不在本次范围

---

## 十、验收标准总览

| 功能点 | 验收标准 |
|-------|---------|
| Sidebar 角标 | 正确显示4类待审批总数；任意审批操作后角标数字准确减少 |
| Tab 切换 | 5个 tab 数据正确；URL 参数与 tab 联动；各 tab 角标数字准确 |
| 超时高亮 | 超过 24h 未处理的行显示 ⚠️ 图标 + 浅红背景 |
| 分页 | 各 tab 分页正确；页码与 URL 联动 |
| 商家注册抽屉 | 展示基本信息 + 所有上传证件图片（懒加载）；approve/reject 操作成功 |
| Deal 审批抽屉 | 展示图片画廊、套餐、使用规则、驳回历史；approve/reject 成功 |
| Deal 批量审批 | 可多选；批量 approve/reject 成功；结果摘要正确显示 |
| 退款争议抽屉 | 展示 refund_items 商品明细 + 双方陈述；approve 触发实际退款；reject 状态正确 |
| 售后申请抽屉 | 展示双方证据图片 + timeline；approve/reject 操作成功 |
| 原页面审批按钮移除 | `/merchants/[id]` 和 `/deals/[id]` 无审批按钮；页面其余功能正常 |
| `/after-sales` 删除 | 路由返回 404；sidebar 无残留链接；approvals After-Sales tab 功能等同 |
| 原有列表页不受影响 | `/merchants`、`/deals` 列表页功能正常 |

---

## 十一、风险与注意事项

1. **RLS 权限**：`refund_requests` 表仅对 service_role 开放全权限，admin portal 需全程使用 `getServiceRoleClient()` 查询，与 `after_sales_requests` 处理方式保持一致

2. **退款执行兼容性**：Phase 5 开发前必须先阅读 `admin-refund` Edge Function 接口，避免重复实现退款逻辑

3. **删除 /after-sales 前的依赖检查**：删除前确认 sidebar、layout、以及任何内部链接中无 `/after-sales` 路由引用

4. **批量操作的邮件通知**：`batchApproveDeal` / `batchRejectDeal` 内部每条 deal 都会触发 M16/M17 邮件；需确认邮件发送不会因并发或循环频率触发限流，必要时在批量 action 中控制发送间隔或异步化

5. **移除审批按钮后的 UX**：`/merchants/[id]` 和 `/deals/[id]` 移除审批按钮后，需要在页面上添加明显提示（如 `"Approval is managed in the Approvals Center →"`），避免管理员在旧页面找不到操作入口而困惑
