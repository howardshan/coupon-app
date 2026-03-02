# 模块 2：首页与推荐 - 实施计划

## 完成状态：✅ 已完成

## 修改清单

### 1. deals_provider.dart - 新增 GPS + 收藏 Providers
- [x] `userLocationProvider` - FutureProvider，获取 GPS 坐标，权限被拒回退到 Dallas 默认
- [x] `distanceMiles()` - Haversine 公式计算两点距离（英里）
- [x] `savedDealIdsProvider` - 快速查询已收藏 deal ID 集合
- [x] `savedDealsListProvider` - 获取完整收藏 deal 列表
- [x] `SavedDealsNotifier` - 切换收藏状态（toggle save/unsave）

### 2. home_screen.dart - UI 修复
- [x] 分类图标 `GestureDetector` 关联 `selectedCategoryProvider`
- [x] 选中分类视觉高亮（蓝色边框 + 背景色）
- [x] "View All" 按钮导航到 `/search`
- [x] `_LargeDealCard` 转 `ConsumerWidget`，添加收藏心形按钮
- [x] 硬编码距离替换为 `_DistanceText` ConsumerWidget（实时 GPS 计算）

### 3. 测试
- [x] `distanceMiles` Haversine 公式单元测试（4 个用例）
- [x] `DealModel` fromJson / 缺省值 / effectiveDiscountLabel / savingsAmount / isExpired（8 个用例）
- [x] `MerchantSummary` fromJson 测试（2 个用例）
