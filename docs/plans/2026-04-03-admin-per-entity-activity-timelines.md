# 后台管理 — 分模块活动时间线（追溯）开发计划

**文档版本**: v1.8  
**创建日期**: 2026-04-03  
**影响范围**: Admin Portal (Next.js) + Supabase（`merchant_activity_events` 迁移与 Edge Functions）  
**相关文档**: [统一审批中心](./2026-04-01-unified-approvals-page.md)

---

## 一、背景与动机

### 1.1 现状

- 统一审批中心 `/approvals` 聚焦**待处理队列**，处理完成后条目离开列表，**不保留「谁在何时做了何操作」的集中视图**。
- 各业务表**字段不齐**：部分有明确时间戳与操作者（如 `deal_rejections.rejected_by`），部分仅有当前状态与零散时间字段。
- 订单详情已具备 **Activity timeline**：由 `admin/lib/order-admin-timeline.ts` 从现有字段**推导**事件，经 `OrderDetailTimelineCard` 展示（**无独立审计表**）。

### 1.2 目标

在**不强制新建全平台统一审计表**的前提下，为各审批/运营相关实体提供**详情页内可追溯时间线**，便于：

- 客诉与内部核对（申请时间、处理时间、结果摘要）；
- 与订单时间线一致的**交互与视觉习惯**。

### 1.3 非目标（本阶段明确不做）

- **单一「审批历史」全站列表页**（跨 Merchant / Deal / Refund / After-sales 统一筛选、导出）；
- **强制**所有操作写入新表；若后续合规要求升级，可再评估「事件表 / 数仓」双写，与本计划不冲突。

---

## 二、方案概述


| 维度  | 做法                                                            |
| --- | ------------------------------------------------------------- |
| 数据  | **各域自用已有表与字段**，在 Server 或 `lib/*-timeline.ts` 内组装为统一结构的「事件数组」 |
| UI  | **抽取通用时间线展示组件**（样式对齐 `OrderDetailTimelineCard`），各页传入已排序事件     |
| 扩展  | 某域若仅有「当前状态」、缺历史节点，可**后续**为该域增加小范围事件表或补字段，仍通过同一 UI 渲染          |


**缺点（已接受）**：每个模块需单独实现「数据组装逻辑」与联调；**优点**：改动面可控、不阻塞业务表演进。

---

## 三、参考实现（订单）


| 文件                                                | 职责                                                                                              |
| ------------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| `admin/lib/order-admin-timeline.ts`               | `OrderTimelineEntry` 类型；`buildOrderTimelineV2` / `buildOrderTimelineV3`；`sortTimelineAscending` |
| `admin/components/order-detail-timeline-card.tsx` | 订单详情「Activity timeline」卡片 UI                                                                    |
| `admin/app/(dashboard)/orders/[id]/page.tsx`      | 拉取订单与 items 后调用 builder，传入 `OrderDetailTimelineCard`                                            |


**约定**：时间线文案 **UI 英文**；代码注释 **中文**（与仓库规范一致）。

---

## 四、通用组件设计（建议）

### 4.1 泛型事件模型

与订单对齐，建议通用类型（名称可调整）：

```ts
// 建议位置：admin/lib/admin-activity-timeline-types.ts
export type AdminActivityTimelineEntry = {
  at: string       // ISO 时间，用于排序与 <time dateTime>
  title: string    // 主标题（英文）
  subtitle?: string // 可选：原因、操作者邮箱、关联 ID 等
}
```

可选扩展（按需）：`kind?: 'info' | 'success' | 'warning' | 'danger'` 用于节点颜色，**首版可与订单一致单色圆点**。

### 4.2 通用展示组件

- **建议路径**: `admin/components/admin-activity-timeline-card.tsx`
- **Props**: `title: string`（如 "Activity timeline" / "Review timeline"）、`footnote?: string`、`events: AdminActivityTimelineEntry[]`
- **行为**: `events.length === 0` 时返回 `null`；列表按调用方保证**时间升序**（与订单一致）。

### 4.3 与订单的关系

- **Phase 0** 可将 `OrderDetailTimelineCard` **重构为**使用通用组件 + 薄封装（或保留订单专用 footnote），避免两套 DOM 长期分叉。

---

## 五、各域数据源与事件范围（建议）

### 5.1 Deal（`/deals/[id]`）


| 数据来源              | 可展示节点（示例）                                                                                  |
| ----------------- | ------------------------------------------------------------------------------------------ |
| `deals`           | `created_at`、`published_at`、`updated_at`（需定义文案：创建 / 上架 / 最后更新）                             |
| `deal_rejections` | 每条驳回：`created_at`、`reason`、`users.email` 或 `rejected_by`（与现有 `RejectionHistory` 信息对齐，避免矛盾） |


