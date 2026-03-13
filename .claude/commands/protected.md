# 保护规则检查

**在开始任何任务之前，必须执行以下步骤：**

## 第 1 步：读取已完成模块清单

读取项目根目录的 `COMPLETED.md`，了解哪些模块已测试通过、禁止随意改动。

## 第 2 步：判断本次任务是否涉及受保护文件

对比任务目标与 `COMPLETED.md` 中的受保护文件列表：

- **不涉及受保护文件** → 直接执行任务
- **涉及受保护文件** → 必须先向用户说明：
  1. 哪个受保护文件/模块需要被改动
  2. 为什么这个改动是必要的
  3. 改动的最小范围是什么
  4. **等待用户明确确认后，才能修改**

## 禁止修改的文件（除非用户明确要求）

以下文件/目录**绝对不能**在未经确认的情况下修改：

### 首页券排序系统
- `deal_joy/lib/features/deals/` 中的 `featuredDealsProvider`、`fetchFeaturedDeals()` 方法
- 首页水平滚动券 UI 相关 widget
- DB 字段 `deals.sort_order`

### Admin Deal Sort Order
- `admin/components/deal-sort-order.tsx`
- `admin/app/actions/admin.ts` — `updateDealSortOrder`
- `admin/app/(dashboard)/deals/page.tsx` — sort_order 列

### Deal Category 分类系统
- `dealjoy_merchant/lib/features/deals/models/deal_category.dart`
- `dealjoy_merchant/lib/features/deals/services/deals_service.dart` — fetchDealCategories, createDealCategory, updateDealCategory, deleteDealCategory
- `dealjoy_merchant/lib/features/deals/providers/deals_provider.dart` — dealCategoriesProvider, dealsServiceProvider
- `dealjoy_merchant/lib/features/deals/pages/deal_create_page.dart` — `_buildDealCategoryDropdown()`
- `dealjoy_merchant/lib/features/deals/pages/deal_edit_page.dart` — `_buildDealCategoryDropdown()`
- `dealjoy_merchant/lib/features/deals/pages/deals_list_page.dart` — `_CategoryManagerSheet`
- `dealjoy_merchant/lib/features/deals/models/merchant_deal.dart` — `dealCategoryId` 字段
- `deal_joy/supabase/functions/merchant-deals/index.ts` — deal_category_id, deal_type, badge_text 相关逻辑
- DB 表 `deal_categories`

### 已完成并测试通过的模块
**详见 `COMPLETED.md`** — 每次任务开始前必须读取该文件，其中列出的模块文件同样受保护。

## 规则摘要

| 情况 | 行动 |
|------|------|
| 任务不涉及受保护文件 | 直接执行 |
| 任务需要改动受保护文件 | 先说明原因 → 等待确认 → 再改动 |
| 用户明确说"改这个文件" | 可以改动 |
| 不确定是否受保护 | 先读 `COMPLETED.md`，再判断 |
