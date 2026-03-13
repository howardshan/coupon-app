// 工作台快捷入口网格组件
// 6 个功能入口: Redeem / Deals / Orders / Reviews / Analytics / Store
// 布局: 3 列 x 2 行，圆形图标背景 + 下方文字标签

import 'package:flutter/material.dart';

// ============================================================
// ShortcutAction 枚举 — 标识每个入口的操作类型
// ============================================================
enum ShortcutAction {
  redeem,
  deals,
  orders,
  reviews,
  analytics,
  store, // 替换原来的 settings，直接跳转店铺管理
  menu, // 菜品/菜单管理
  brand, // 品牌管理（仅品牌管理员可见）
}

// ============================================================
// _ShortcutItem 内部数据类 — 图标 + 标签 + 颜色 + 路由
// ============================================================
class _ShortcutItem {
  final ShortcutAction action;
  final IconData icon;
  final String label;
  final Color color;

  const _ShortcutItem({
    required this.action,
    required this.icon,
    required this.label,
    required this.color,
  });
}

// ============================================================
// ShortcutGrid — 6 格快捷入口
// ============================================================
class ShortcutGrid extends StatelessWidget {
  /// 点击回调，参数为对应的 ShortcutAction
  final void Function(ShortcutAction action) onTap;

  /// 是否品牌管理员（控制 Brand 入口显示）
  final bool isBrandAdmin;

  const ShortcutGrid({super.key, required this.onTap, this.isBrandAdmin = false});

  // 6 个快捷入口定义（美团工作台风格）
  static const List<_ShortcutItem> _items = [
    _ShortcutItem(
      action: ShortcutAction.redeem,
      icon: Icons.qr_code_scanner,
      label: 'Redeem',
      color: Color(0xFFFF6B35), // 品牌橙色，最常用操作突出显示
    ),
    _ShortcutItem(
      action: ShortcutAction.deals,
      icon: Icons.local_offer_outlined,
      label: 'Deals',
      color: Color(0xFF2196F3), // 蓝色
    ),
    _ShortcutItem(
      action: ShortcutAction.orders,
      icon: Icons.receipt_long_outlined,
      label: 'Orders',
      color: Color(0xFF4CAF50), // 绿色
    ),
    _ShortcutItem(
      action: ShortcutAction.reviews,
      icon: Icons.star_outline,
      label: 'Reviews',
      color: Color(0xFFFF9800), // 橙黄色
    ),
    _ShortcutItem(
      action: ShortcutAction.analytics,
      icon: Icons.bar_chart_outlined,
      label: 'Analytics',
      color: Color(0xFF9C27B0), // 紫色
    ),
    _ShortcutItem(
      action: ShortcutAction.store,
      icon: Icons.storefront_outlined,
      label: 'Store',
      color: Color(0xFF607D8B), // 蓝灰色
    ),
    _ShortcutItem(
      action: ShortcutAction.menu,
      icon: Icons.restaurant_menu_outlined,
      label: 'Menu',
      color: Color(0xFFE91E63), // 粉红色
    ),
    _ShortcutItem(
      action: ShortcutAction.brand,
      icon: Icons.business_outlined,
      label: 'Brand',
      color: Color(0xFF795548), // 棕色
    ),
  ];

  @override
  Widget build(BuildContext context) {
    // 非品牌管理员过滤掉 Brand 入口
    final visibleItems = isBrandAdmin
        ? _items
        : _items.where((i) => i.action != ShortcutAction.brand).toList();

    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true, // 内嵌在 ScrollView 中需要
      physics: const NeverScrollableScrollPhysics(), // 禁用自身滚动
      childAspectRatio: 0.9, // 4 列稍窄，调整比例
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      children: visibleItems.map((item) => _ShortcutCell(
        item: item,
        onTap: () => onTap(item.action),
      )).toList(),
    );
  }
}

// ============================================================
// _ShortcutCell — 单个快捷入口 Widget
// ============================================================
class _ShortcutCell extends StatelessWidget {
  final _ShortcutItem item;
  final VoidCallback onTap;

  const _ShortcutCell({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade100),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 圆形图标背景（美团风格）
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: item.color.withAlpha(26), // ~10% 透明度
                shape: BoxShape.circle,
              ),
              child: Icon(
                item.icon,
                size: 24,
                color: item.color,
              ),
            ),

            const SizedBox(height: 8),

            // 入口标签
            Text(
              item.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
