// 菜品列表页
// 顶部分类 Tab 栏 + 按分类分组展示
// 支持添加、编辑、切换状态、删除

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/menu_item.dart';
import '../models/menu_category.dart';
import '../providers/menu_provider.dart';
import '../providers/category_provider.dart';

// ============================================================
// MenuListPage — 菜品管理列表（带分类 Tab）
// ============================================================
class MenuListPage extends ConsumerStatefulWidget {
  const MenuListPage({super.key});

  @override
  ConsumerState<MenuListPage> createState() => _MenuListPageState();
}

class _MenuListPageState extends ConsumerState<MenuListPage> {
  static const _primaryOrange = Color(0xFFFF6B35);

  /// 当前选中的分类 ID，null 表示 "All"
  String? _selectedCategoryId;

  @override
  Widget build(BuildContext context) {
    final menuAsync = ref.watch(menuProvider);
    final categoriesAsync = ref.watch(categoryProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Menu Items',
          style: TextStyle(
            color: Color(0xFF1A1A1A),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          // 管理分类入口
          IconButton(
            icon: const Icon(Icons.category_outlined, color: Color(0xFF666666)),
            tooltip: 'Manage Categories',
            onPressed: () => context.push('/store/menu/categories'),
          ),
          // 添加菜品
          IconButton(
            icon: const Icon(Icons.add_rounded, color: _primaryOrange),
            onPressed: () => context.push('/store/menu/create'),
          ),
        ],
      ),
      body: menuAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: _primaryOrange),
        ),
        error: (error, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              Text('Failed to load: $error',
                  style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.read(menuProvider.notifier).refresh(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (items) {
          if (items.isEmpty) return _buildEmptyState(context);

          final categories = categoriesAsync.valueOrNull ?? [];
          return _buildContent(context, ref, items, categories);
        },
      ),
    );
  }

  // 空状态
  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.restaurant_menu,
                size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            const Text(
              'No Menu Items Yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF333333),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Add your products or dishes so you can\ninclude them in deals.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Color(0xFF999999)),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => context.push('/store/menu/create'),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add First Item'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryOrange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 主内容：分类 Tab + 菜品列表
  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    List<MenuItem> items,
    List<MenuCategory> categories,
  ) {
    // 根据选中分类过滤
    final filteredItems = _selectedCategoryId == null
        ? items
        : _selectedCategoryId == '_uncategorized'
            ? items.where((i) => i.categoryId == null).toList()
            : items.where((i) => i.categoryId == _selectedCategoryId).toList();

    return Column(
      children: [
        // 分类 Tab 栏
        if (categories.isNotEmpty) _buildCategoryTabs(categories, items),

        // 菜品列表
        Expanded(
          child: filteredItems.isEmpty
              ? _buildFilteredEmptyState()
              : RefreshIndicator(
                  color: _primaryOrange,
                  onRefresh: () async {
                    await ref.read(menuProvider.notifier).refresh();
                    await ref.read(categoryProvider.notifier).refresh();
                  },
                  child: _selectedCategoryId == null && categories.isNotEmpty
                      ? _buildGroupedList(filteredItems, categories)
                      : _buildFlatList(filteredItems),
                ),
        ),
      ],
    );
  }

  // 分类 Tab 栏（横向滚动 Chip）
  Widget _buildCategoryTabs(List<MenuCategory> categories, List<MenuItem> allItems) {
    // 统计未分类菜品数量
    final uncategorizedCount = allItems.where((i) => i.categoryId == null).length;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            // "All" Tab
            _buildTabChip(
              label: 'All',
              count: allItems.length,
              selected: _selectedCategoryId == null,
              onTap: () => setState(() => _selectedCategoryId = null),
            ),
            const SizedBox(width: 8),

            // 各分类 Tab
            ...categories.map((cat) {
              final count = allItems.where((i) => i.categoryId == cat.id).length;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _buildTabChip(
                  label: cat.name,
                  count: count,
                  selected: _selectedCategoryId == cat.id,
                  onTap: () => setState(() => _selectedCategoryId = cat.id),
                ),
              );
            }),

            // "Uncategorized" Tab（仅当有未分类菜品时显示）
            if (uncategorizedCount > 0)
              _buildTabChip(
                label: 'Uncategorized',
                count: uncategorizedCount,
                selected: _selectedCategoryId == '_uncategorized',
                onTap: () => setState(() => _selectedCategoryId = '_uncategorized'),
              ),
          ],
        ),
      ),
    );
  }

  // 单个 Tab Chip
  Widget _buildTabChip({
    required String label,
    required int count,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _primaryOrange : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? _primaryOrange : const Color(0xFFE0E0E0),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : const Color(0xFF555555),
              ),
            ),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: selected
                    ? Colors.white.withAlpha(51)
                    : const Color(0xFFE0E0E0),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : const Color(0xFF999999),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 选中分类无菜品时的空状态
  Widget _buildFilteredEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_outlined, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          const Text(
            'No items in this category',
            style: TextStyle(fontSize: 15, color: Color(0xFF999999)),
          ),
        ],
      ),
    );
  }

  // 按分类分组展示（"All" Tab 时使用）
  Widget _buildGroupedList(List<MenuItem> items, List<MenuCategory> categories) {
    // 构建分组数据
    final List<Widget> slivers = [];

    for (final cat in categories) {
      final catItems = items.where((i) => i.categoryId == cat.id).toList();
      if (catItems.isEmpty) continue;

      slivers.add(SliverToBoxAdapter(
        child: _buildSectionHeader(cat.name, catItems.length),
      ));
      slivers.add(SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _MenuItemCard(item: catItems[index]),
          ),
          childCount: catItems.length,
        ),
      ));
      slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 8)));
    }

    // 未分类菜品
    final uncategorized = items.where((i) => i.categoryId == null).toList();
    if (uncategorized.isNotEmpty) {
      slivers.add(SliverToBoxAdapter(
        child: _buildSectionHeader('Uncategorized', uncategorized.length),
      ));
      slivers.add(SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _MenuItemCard(item: uncategorized[index]),
          ),
          childCount: uncategorized.length,
        ),
      ));
    }

    // 底部间距
    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 16)));

    return CustomScrollView(slivers: slivers);
  }

  // 分组标题
  Widget _buildSectionHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF333333),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '($count)',
            style: const TextStyle(fontSize: 13, color: Color(0xFF999999)),
          ),
        ],
      ),
    );
  }

  // 平铺列表（选中特定分类时使用）
  Widget _buildFlatList(List<MenuItem> items) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        return _MenuItemCard(item: items[index]);
      },
    );
  }
}

