// 商家类别选择网格组件
// 8个类别卡片，单选，选中态显示橙色边框

import 'package:flutter/material.dart';
import '../models/merchant_application.dart';

// ============================================================
// CategorySelector — 商家类别选择网格
// ============================================================
class CategorySelector extends StatelessWidget {
  const CategorySelector({
    super.key,
    required this.selectedCategory,
    required this.onCategorySelected,
  });

  /// 当前选中的类别（null 表示未选）
  final MerchantCategory? selectedCategory;

  /// 用户点击某个类别时的回调
  final ValueChanged<MerchantCategory> onCategorySelected;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.4,
      ),
      itemCount: MerchantCategory.values.length,
      itemBuilder: (context, index) {
        final category = MerchantCategory.values[index];
        final isSelected = category == selectedCategory;
        return _CategoryCard(
          category: category,
          isSelected: isSelected,
          onTap: () => onCategorySelected(category),
        );
      },
    );
  }
}

// ============================================================
// 单个类别卡片（私有组件）
// ============================================================
class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.category,
    required this.isSelected,
    required this.onTap,
  });

  final MerchantCategory category;
  final bool isSelected;
  final VoidCallback onTap;

  static const _primaryOrange = Color(0xFFFF6B35);

  // 根据类别名称返回对应的 Material Icon
  IconData _getIcon() {
    switch (category) {
      case MerchantCategory.restaurant:
        return Icons.restaurant;
      case MerchantCategory.spaAndMassage:
        return Icons.spa;
      case MerchantCategory.hairAndBeauty:
        return Icons.content_cut;
      case MerchantCategory.fitness:
        return Icons.fitness_center;
      case MerchantCategory.funAndGames:
        return Icons.sports_esports;
      case MerchantCategory.nailAndLash:
        return Icons.back_hand;
      case MerchantCategory.wellness:
        return Icons.self_improvement;
      case MerchantCategory.other:
        return Icons.store;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isSelected
              ? _primaryOrange.withAlpha(25) // 选中时淡橙色背景
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? _primaryOrange : const Color(0xFFE0E0E0),
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(13),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _getIcon(),
              size: 32,
              color: isSelected ? _primaryOrange : const Color(0xFF757575),
            ),
            const SizedBox(height: 8),
            Text(
              category.label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight:
                    isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected
                    ? _primaryOrange
                    : const Color(0xFF212121),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
