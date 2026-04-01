# 后台管理系统 — 统一审批中心开发计划

**文档版本**: v1.0
**创建日期**: 2026-04-01
**目标路由**: `/approvals`
**影响范围**: Admin Portal (Next.js)，不涉及 Flutter 端或 Supabase 后端 schema 变更

---

## 一、背景与问题

### 现有审批流的分布现状

当前 admin portal 中，需要管理员介入的审批流共有 **4 种**，分散在不同页面：

| 审批类型 | 数据来源 | 触发状态 | 当前入口 | 存在问题 |
|---------|---------|---------|---------|---------|
| 商家注册申请 | `merchants` + `merchant_documents` | `status = 'pending'` | `/merchants` 列表 + `/merchants/[id]` | 与已批准/已拒绝商家混在同一列表，需手动识别 |
| Deal 上架申请 | `deals` | `deal_status = 'pending'` | `/deals` 列表（需手动筛选）+ `/deals/[id]` | 无专属待审队列，容易遗漏 |
| 核销后退款争议仲裁 | `refund_requests` | `status = 'pending_admin'` | **Next.js admin 后台完全缺失** | 商家拒绝后升级至管理员的争议，admin portal 无任何入口 |
| 售后仲裁申请 | `after_sales_requests` | `status = 'awaiting_platform'` | `/after-sales` 独立页 | 已有独立页，但信息展示在抽屉内已较完整，需整合 |

### 核心痛点

1. **分散跳转**：4 种审批类型分布在至少 3 个不同页面，高峰期来回切换效率低，容易漏单
2. **信息不完全**：
   - 商家注册：营业执照/证件图片集中在 `/merchants/[id]` 内，需跳转新页才能看
   - Deal 审批：完整配置（套餐、图片、使用规则）需跳转 `/deals/[id]` 查看
   - 退款争议：目前 admin portal 根本没有展示入口，是实际存在的功能空白
   - 售后申请：双方图片证据和 timeline 已在现有抽屉展示，相对完整
3. **缺乏全局视角**：没有统一的「待处理数量」汇总，管理员无法一眼判断当前积压情况

---

## 二、目标

1. 新建 `/approvals` 统一审批中心页面，聚合全部 4 类待审批申请
2. 侧边栏导航新增 Approvals 入口，显示实时待审批总数角标
3. 每类申请提供**右侧抽屉（Drawer）**形式的完整详情，无需跳转新页即可完成审批操作
4. 补全 `refund_requests` 在 admin portal 的管理员仲裁功能（当前完全缺失）
5. 将现有 `/after-sales` 页面的功能整合至新页，保持 `/after-sales` 路由可访问（做重定向或保留）

---

## 三、数据层分析

### 3.1 各类申请的数据库查询

**商家注册申请**
```sql
-- 列表查询
SELECT id, name, category, contact_name, contact_email, phone, created_at
FROM merchants
WHERE status = 'pending'
ORDER BY created_at ASC;   -- 先进先出

-- 抽屉详情（追加查询）
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
  d.validity_type, d.validity_days, d.max_per_person,
  m.name AS merchant_name, m.address AS merchant_address,
  di.image_url, di.is_primary
FROM deals d
JOIN merchants m ON m.id = d.merchant_id
LEFT JOIN deal_images di ON di.deal_id = d.id
WHERE d.deal_status = 'pending'
ORDER BY d.created_at ASC;
```

**核销后退款争议（管理员仲裁）**
```sql
SELECT
  rr.id, rr.refund_amount, rr.refund_items, rr.user_reason,
  rr.merchant_reason, rr.merchant_decided_at, rr.status,
  rr.created_at,
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
-- 沿用现有 view_merchant_after_sales_requests 视图，追加 awaiting_platform 过滤
-- 详情通过现有 /api/platform-after-sales/[id] API 获取
```

### 3.2 待审批数量汇总（用于角标）

```typescript
// 使用 Promise.all 并行查询，减少加载时间
const [merchantCount, dealCount, refundCount, afterSalesCount] = await Promise.all([
  serviceClient.from('merchants').select('id', { count: 'exact', head: true }).eq('status', 'pending'),
  serviceClient.from('deals').select('id', { count: 'exact', head: true }).eq('deal_status', 'pending'),
  serviceClient.from('refund_requests').select('id', { count: 'exact', head: true }).eq('status', 'pending_admin'),
  serviceClient.from('after_sales_requests').select('id', { count: 'exact', head: true }).eq('status', 'awaiting_platform'),
])
const totalPending = (merchantCount.count ?? 0) + (dealCount.count ?? 0)
                   + (refundCount.count ?? 0) + (afterSalesCount.count ?? 0)
```

