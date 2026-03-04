import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

/// Deals 分类过滤条组件
/// 横向可滚动的 ChoiceChip 列表，用于过滤商家详情页中的 deal 列表
class DealFilterBar extends StatelessWidget {
  /// 当前选中的过滤条件
  final String selectedFilter;

  /// 过滤条件变更回调
  final ValueChanged<String> onFilterChanged;

  /// 可选过滤选项，默认提供常用分类
  final List<String> filters;

  const DealFilterBar({
    super.key,
    required this.selectedFilter,
    required this.onFilterChanged,
    this.filters = const ['All', '2-Person', 'Multi-Person', 'Flash Deal'],
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = filters[index];
          final isSelected = filter == selectedFilter;

          return GestureDetector(
            onTap: () => onFilterChanged(filter),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                // 选中：primary 背景；未选中：surfaceVariant 背景
                color: isSelected ? AppColors.primary : AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                filter,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  // 选中：白字；未选中：深色文字
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