// ============================================================
// _MenuItemCard — 单个菜品卡片
// ============================================================
class _MenuItemCard extends ConsumerWidget {
  const _MenuItemCard({required this.item});

  final MenuItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete Item'),
            content: Text('Delete "${item.name}"?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete',
                    style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) {
        ref.read(menuProvider.notifier).deleteItem(item.id);
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red.shade400,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      child: Card(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey.shade100),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => context.push('/store/menu/${item.id}', extra: item),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // 图片
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 60,
                    height: 60,
                    child: item.imageUrl != null && item.imageUrl!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: item.imageUrl!,
                            fit: BoxFit.cover,
                            placeholder: (_, _) => Container(
                              color: Colors.grey.shade100,
                              child: const Icon(Icons.image,
                                  color: Colors.grey, size: 24),
                            ),
                            errorWidget: (_, _, _) => Container(
                              color: Colors.grey.shade100,
                              child: const Icon(Icons.broken_image,
                                  color: Colors.grey, size: 24),
                            ),
                          )
                        : Container(
                            color: Colors.grey.shade100,
                            child: const Icon(Icons.restaurant,
                                color: Colors.grey, size: 24),
                          ),
                  ),
                ),
                const SizedBox(width: 12),

                // 名称 + 分类 + 价格
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.name,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: item.isActive
                                    ? const Color(0xFF1A1A1A)
                                    : Colors.grey,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (item.isSignature)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF3E0),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Signature',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFFFF6B35),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            item.price != null
                                ? '\$${item.price!.toStringAsFixed(2)}'
                                : 'No price',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: item.isActive
                                  ? const Color(0xFF333333)
                                  : Colors.grey,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            item.categoryLabel,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF999999),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // 状态开关
                Switch(
                  value: item.isActive,
                  activeThumbColor: const Color(0xFFFF6B35),
                  onChanged: (_) {
                    ref.read(menuProvider.notifier).toggleStatus(item.id);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