### 3.3 新增 Server Actions（退款争议仲裁）

在 `admin/app/actions/approvals.ts`（新建）中添加：

```typescript
// 管理员批准退款争议（触发退款）
export async function approveRefundDispute(requestId: string, adminReason?: string)

// 管理员拒绝退款争议（最终拒绝）
export async function rejectRefundDispute(requestId: string, adminReason: string)
```

操作逻辑：
- `approveRefundDispute`：更新 `refund_requests.status = 'approved_admin'`，写入 `admin_decision / admin_reason / admin_decided_at / admin_decided_by`，然后触发实际退款（调用 `create-refund` Edge Function 或直接 Stripe API）
- `rejectRefundDispute`：更新 `status = 'rejected_admin'`，写入决策字段，发送通知邮件给用户

> **注意**：退款执行逻辑需与现有 `admin-refund` Edge Function 或 `create-refund` Edge Function 对齐，避免重复实现。优先调用现有 Edge Function。

---

## 四、UI 设计

### 4.1 页面整体布局

```
┌─────────────────────────────────────────────────────┐
│  Approvals                            [24 pending]   │
│  ─────────────────────────────────────────────────  │
│  [All (24)] [Merchants (3)] [Deals (8)] [Refund Disputes (5)] [After-Sales (8)]  │
│  ─────────────────────────────────────────────────  │
│  TYPE     SUMMARY         SUBMITTER   SUBMITTED   │
│  [Deal]   Summer BBQ...   TopWok       2h ago      [Review ▶] │
│  [Merch]  Green Garden... Jane Doe     4h ago      [Review ▶] │
│  [Refund] $28.00 dispute  U***r       1d ago      [Review ▶] │
│  ...                                               │
└─────────────────────────────────────────────────────┘
                                    ↕ 点击行 / Review 按钮
┌──────────────────────────────────────┐
│  ← 右侧抽屉滑出（max-w-2xl）          │
│  [Deal Review]  Summer BBQ Combo      │
│  ─────────────────────────────────   │
│  图片画廊 / 营业执照 / 退款明细 / 证据 │
│  完整配置信息展示区                   │
│  ─────────────────────────────────   │
│  [Approve]  [Reject with reason]      │
└──────────────────────────────────────┘
```

### 4.2 Tab 设计

- **All**：4 类混合，按提交时间升序（最老的排最前），便于优先处理积压
- **Merchant Applications**：仅 `merchants.status = 'pending'`
- **Deal Reviews**：仅 `deals.deal_status = 'pending'`
- **Refund Disputes**：仅 `refund_requests.status = 'pending_admin'`
- **After-Sales**：仅 `after_sales_requests.status = 'awaiting_platform'`

每个 Tab 标签右侧显示该类型数量角标（红色，0 时不显示）。

### 4.3 列表行设计

每行统一字段：

| 字段 | 说明 |
|-----|-----|
| 类型标签 | `Merchant` / `Deal` / `Refund Dispute` / `After-Sales`，不同颜色区分 |
| 摘要 | 商家名 / Deal 标题 / 退款金额+商家名 / 原因类型 |
| 申请人 | 商家联系人 / 商家名 / 用户（脱敏）|
| 提交时间 | 相对时间（"2h ago"）+ hover 显示绝对时间 |
| 操作 | "Review" 按钮，点击开启详情抽屉 |

高亮规则：超过 24 小时未处理的行背景浅红色提示。

### 4.4 各类型详情抽屉内容

#### 商家注册申请抽屉
```
[基本信息卡]
  商家名 / 公司名 / 类别 / EIN
  联系人 / 联系邮箱 / 电话
  地址 / 申请时间

[证件材料（重点区域）]
  每张证件：类型标签 + 图片（点击新标签页全屏查看）
  支持的证件类型：Business License, Health Permit, Storefront Photo, Owner ID 等

[审批操作区]
  [Approve] → 确认弹窗 → 调用 approveMerchant()
  [Reject]  → 输入拒绝原因 → 调用 rejectMerchant()
```

