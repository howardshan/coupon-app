# Plan：Deal 评价体验完善（提交后立即展示 + 扩展能力）

## 背景与问题

- 用户在 **Write Review** 提交成功后仅 `pop` 返回详情页。
- 详情页评价列表来自 `dealReviewsProvider(dealId)`、`deal.reviewCount` 来自 `dealDetailProvider(dealId)`，均为 **Riverpod FutureProvider 缓存**，不会自动重拉。
- 结果：**数据库已写入且触发器已更新 `deals.review_count`，但界面仍显示旧数据**。

## 目标

1. **P0**：提交评价后详情页 **立即** 显示新评价与更新后的评论数。
2. **P1**：减少误操作与重复提交、基础体验加固。
3. **P2**：补齐「查看全部评价」等已 TODO 能力（可选分阶段上线）。

---

## 阶段一：P0 — 提交后刷新缓存（必做）

| 文件 | 变更 |
|------|------|
| `deal_joy/lib/features/reviews/presentation/screens/write_review_screen.dart` | `insert` 成功且 `mounted` 后，在 `context.pop()` **之前** 调用：<br>`ref.invalidate(dealReviewsProvider(widget.dealId));`<br>`ref.invalidate(dealDetailProvider(widget.dealId));` |
| 同上 | `import '../../../deals/domain/providers/deals_provider.dart';`（路径按实际模块调整） |

**验证**：详情页 → Write Review → 提交 → 返回后列表出现新条、标题区 `(N reviews)` 与星级区域数字与 DB 一致。

**注意**：`featuredDealsProvider` / 首页列表里的 `reviewCount` 仍为旧缓存；若需首页也即时更新，可额外 `ref.invalidate(featuredDealsProvider)` 及对应列表 Provider（见阶段三可选）。

---

## 阶段二：P1 — 体验与数据一致性

### 2.1 重复评价（建议）

- **现状**：RLS 仅校验「本人插入」，**同一用户对同一 deal 可多次插入**（若无 DB 约束）。
- **方案 A（推荐）**：Migration 增加 `UNIQUE (user_id, deal_id)`，插入冲突时前端提示「You have already reviewed this deal」。
- **方案 B**：仅前端：进入写评价页前先查是否已有该 deal 的评价，有则跳转详情或只读展示。

### 2.2 写评价入口权限（产品确认）

- 若业务要求 **仅购买/核销用户可评**：在打开 `/review/:dealId` 前校验 `orders`/`coupons`（或隐藏按钮）；否则保持现状（任何人可写）。

### 2.3 输入校验

- 评论 `trim()` 后若为空：允许仅星级或要求至少 N 字（与产品一致）。
- 限制 `comment` 最大长度（如 2000），避免异常 payload。

### 2.4 错误提示

- `PostgrestException` 区分：唯一约束冲突、网络错误，SnackBar 文案区分。

---

## 阶段三：P2 — 「查看全部评价」与列表体验

| 项 | 说明 |
|----|------|
| 详情页 TODO | `deal_detail_screen.dart` 中「See All N Reviews」目前无路由。 |
| 新页面 | 例如 `DealReviewsListScreen(dealId)`：全屏列表，`fetchReviewsByDeal` 分页或提高 `limit`。 |
| Provider | 可复用 `dealReviewsProvider` 或新建 `AsyncNotifier` 支持分页加载更多。 |
| 路由 | `app_router.dart` 增加 `/deals/:dealId/reviews` 或 `/review-list/:dealId`，与现有 `/review/:dealId`（写评价）区分命名。 |

**验证**：评价 >5 条时「See All」进入列表页，下拉/分页可浏览。

---

## 阶段四：可选 — 全站评价数一致性

- 用户从首页进详情再写评价返回首页：`featuredDealsProvider`、`dealsListProvider` 仍可能显示旧 `review_count`。
- **可选**：在 `write_review_screen` 成功分支中增加：<br>`ref.invalidate(featuredDealsProvider);`<br>并对当前城市/分页下的 `dealsListProvider` 做 `invalidate`（family 需传 page，可只 invalidate 常用页或接受首页略滞后）。

---

## 执行顺序建议

1. **阶段一**（小改动、高收益）→ 自测通过即可合并。  
2. **阶段二** 按产品优先级选做（建议至少 2.1 或明确「允许多评」）。  
3. **阶段三** 独立 PR，避免与 P0 混在一起。  
4. **阶段四** 按需。

---

## 涉及模块与禁区

- 主要改动：**用户端** `deal_joy/lib/features/reviews/`、`deals/`（provider 失效、详情页、可选新页）。
- **不动**：`deals_repository` 的 `sort_order` / 首页 featured 逻辑（COMPLETED.md 保护项）— 仅允许增加 `invalidate` 调用或只读扩展，不改编排规则。
- **测试**：集成/手动：写评价 → 详情立即更新；若有唯一约束，第二次提交应友好报错。

---

## 验收清单

- [ ] 提交评价后返回详情，**新评价出现在列表顶部**（与 `order created_at DESC` 一致）。
- [ ] 详情页 **Reviews (N)** 与 deal 头图区评价数 **+1**（与 DB `review_count` 一致）。
- [ ] 无登录/未提交时不应误 invalidate 导致异常。
- [ ] （若做 P2）See All 可打开完整列表。
