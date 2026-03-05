import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/models/deal_category_model.dart';

/// Deal 分类筛选标签栏的 SliverPersistentHeaderDelegate
/// 用于在 CustomScrollView 中实现二级吸顶效果
class DealCategoryFilterDelegate extends SliverPersistentHeaderDelegate {
  final List<DealCategoryModel> categories;
  final String? selectedCategoryId;
  final ValueChanged<String?> onSelected;

  DealCategoryFilterDelegate({
    required this.categories,
    required this.selectedCategoryId,
    required this.onSelected,
  });

  @override
  double get minExtent => 48;

  @override
  double get maxExtent => 48;

  @override
  bool shouldRebuild(covariant DealCategoryFilterDelegate oldDelegate) {
    return oldDelegate.selectedCategoryId != selectedCategoryId ||
        oldDelegate.categories != categories;
  }

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return DealCategoryFilter(
      categories: categories,
      selectedCategoryId: selectedCategoryId,
      onSelected: onSelected,
    );
  }
}

/// Deal 分类筛选标签栏组件
class DealCategoryFilter extends StatelessWidget {
  final List<DealCategoryModel> categories;
  final String? selectedCategoryId;
  final ValueChanged<String?> onSelected;

  const DealCategoryFilter({
    super.key,
    required this.categories,
    required this.selectedCategoryId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    // 无分类时不显示
    if (categories.isEmpty) return const SizedBox.shrink();

    // "All" + 动态分类
    final items = [null, ...categories.map((c) => c.id)];
    final labels = ['All', ...categories.map((c) => c.name)];

    return Container(
      height: 48,
      color: AppColors.surface,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final isSelected = selectedCategoryId == items[i];
          return GestureDetector(
            onTap: () => onSelected(items[i]),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.secondary
                    : AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                labels[i],
                style: TextStyle(
                  fontSize: 13,
                  fontWeight:
                      isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? Colors.white : AppColors.textPrimary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
