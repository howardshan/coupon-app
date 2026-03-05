// 菜品选择器弹窗
// 用于 Deal 创建页选择套餐内容
// 展示 active 菜品列表，支持数量调整(+/-)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/menu_item.dart';
import '../providers/menu_provider.dart';

// ============================================================
// MenuItemPicker — 全屏弹窗选择菜品
// ============================================================
class MenuItemPicker extends ConsumerStatefulWidget {
  const MenuItemPicker({
    super.key,
    this.initialSelection = const [],
  });

  /// 已选菜品（编辑时回填）
  final List<SelectedMenuItem> initialSelection;

  @override
  ConsumerState<MenuItemPicker> createState() => _MenuItemPickerState();
}

class _MenuItemPickerState extends ConsumerState<MenuItemPicker> {
  static const _primaryOrange = Color(0xFFFF6B35);

  // 菜品ID → 选中数量
  late Map<String, int> _selectedQuantities;

  @override
  void initState() {
    super.initState();
    _selectedQuantities = {
      for (final s in widget.initialSelection) s.menuItem.id: s.quantity,
    };
  }

  // 总价
  double _calcTotal(List<MenuItem> items) {
    double total = 0;
    for (final item in items) {
      final qty = _selectedQuantities[item.id] ?? 0;
      if (qty > 0) {
        total += (item.price ?? 0) * qty;
      }
    }
    return total;
  }

  // 选中数量
  int _calcCount() {
    return _selectedQuantities.values.fold(0, (sum, qty) => sum + qty);
  }

  @override
  Widget build(BuildContext context) {
    final activeItemsAsync = ref.watch(activeMenuItemsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Color(0xFF333333)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Select Items',
          style: TextStyle(
            color: Color(0xFF1A1A1A),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: activeItemsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: _primaryOrange),
        ),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (items) {
          if (items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.restaurant_menu, size: 48, color: Colors.grey),
                    SizedBox(height: 12),
                    Text(
                      'No active menu items',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF333333),
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Add items in Store → Menu Items first.',
                      style: TextStyle(fontSize: 13, color: Color(0xFF999999)),
                    ),
                  ],
                ),
              ),
            );
          }

          return Column(
            children: [
              // 菜品列表
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final qty = _selectedQuantities[item.id] ?? 0;
                    return _buildItemRow(item, qty);
                  },
                ),
              ),

              // 底部确认栏
              _buildBottomBar(items),
            ],
          );
        },
      ),
    );
  }

  Widget _buildItemRow(MenuItem item, int qty) {
    final isSelected = qty > 0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? _primaryOrange.withAlpha(100) : Colors.grey.shade100,
        ),
      ),
      child: Row(
        children: [
          // 图片
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 50,
              height: 50,
              child: item.imageUrl != null && item.imageUrl!.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: item.imageUrl!,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => Container(
                        color: Colors.grey.shade100,
                      ),
                      errorWidget: (_, _, _) => Container(
                        color: Colors.grey.shade100,
                        child: const Icon(Icons.image, size: 20, color: Colors.grey),
                      ),
                    )
                  : Container(
                      color: Colors.grey.shade100,
                      child: const Icon(Icons.restaurant, size: 20, color: Colors.grey),
                    ),
            ),
          ),
          const SizedBox(width: 12),

          // 名称 + 价格
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A1A),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  item.price != null
                      ? '\$${item.price!.toStringAsFixed(2)}'
                      : 'No price',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF666666),
                  ),
                ),
              ],
            ),
          ),

          // 数量调整
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 减
              if (qty > 0)
                _buildQtyButton(
                  icon: Icons.remove,
                  onTap: () {
                    setState(() {
                      if (qty <= 1) {
                        _selectedQuantities.remove(item.id);
                      } else {
                        _selectedQuantities[item.id] = qty - 1;
                      }
                    });
                  },
                ),
              if (qty > 0)
                SizedBox(
                  width: 32,
                  child: Text(
                    '$qty',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                ),
              // 加
              _buildQtyButton(
                icon: Icons.add,
                filled: qty == 0,
                onTap: () {
                  setState(() {
                    _selectedQuantities[item.id] = qty + 1;
                  });
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQtyButton({
    required IconData icon,
    required VoidCallback onTap,
    bool filled = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: filled ? _primaryOrange : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: filled ? _primaryOrange : const Color(0xFFDDDDDD),
          ),
        ),
        child: Icon(
          icon,
          size: 18,
          color: filled ? Colors.white : const Color(0xFF666666),
        ),
      ),
    );
  }

  Widget _buildBottomBar(List<MenuItem> allItems) {
    final count = _calcCount();
    final total = _calcTotal(allItems);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(13),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          // 统计
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$count item${count != 1 ? 's' : ''} selected',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF666666),
                  ),
                ),
                if (total > 0)
                  Text(
                    'Total: \$${total.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
              ],
            ),
          ),

          // 确认按钮
          SizedBox(
            height: 44,
            child: ElevatedButton(
              onPressed: count > 0
                  ? () {
                      // 构建选中列表返回
                      final result = <SelectedMenuItem>[];
                      for (final entry in _selectedQuantities.entries) {
                        final item = allItems.firstWhere(
                          (i) => i.id == entry.key,
                          orElse: () => allItems.first,
                        );
                        result.add(SelectedMenuItem(
                          menuItem: item,
                          quantity: entry.value,
                        ));
                      }
                      Navigator.pop(context, result);
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryOrange,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 24),
              ),
              child: const Text(
                'Confirm',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