#### Deal 上架申请抽屉
```
[Deal 头部]
  图片画廊（主图 + deal_images）
  标题 / 原价 / 折扣价 / 折扣标签

[套餐与菜品]
  dishes[] 列表（名称/数量/小计）
  package_contents

[使用规则]
  usage_notes / usage_days / max_per_person
  validity_type + validity_days
  is_stackable

[商家信息]
  商家名 / 地址

[驳回历史]
  若有历史驳回记录，展示 rejection_history（复用现有 RejectionHistory 组件）

[审批操作区]
  [Approve & Publish] → 调用 setDealActive(id, true)
  [Reject]            → 输入原因 → 调用 rejectDeal(id, reason)
```

#### 退款争议仲裁抽屉（全新功能）
```
[争议概览]
  退款金额 / 订单 ID（可点击跳转 /orders/[id]）
  商家名 / 用户（脱敏）
  申请时间 / 商家拒绝时间

[争议商品明细]
  refund_items JSONB 展开：
  商品名 | 数量 | 单价 | 申请退款金额

[双方陈述]
  用户申请理由（user_reason）
  商家拒绝理由（merchant_reason）

[仲裁操作区]
  [Approve & Refund]  → 确认弹窗（显示退款金额）→ approveRefundDispute()
  [Final Rejection]   → 必填 admin_reason → rejectRefundDispute()
```

#### 售后申请抽屉
直接复用现有 `after-sales-page-client.tsx` 中的抽屉逻辑，迁移至新页面，不重写。

---

## 五、文件变更清单

### 5.1 新建文件

| 文件路径 | 类型 | 说明 |
|---------|-----|------|
| `admin/app/(dashboard)/approvals/page.tsx` | Server Component | 并行查询4张表，传递数据给 Client Component |
| `admin/components/approvals-page-client.tsx` | Client Component | 主页面：Tab 切换、列表渲染、抽屉状态管理 |
| `admin/components/approvals/merchant-drawer.tsx` | Client Component | 商家注册详情抽屉（复用 merchant-review-actions.tsx 中的操作按钮） |
| `admin/components/approvals/deal-drawer.tsx` | Client Component | Deal 详情抽屉（复用 deal-review-actions.tsx 中的操作按钮） |
| `admin/components/approvals/refund-dispute-drawer.tsx` | Client Component | 退款争议仲裁抽屉（全新，需新建） |
| `admin/app/actions/approvals.ts` | Server Actions | 退款争议的 approveRefundDispute / rejectRefundDispute |

### 5.2 修改文件

| 文件路径 | 改动内容 |
|---------|---------|
| `admin/components/sidebar.tsx` | 在 `adminNav` 数组中于 Orders 后面新增 `{ kind: 'link', href: '/approvals', label: 'Approvals', icon: '✅' }`；需要传入待审批总数以显示角标（需重构 sidebar 接受 `pendingCount` prop，或改用客户端独立 fetch） |
| `admin/app/(dashboard)/layout.tsx` | 若 sidebar 角标需要服务端数据，在 layout 层加入待审批总数查询并传给 Sidebar |

### 5.3 不修改 / 保留文件

| 文件路径 | 原因 |
|---------|------|
| `admin/app/(dashboard)/after-sales/page.tsx` | 保留原有路由，可在页面顶部加一条 banner 提示"请前往 Approvals 集中处理"，或直接做 `redirect('/approvals?tab=after-sales')` |
| `admin/app/(dashboard)/merchants/[id]/page.tsx` | 保留，抽屉中可提供"View Full Profile"链接跳转至此 |
| `admin/app/(dashboard)/deals/[id]/page.tsx` | 保留，抽屉中可提供"View Full Deal"链接跳转至此 |
| `admin/app/actions/admin.ts` | 已有的 `approveMerchant` / `rejectMerchant` / `setDealActive` / `rejectDeal` 不动，抽屉组件直接调用这些现有 actions |

---

## 六、实现步骤（分阶段）

### Phase 1：数据层 + Sidebar 角标（最小可见成果）

**目标**：侧边栏出现 "Approvals" 入口，角标显示实时待审批总数

