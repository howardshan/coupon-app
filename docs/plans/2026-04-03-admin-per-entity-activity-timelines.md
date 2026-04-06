# 后台管理 — 分模块活动时间线（追溯）开发计划

**文档版本**: v1.2  
**创建日期**: 2026-04-03  
**影响范围**: Admin Portal (Next.js)  
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

### 5.2 Merchant（`/merchants/[id]`）


| 数据来源           | 可展示节点（示例）                                               |
| -------------- | ------------------------------------------------------- |
| `merchants`    | `submitted_at` / `created_at`、`updated_at`、`status` 当前值 |
| 若库中**无**状态变更流水 | 首版仅展示「注册 / 提交 / 最后更新」；**不虚构**中间节点                       |


**可选后续增强**：迁移或表 `merchant_status_events`（本计划不强制）。

### 5.3 退款争议（`refund_requests`，展示位置待定）


| 数据来源              | 可展示节点（示例）                                                                                                                  |
| ----------------- | -------------------------------------------------------------------------------------------------------------------------- |
| `refund_requests` | `created_at`、`merchant_decided_at`、`admin_decided_at`、状态文本；`user_reason` / `merchant_reason` / `admin_reason` 摘要进 subtitle |


**展示位置选项**（实现时二选一或并行）：  

- A）在 **Admin 订单详情** 关联区块（若易从订单跳转）；  
- B）在 **审批中心 Refund Dispute 抽屉** 底部增加折叠时间线（数据已在列表/详情接口中部分存在）。

### 5.4 After-sales（售后）

- 抽屉内已有 `timeline` JSONB 与 `TimelineBlock`（`after-sales-drawer.tsx`）。
- **本计划建议**：将展示**迁移/复用**通用 `AdminActivityTimelineCard` 的样式与结构，或把 `TimelineBlock` 改为内部调用通用组件，**统一视觉**。

### 5.5 统一审批中心 `/approvals`

- **可选**：在各抽屉底部增加「Mini timeline」（仅当前实体、数据来自抽屉已加载字段），减少跳转详情页的频率。  
- **优先级**：低于详情页完整时间线。

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

### Phase 2：Merchant 详情时间线

1. 新增 `admin/lib/merchant-admin-timeline.ts`，基于 `merchants` 现有字段组装事件。
2. 在 `merchants/[id]/page.tsx` 挂载时间线卡片。

**验收**：不编造无库表支撑的事件；footnote 标明局限。

### Phase 3：退款争议时间线

1. 确定展示载体（订单详情 / 抽屉 / 二者）。
2. 新增 `admin/lib/refund-dispute-admin-timeline.ts`（或并入现有 lib），从 `refund_requests` 行组装事件。
3. 接入 UI。

**验收**：`pending_admin` → 批准后时间线可见管理员处理节点（依赖现有字段是否含 `admin_decided_at` 等）。

### Phase 4：售后时间线与样式统一

1. 对比 `after-sales-drawer.tsx` 中 `TimelineBlock` 与通用组件差异。
2. 统一为同一套卡片样式；映射 `timeline` JSONB 字段到 `AdminActivityTimelineEntry`。

**验收**：售后抽屉时间线可读性与现网一致或提升；无回归。

### Phase 5（可选）：审批中心抽屉内迷你时间线

1. Deal / Merchant / Refund 抽屉在数据足够处嵌入简化时间线或「View full timeline → `/deals/[id]`」链接。

---

## 七、文件变更清单（预估）


| 路径                                                  | 说明                  |
| --------------------------------------------------- | ------------------- |
| `admin/lib/admin-activity-timeline-types.ts`        | 新建，通用条目类型           |
| `admin/components/admin-activity-timeline-card.tsx` | 新建，通用 UI            |
| `admin/components/order-detail-timeline-card.tsx`   | 改为复用通用组件（可选但推荐）     |
| `admin/lib/deal-admin-timeline.ts`                  | 新建                  |
| `admin/lib/merchant-admin-timeline.ts`              | 新建                  |
| `admin/lib/refund-dispute-admin-timeline.ts`        | 新建（或命名调整）           |
| `admin/app/(dashboard)/deals/[id]/page.tsx`         | 接入时间线               |
| `admin/app/(dashboard)/merchants/[id]/page.tsx`     | 接入时间线               |
| `admin/components/approvals/*.tsx`                  | 可选：抽屉内时间线           |
| `admin/components/approvals/after-sales-drawer.tsx` | 可选：Timeline 与通用组件对齐 |


---

## 八、风险与注意事项

1. **信息不完整**：仅靠 `updated_at` 无法区分「改标题」与「下架」，footnote 必须诚实说明。
2. **与邮件/日志对账**：时间线不等于法务级审计；重要场景保留 Email Logs、Stripe Dashboard 等外部源。
3. **性能**：Deal 驳回记录通常体量小；若未来单 Deal 驳回次数极大，注意 limit 与分页（当前可省略）。
4. **RLS**：Admin 页面已用 `createClient` / `getServiceRoleClient` 的模式需与各查询一致，避免详情页能看、时间线查不到。

---

## 九、验收标准总览


| 项           | 标准                               |
| ----------- | -------------------------------- |
| 通用组件        | 空数组不渲染；时间升序展示；英文标题/副标题；与订单卡片视觉协调 |
| Deal        | 详情页可见与驳回历史一致的时间线；无捏造字段           |
| Merchant    | 详情页可见基于现有字段的时间线；局限有 footnote     |
| Refund      | 选定载体上可见关键里程碑时间                   |
| After-sales | 样式统一或明确保留差异理由                    |
| 回归          | 订单详情原时间线行为不变（Phase 0 后）          |


---

## 十、后续演进（不在本批次必须完成）

- 若需 **全站审批导出**：增加 `admin_audit_events` 表或在 Edge Function 层双写；本计划的各 `build*Timeline` 可改为「读事件表 + 读实体表」混合。  
- 若某域强依赖 **操作者**：在对应 Server Action 成功路径更新列或写域内事件表，再并入时间线 builder。

---

## 变更记录


| 版本   | 日期         | 变更内容                                                                                                                 |
| ---- | ---------- | -------------------------------------------------------------------------------------------------------------------- |
| v1.0 | 2026-04-03 | 初稿：分模块时间线方案、阶段划分、文件清单与验收标准                                                                                           |
| v1.1 | 2026-04-03 | Phase 0 落地：`admin-activity-timeline-types`、`AdminActivityTimelineCard`、订单时间线改为薄封装复用                                  |
| v1.2 | 2026-04-03 | Phase 1：`deal-admin-timeline.ts`、`/deals/[id]` 接入 Activity timeline；`sortActivityTimelineAscending` 抽取至 types，订单排序复用 |


