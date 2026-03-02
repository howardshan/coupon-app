# 模块 4：Deal 详情页 - 实施计划

## 完成状态：✅ 已完成

## 修改文件

### 1. deal_detail_screen.dart
- [x] 修复 Share 按钮：`SharePlus.instance.share(ShareParams(...))` → `Share.share(text)`
- [x] `_DealDetailBody` 从 `StatefulWidget` 转为 `ConsumerStatefulWidget`
- [x] 底部栏：左侧添加收藏心形按钮（关联 savedDealsNotifierProvider）
- [x] 地图区域：添加静态地图图片 + GestureDetector 打开 Google Maps 导航
- [x] `_mapFallback()` 辅助组件（图片加载失败时的占位）
- [x] 修复 CachedNetworkImage errorWidget 多余下划线警告

### 2. .env
- [x] Stripe key 格式修复：`sb_publishable_*` → `pk_test_REPLACE_WITH_YOUR_STRIPE_KEY`