1. 修改 `admin/app/(dashboard)/layout.tsx`：并行查询 4 张表的待审批数量，传给 Sidebar
2. 修改 `admin/components/sidebar.tsx`：接受 `pendingCount: number` prop，在 Approvals 链接旁显示角标
3. 新建 `admin/app/(dashboard)/approvals/page.tsx`：暂时只渲染标题和数量统计，验证数据通路

**验收标准**：sidebar 显示 "Approvals" + 角标数字，点击可进入页面

---

### Phase 2：统一列表（Tab 切换 + 行渲染）

**目标**：All / Merchant / Deal / Refund Dispute / After-Sales 5 个 tab 均可切换，列表正确展示

1. 完善 `admin/app/(dashboard)/approvals/page.tsx`：根据 `tab` search param 查询对应表，支持分页
2. 新建 `admin/components/approvals-page-client.tsx`：
   - Tab 组件（读取 `initialTab` prop，通过 URL search param 切换）
   - 统一列表渲染（类型标签、摘要、申请人、时间、超时高亮）
   - 行点击事件占位（抽屉后续实现）

**验收标准**：5 个 tab 数据正确，切换 URL 参数变化，超时行高亮显示

---

### Phase 3：商家注册 + Deal 审批抽屉

**目标**：点击 Merchant / Deal 类型的行，右侧滑出完整详情，可直接操作审批

1. 新建 `admin/components/approvals/merchant-drawer.tsx`：
   - 接受 `merchantId: string`，内部 fetch `/api/approvals/merchant/[id]` 或直接通过 Server Action 传递完整数据
   - 展示基本信息 + 证件图片列表
   - 复用 `merchant-review-actions.tsx` 中的 `<MerchantReviewActions>` 操作按钮
2. 新建 `admin/components/approvals/deal-drawer.tsx`：
   - 展示图片画廊、套餐、使用规则、商家信息
   - 复用 `deal-review-actions.tsx` 中的 `<DealReviewActions>` 操作按钮
   - 展示驳回历史（复用 `rejection-history.tsx`）

> **注意**：抽屉内部的详情数据（尤其是 merchant_documents 和 deal_images）需要在用户点击"Review"时通过 API route 或 Server Action 懒加载，避免在列表页一次性加载所有详情数据

**验收标准**：点击 Merchant/Deal 行后抽屉滑出，信息完整，approve/reject 操作成功后抽屉关闭、列表刷新

---

### Phase 4：退款争议仲裁抽屉（补全功能空白）

**目标**：首次在 admin portal 中实现退款争议的管理员仲裁功能

1. 新建 `admin/app/actions/approvals.ts`：
   - `approveRefundDispute(requestId, adminReason?)`：
     - 验证 admin 身份（`requireAdmin()`）
     - 更新 `refund_requests` 状态和决策字段
     - 调用退款执行逻辑（优先复用现有 `admin-refund` Edge Function）
     - `revalidatePath('/approvals')`
   - `rejectRefundDispute(requestId, adminReason)`：
     - 更新状态为 `rejected_admin`
     - 写入决策字段
     - 可选：发送邮件通知用户
2. 新建 `admin/components/approvals/refund-dispute-drawer.tsx`：
   - 展示争议概览、商品明细（解析 `refund_items` JSONB）、双方陈述
   - Approve 操作：确认弹窗（显示金额）→ 调用 action
   - Reject 操作：必填原因输入框（min 10字）→ 调用 action

**验收标准**：Refund Dispute 行点击后抽屉展示完整信息（包括 refund_items 商品列表），approve/reject 操作执行成功

---

### Phase 5：售后申请整合 + /after-sales 处理

**目标**：After-Sales tab 功能完整，现有 /after-sales 用户迁移至新页面

1. 将 `after-sales-page-client.tsx` 中的抽屉逻辑提取为独立的 `admin/components/approvals/after-sales-drawer.tsx`
2. 在新的 `approvals-page-client.tsx` 中复用此 Drawer 组件
3. 修改 `admin/app/(dashboard)/after-sales/page.tsx`：顶部加 banner 提示跳转，或直接 redirect

**验收标准**：After-Sales tab 功能与原 /after-sales 页面等同，审批操作正常

---

### Phase 6：侧边栏角标实时更新

**目标**：每次审批操作后，侧边栏角标数字实时更新