**注意**：`setDealActive` / `rejectDeal` 若未单独落事件表，**下架时间**可能仅体现在 `updated_at` 或 `deal_status` 变更推断，需在文案 footnote 中说明「部分步骤由时间戳推导」。

### 5.2 Merchant（`/merchants/[id]`）— **已实现（v1.4+）**


| 数据来源 | 可展示节点（示例） |
| -------- | ------------------ |
| **`merchant_activity_events`（审计表）** | 迁移上线后新产生的：**申请提交**、**管理员通过/拒绝/撤销认证**、**门店对消费者在线/离线**（商家 Dashboard 或管理员按钮）、**商家闭店**等；含 `actor_type`、`actor_user_id`、驳回 `detail`。 |
| **`merchants`（行内字段）** | **兜底**：当该商户**尚无**审计行时，`buildMerchantTimeline` 仅用 `created_at` / `submitted_at` / `updated_at` / 当前 `status` 推导「建档 / 提交 / 最后更新」，**不虚构**中间节点。 |
| **详情页查询** | `merchant_activity_events` 按 `merchant_id` + `created_at` 升序；批量解析 `users.email` 作为副标题中的操作者标识。 |


**事件类型（`event_type`）**：`application_submitted`、`admin_approved`、`admin_rejected`、`admin_revoked_to_pending`、`store_online_merchant`、`store_offline_merchant`、`store_online_admin`、`store_offline_admin`、`store_closed_merchant`。

**写入路径摘要**：

| 路径 | 写入事件 |
| ---- | -------- |
| Edge `merchant-register` | `application_submitted`（对齐 `submitted_at`） |
| Edge `merchant-dashboard` PATCH `is_online` | `store_online_merchant` / `store_offline_merchant` |
| Edge `merchant-store` POST `close` | `store_closed_merchant` |
| Admin `approveMerchant` / `rejectMerchant` / `revokeMerchantApproval` | `admin_*` |
| Admin `adminSetMerchantStoreOnline` | `store_online_admin` / `store_offline_admin` |

**部署注意**：迁移需推生产；上述 Edge Functions 需从 **`deal_joy/`** 目录部署。审计数据**自迁移与部署后起算**，历史行为不自动回填。

**原「可选后续」**：域内事件表已落地为 `merchant_activity_events`，不再依赖单独的 `merchant_status_events` 命名。

### 5.3 退款争议（`refund_requests`）— **已实现（v1.6）**


| 数据来源 | 可展示节点（示例） |
| -------- | ------------------ |
| `refund_requests` | 提交（`created_at` + 用户理由摘要）、商家决定（`merchant_decided_at` + `merchant_decision` / `merchant_reason`）、管理员决定（`admin_decided_at` + `admin_decision` / `admin_reason`）、完成（`completed_at`）、用户撤回（`status = cancelled` + `updated_at`）。 |

**展示载体（已定稿）**：**A + B 并行**  

- **Admin 订单详情** `/orders/[id]`：侧栏在订单 `OrderDetailTimelineCard` 下方增加 **Refund dispute timeline**（`service_role` 按 `order_id` 拉取全部争议行，多条则合并排序）。  
- **审批中心 Refund Dispute 抽屉**：在陈述区上方挂载同一套 `AdminActivityTimelineCard`（单条争议）；`RefundDisputeItem` 已扩展字段供时间线与 Overview 一致。  

**实现文件**：`admin/lib/refund-dispute-admin-timeline.ts`（`buildRefundDisputeTimeline` / `buildMergedOrderRefundDisputeTimelines`）。  

**刷新**：`approveRefundDispute` / `rejectRefundDispute` 成功后 `revalidatePath(/orders/[orderId])` 以便订单侧栏时间线更新。

### 5.4 After-sales（售后）— **已实现（v1.7）**

- **数据来源**：售后详情 API 返回的 `request.timeline`（JSONB 数组：`status`、`actor`、`note`、`attachments`、`at`）。
- **展示**：`after-sales-drawer.tsx` 已移除内联 `TimelineBlock`，改用 `AdminActivityTimelineCard` + `admin/lib/after-sales-admin-timeline.ts` 的 `buildAfterSalesTimelineEntries`（升序、标题为状态文案、副标题含 Actor 与 note）。
- **附件**：`AdminActivityTimelineEntry` 增加可选 `attachments`，通用卡片在每条目下渲染与旧版一致的「File N」外链，避免能力回退。

### 5.5 统一审批中心 `/approvals` — **Phase 5 已落地（v1.8）**

