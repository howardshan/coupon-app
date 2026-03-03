# 模块 3：搜索系统 - 实施计划

## 完成状态：✅ 已完成

## 新建文件

### 1. search_provider.dart
- [x] `SearchSortOption` 枚举（5 种排序：相关度/距离/价格/销量/评分）
- [x] `SearchFilters` 数据类（分类/价格范围/评分，含 copyWith + clear 方法）
- [x] `searchSortProvider` / `searchFiltersProvider` - 状态管理
- [x] `SearchHistoryNotifier` - shared_preferences 持久化，最多 10 条，去重
- [x] `searchSuggestionsProvider` - 输入 2 字符触发，最多 8 条建议
- [x] `searchResultsProvider` - 完整搜索结果，含服务端分类 + 客户端价格/评分过滤 + 排序

### 2. search_screen.dart
- [x] `ConsumerStatefulWidget` 三阶段状态机：idle / suggesting / results
- [x] idle：热门搜索标签（Top3 高亮）+ 搜索历史（可删除/清空）
- [x] suggesting：300ms 防抖 + 关键词高亮 + shimmer 加载
- [x] results：结果数量 + 横排卡片 + 过滤排序工具栏
- [x] `_FilterSheet` - DraggableScrollableSheet（分类/价格/评分）
- [x] `_SortSheet` - 排序选项列表

### 3. app_router.dart
- [x] 添加 `/search` 路由

### 4. 测试
- [x] `SearchFilters` copyWith / clear / hasActiveFilters（7 个用例）
- [x] `SearchSortOption` label 值验证（3 个用例）