实现方案：利用 Next.js `revalidatePath('/approvals')` + `revalidatePath('/')` 机制，审批操作后 Server Actions 调用 revalidatePath，layout 重新渲染时角标自动更新。

**验收标准**：批准/拒绝操作后刷新页面，角标数字正确减少

---

## 七、关键技术决策

### 7.1 抽屉详情数据加载方式

**推荐方案：点击后 API route 懒加载**

- 列表页仅展示摘要字段（减少初始数据量）
- 用户点击某一行后，客户端 `fetch('/api/approvals/[type]/[id]')` 加载完整详情
- 参考现有 `after-sales-page-client.tsx` 中的 `fetch('/api/platform-after-sales/[id]')` 模式

对于商家注册详情，需新建 `admin/app/api/approvals/merchant/[id]/route.ts`，使用 service role client 读取 `merchant_documents`（已有 admin 读权限）。

对于 Deal 详情，可直接在列表查询时一并加载（字段数量可控），无需独立 API。

### 7.2 All tab 的混合排序

All tab 将 4 类数据合并后按 `created_at ASC` 排序，实现方式：

- 服务端：对各表分别查询后在 JS 层合并排序（数据量小时适用）
- 或：创建 Supabase VIEW 聚合 4 张表，通过统一 RPC 查询

初期使用 JS 层合并，若性能有问题再评估是否创建 VIEW。

### 7.3 退款争议审批后的退款执行

退款争议管理员批准后，需要实际发起退款到用户账户（Stripe 退款 或 Store Credit）。

执行路径：调用现有 `admin-refund` Edge Function（`/deal_joy/supabase/functions/admin-refund/index.ts`），该函数应已处理退款逻辑。若 Edge Function 的接口与 `refund_requests` 表不兼容，需在 Server Action 中直接实现退款逻辑（参考 `create-refund` Edge Function 的实现）。

**此处在开发前需先阅读 `admin-refund` Edge Function 的接口定义确认兼容性。**

---

## 八、不在本次开发范围内

- 批量审批（多选+一键操作）— 可作为后续迭代
- 审批通知推送（当新申请进入时通知管理员）— 依赖通知系统
- 审批 SLA 自动升级机制 — 依赖 cron job 配置
- 商家端 Flutter App 中 `admin_refund_requests_page.dart` 的调整 — 不在本次范围，保留现状

---

## 九、验收标准总览

| 功能点 | 验收标准 |
|-------|---------|
| Sidebar 角标 | 显示全部 4 类待审批总数；审批后数字正确减少 |
| Tab 切换 | 5 个 tab 均有数据；URL 参数与 tab 联动；角标数字准确 |
| 超时高亮 | 超过 24h 未处理的申请行背景高亮显示 |
| 商家注册抽屉 | 展示基本信息 + 所有上传证件图片；approve/reject 操作成功 |
| Deal 审批抽屉 | 展示图片画廊、套餐、使用规则；驳回历史可见；approve/reject 操作成功 |
| 退款争议抽屉 | 展示 refund_items 商品明细、双方陈述；admin approve/reject 操作成功并执行退款 |
| 售后申请抽屉 | 与原 /after-sales 页面功能等同；双方证据图片可查看 |
| 原有页面不破坏 | `/merchants`、`/deals`、`/after-sales` 原有功能正常 |

---

## 十、风险与注意事项

1. **RLS 权限**：`refund_requests` 表目前只对 service_role 开放全权限（`refund_requests_service_all`），admin portal 需使用 `getServiceRoleClient()` 查询，与 `after_sales_requests` 处理方式一致

2. **退款执行对齐**：Phase 4 开发前必须先阅读 `admin-refund` Edge Function 接口，确认与 `refund_requests` 表的兼容性，避免重复实现退款逻辑

3. **Sidebar 角标查询性能**：Layout 层每次渲染都会发起 4 个数据库查询，建议加 5 分钟缓存（`unstable_cache` 或 `revalidate: 300`），避免对数据库造成压力

4. **`/after-sales` 路由迁移**：若直接 redirect，需确认是否有外部链接或书签指向该路由；建议保留页面但加 banner 引导，而非强制 redirect

5. **抽屉内操作后的刷新**：Server Actions 中的 `revalidatePath` 会触发页面数据重新获取，Client Component 需正确处理列表数据更新（参考现有 `after-sales-page-client.tsx` 的 `router.refresh()` 模式）