- **Deal 抽屉**：`buildDealTimeline` + `AdminActivityTimelineCard`（Activity preview）；列表/All Tab 的 `DealItem` 补充 `updated_at` 等字段；底部链接文案改为打开详情完整时间线。  
- **Merchant 抽屉**：`buildMerchantTimeline(…, [])` 行内推导预览；`/api/approvals/merchant/[id]` 增加 `updated_at`；底部链接同 Deal。  
- **Refund 抽屉**：已有完整争议时间线；补充订单链接旁说明（订单页含 activity 与同单其他争议）。  
- **After-Sales 抽屉**：详情返回 `order_id` 后在 Overview 显示跳转订单链接。

---

## 六、实现阶段（建议）

### Phase 0：基础抽取

1. 新增 `admin/lib/admin-activity-timeline-types.ts`（或等价）定义 `AdminActivityTimelineEntry`。
2. 新增 `admin/components/admin-activity-timeline-card.tsx`，UI 参考 `order-detail-timeline-card.tsx`。
3. （推荐）重构 `OrderDetailTimelineCard` 使用通用组件，回归测试订单详情页时间线。

**验收**：订单页时间线外观与行为与重构前一致；通用组件可在 Story 页或临时测试页用假数据验证（若无 Story，以订单页为准）。

### Phase 1：Deal 详情时间线

1. 新增 `admin/lib/deal-admin-timeline.ts`：`buildDealTimeline(deal, rejectionRecords, ...)` → `AdminActivityTimelineEntry[]`。
2. 在 `admin/app/(dashboard)/deals/[id]/page.tsx` 查询/合并 `deal_rejections`（若与 RejectionHistory 重复查询，可考虑合并为一次取数传两处）。
3. 挂载 `AdminActivityTimelineCard`，footnote 说明推导性质。

**验收**：含驳回记录的 Deal 时间线包含驳回节点；无驳回时至少有创建/发布等可用节点（以实际字段为准）。

### Phase 2：Merchant 详情时间线 — **已完成**

**2a（初版，v1.3）**

1. 新增 `admin/lib/merchant-admin-timeline.ts`，基于 `merchants` 行内字段组装兜底事件。
2. 在 `merchants/[id]/page.tsx` 挂载 `AdminActivityTimelineCard`，footnote 说明推导局限。

**2b（完整审计，v1.4）**

1. 新增迁移 `deal_joy/supabase/migrations/20260402140000_merchant_activity_events.sql` 与表 `merchant_activity_events`（RLS：admin 全读、门店主读本店）。
2. Deno 共享 `deal_joy/supabase/functions/_shared/merchant_activity_log.ts`；在 `merchant-register`、`merchant-dashboard`、`merchant-store` 成功路径追加写入。
3. Admin：`admin/lib/merchant-activity-events.ts`（`logMerchantActivityServer`）；`admin.ts` 中 `approveMerchant` / `rejectMerchant` / `revokeMerchantApproval` 写审计；新增 `adminSetMerchantStoreOnline`；`requireAdmin` 返回 `adminUserId` 供操作者关联。
4. `merchant-admin-timeline.ts`：`buildMerchantTimeline(merchant, activityEvents[])` — 有审计行则映射为英文节点并排序，可补「建档」锚点与「Record last updated」；无行则回退 2a。
5. `merchants/[id]/page.tsx`：查询事件表 + 操作者邮箱；展示 `is_online` 与 `MerchantAdminVisibilityActions`（Take offline / Put online）；footnote 区分有数据 / 无数据 / 查询失败。

**验收**：迁移后新操作在时间线可见（含多次驳回/通过、上下线、闭店）；无审计行时仍为行内推导且不捏造节点；footnote 诚实说明历史不完整范围。

### Phase 3：退款争议时间线 — **已完成（v1.6）**

1. **载体**：订单详情侧栏 + Refund Dispute 抽屉（二者）。
2. 新增 `admin/lib/refund-dispute-admin-timeline.ts`：`buildRefundDisputeTimeline`（单条）、`buildMergedOrderRefundDisputeTimelines`（同单多争议合并升序）。
3. `orders/[id]/page.tsx`：`getServiceRoleClient` 查询 `refund_requests`，挂载 `AdminActivityTimelineCard`。
4. `refund-dispute-drawer.tsx`：挂载同一时间线组件；`approvals/page.tsx` 扩展 `RefundDisputeItem` 与 `fetchRefundDisputes` / 统一 Tab 批量查询字段。
5. `approvals.ts`：仲裁成功后按 `requestId` 解析 `order_id` 并 `revalidatePath` 订单详情。

