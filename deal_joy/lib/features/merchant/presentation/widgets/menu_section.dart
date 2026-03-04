import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/models/menu_item_model.dart';
import 'menu_item_card.dart';

/// Menu Tab 整体容器
/// 接收按分类分组的菜品 Map，分三个区块展示
/// keys: 'signature' | 'popular' | 'regular'
class MenuSection extends StatelessWidget {
  final Map<String, List<MenuItemModel>> groupedItems;

  const MenuSection({super.key, required this.groupedItems});

  @override
  Widget build(BuildContext context) {
    final signature = groupedItems['signature'] ?? [];
    final popular = groupedItems['popular'] ?? [];
    final regular = groupedItems['regular'] ?? [];

    // 三组全空时显示空状态
    if (signature.isEmpty && popular.isEmpty && regular.isEmpty) {
      return const Center(
        child: Text(
          'No menu items available',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Signature Dishes 区块
          if (signature.isNotEmpty) ...[
            _SectionHeader(
              title: 'Signature Dishes',
              count: signature.length,
            ),
            const SizedBox(height: 10),
            _HorizontalCardList(items: signature),
            const SizedBox(height: 20),
          ],

          // Popular Picks 区块
          if (popular.isNotEmpty) ...[
            _SectionHeader(
              title: 'Popular Picks',
              count: popular.length,
            ),
            const SizedBox(height: 10),
            _HorizontalCardList(items: popular),
            const SizedBox(height: 20),
          ],

          // All Items 网格区块（regular 菜品）
          if (regular.isNotEmpty) ...[
            _SectionHeader(
              title: 'All Items',
              count: regular.length,
            ),
            const SizedBox(height: 10),
            _RegularGrid(items: regular),
          ],
        ],
      ),
    );
  }
}

/// 区块标题组件：标题文字 + 括号内数量
class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;

  const _SectionHeader({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '($count)',
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 水平滚动菜品卡片列表（高 180）
class _HorizontalCardList extends StatelessWidget {
  final List<MenuItemModel> items;

  const _HorizontalCardList({required this.items});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 180,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) => MenuItemCard(item: items[index]),
      ),
    );
  }
}

/// regular 菜品网格布局（两列）
class _RegularGrid extends StatelessWidget {
  final List<MenuItemModel> items;

  const _RegularGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        // 内嵌在 SingleChildScrollView 中，禁止自身滚动
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 140 / 180, // 与横滑卡片保持相同比例
        ),
        itemCount: items.length,
        itemBuilder: (context, index) => MenuItemCard(item: items[index]),
      ),
    );
  }
}