**验收**：有待审或已结争议的单据在订单页与抽屉均可见里程碑；管理员批准后订单页侧栏可刷新出 Admin 节点（依赖 `admin_decided_at` 等字段由 Edge 写入）。

### Phase 4：售后时间线与样式统一 — **已完成（v1.7）**

1. 新增 `admin/lib/after-sales-admin-timeline.ts`：`buildAfterSalesTimelineEntries(timeline)`。
2. `admin/lib/admin-activity-timeline-types.ts`：`AdminActivityTimelineEntry` 可选 `attachments`。
3. `admin/components/admin-activity-timeline-card.tsx`：`subtitle` 支持多行（`whitespace-pre-line`）；有条目附件时渲染链接行。
4. `after-sales-drawer.tsx`：用 `AdminActivityTimelineCard` 替换 `TimelineBlock`，footnote 说明记录来源与历史可能不完整。

**验收**：视觉与订单/退款等时间线一致；Actor、note、附件链接保留；无事件时不占版面。

### Phase 5（可选）：审批中心抽屉内迷你时间线 — **已完成（v1.8）**

1. Deal / Merchant：`AdminActivityTimelineCard` + 既有 builder；数据来自列表字段 + Deal 驳回 API / Merchant 详情 API。  
2. Refund / After-Sales：跳转与文案增强（订单页对照）；不重复缩成「迷你」时间线。

**验收**：审批人在抽屉内可预览与详情页一致推导的 Deal/Merchant 时间线；可一键打开详情或订单页。

---

## 七、文件变更清单（至 Phase 5 审批抽屉预览）


| 路径                                                  | 说明                  |
| --------------------------------------------------- | ------------------- |
| `admin/lib/admin-activity-timeline-types.ts`        | 通用条目类型；Phase 4 起含可选 `attachments` |
| `admin/components/admin-activity-timeline-card.tsx` | 通用 UI；Phase 4 多行 subtitle + 附件链接 |
| `admin/lib/after-sales-admin-timeline.ts`           | 新建；JSONB timeline → 通用条目 |
| `admin/components/order-detail-timeline-card.tsx`   | 改为复用通用组件（可选但推荐）     |
| `admin/lib/deal-admin-timeline.ts`                  | 新建                  |
| `admin/lib/merchant-admin-timeline.ts`              | 新建；含审计行合并与行内兜底        |
| `admin/lib/merchant-activity-events.ts`             | 新建；Server 侧写 `merchant_activity_events` |
| `admin/components/merchant-admin-visibility-actions.tsx` | 新建；管理员强制上下线 UI    |
| `admin/app/actions/admin.ts`                        | 审批/上下线审计写入；`requireAdmin` 返回 `adminUserId`；`rejectDeal.rejected_by` 等 |
| `deal_joy/supabase/migrations/20260402140000_merchant_activity_events.sql` | 审计表 + RLS |
| `deal_joy/supabase/functions/_shared/merchant_activity_log.ts` | 新建；Edge 侧写审计 |
| `deal_joy/supabase/functions/merchant-register/index.ts` | 申请提交事件 |
| `deal_joy/supabase/functions/merchant-dashboard/index.ts` | `is_online` 变更事件 |
| `deal_joy/supabase/functions/merchant-store/index.ts` | 闭店事件 |
| `admin/lib/refund-dispute-admin-timeline.ts`        | 新建；退款争议时间线 builder   |
| `admin/app/actions/approvals.ts`                    | 仲裁后 revalidate 订单详情（与 Phase 3 联动） |
| `admin/components/approvals/refund-dispute-drawer.tsx` | 挂载 Refund dispute timeline |
| `admin/app/(dashboard)/orders/[id]/page.tsx`        | Refund dispute timeline（侧栏） |
| `admin/app/(dashboard)/approvals/page.tsx`          | Refund 列表字段扩展（时间线 / Overview） |
| `admin/app/(dashboard)/deals/[id]/page.tsx`         | 接入时间线               |
| `admin/app/(dashboard)/merchants/[id]/page.tsx`     | 接入时间线 + 事件查询 + 可见性侧栏   |
| `admin/components/approvals/deal-drawer.tsx`        | Phase 5：Activity preview + 详情链接文案 |
| `admin/components/approvals/merchant-drawer.tsx`    | Phase 5：Activity preview + 详情链接文案 |
| `admin/components/approvals/refund-dispute-drawer.tsx` | Phase 5：订单链接说明 |
| `admin/components/approvals/after-sales-drawer.tsx` | Phase 4 时间线 + Phase 5：`order_id` 跳转订单 |
| `admin/app/(dashboard)/approvals/page.tsx`          | Phase 5：`DealItem` 扩展字段与查询 |
| `admin/app/api/approvals/merchant/[id]/route.ts`    | Phase 5：`updated_at` |


---

## 八、风险与注意事项

1. **信息不完整**：仅靠 `updated_at` 无法区分「改标题」与「下架」，footnote 必须诚实说明。
2. **与邮件/日志对账**：时间线不等于法务级审计；重要场景保留 Email Logs、Stripe Dashboard 等外部源。
3. **性能**：Deal 驳回记录通常体量小；若未来单 Deal 驳回次数极大，注意 limit 与分页（当前可省略）。
4. **RLS**：Admin 页面已用 `createClient` / `getServiceRoleClient` 的模式需与各查询一致，避免详情页能看、时间线查不到。
5. **Merchant 审计表**：`merchant_activity_events` 仅 service role / 受控服务端写入；部署 Edge 与迁移顺序错误会导致写入失败（函数内仅打日志，主流程不中断）。
6. **CLI 部署路径**：`supabase functions deploy` 须在含 `supabase/functions/` 的 **`deal_joy/`** 目录执行，避免仓库根目录报 entrypoint 不存在。

---

## 九、验收标准总览


| 项           | 标准                               |
| ----------- | -------------------------------- |
| 通用组件        | 空数组不渲染；时间升序展示；英文标题/副标题；与订单卡片视觉协调 |
| Deal        | 详情页可见与驳回历史一致的时间线；无捏造字段           |
| Merchant    | 详情页可见审计事件 + 行内兜底；footnote 说明历史起算时间与局限；管理员可强制上下线并记审计 |
| Refund      | 订单详情侧栏 + Refund 抽屉可见 `refund_requests` 里程碑；仲裁后订单页可刷新 |
| After-sales | 抽屉内 `timeline` 经 builder 展示；与通用时间线卡片一致；附件可点   |
| Approvals 抽屉 | Deal/Merchant 预览与详情 builder 一致；可打开详情/订单对照完整时间线   |
| 回归          | 订单详情原时间线行为不变（Phase 0 后）          |


---

## 十、后续演进（不在本批次必须完成）

- 若需 **全站审批导出**：增加 `admin_audit_events` 表或在 Edge Function 层双写；本计划的各 `build*Timeline` 可改为「读事件表 + 读实体表」混合。  
- 若某域强依赖 **操作者**：在对应 Server Action 成功路径更新列或写域内事件表，再并入时间线 builder。  
- **Merchant 域**已采用 `merchant_activity_events`，可作为其他域（如统一 `admin_audit_events`）的参考模式。

---

## 变更记录


| 版本   | 日期         | 变更内容                                                                                                                 |
| ---- | ---------- | -------------------------------------------------------------------------------------------------------------------- |
| v1.0 | 2026-04-03 | 初稿：分模块时间线方案、阶段划分、文件清单与验收标准                                                                                           |
| v1.1 | 2026-04-03 | Phase 0 落地：`admin-activity-timeline-types`、`AdminActivityTimelineCard`、订单时间线改为薄封装复用                                  |
| v1.2 | 2026-04-03 | Phase 1：`deal-admin-timeline.ts`、`/deals/[id]` 接入 Activity timeline；`sortActivityTimelineAscending` 抽取至 types，订单排序复用 |
| v1.3 | 2026-04-06 | Phase 2：`merchant-admin-timeline.ts`、`/merchants/[id]` 接入 Activity timeline；仅 merchants 行内时间戳推导，footnote 说明无独立审批时刻   |
| v1.4 | 2026-04-06 | Merchant 审计表 `merchant_activity_events` + 全链路写入；时间线合并事件；管理员强制上下线 `adminSetMerchantStoreOnline`                       |
| v1.5 | 2026-04-06 | 计划书同步：§5.2 / Phase 2 / 文件清单 / 风险 / 验收总览与实现对齐；补充事件类型、写入路径、部署与 `deal_joy` 目录约定   |
| v1.6 | 2026-04-06 | Phase 3 落地：§5.3、`refund-dispute-admin-timeline.ts`、订单侧栏 + Refund 抽屉、`RefundDisputeItem` 字段扩展、仲裁后 revalidate 订单详情   |
| v1.7 | 2026-03-30 | Phase 4：`after-sales-admin-timeline.ts`、售后抽屉统一 `AdminActivityTimelineCard`；条目类型支持 `attachments`、卡片多行 subtitle   |
| v1.8 | 2026-03-30 | Phase 5：Deal/Merchant 审批抽屉 Activity preview；After-Sales `order_id` 链订单；Refund 订单说明；`DealItem` 与 merchant API 字段扩展   |


