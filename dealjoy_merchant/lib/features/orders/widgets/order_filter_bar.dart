// 订单筛选行组件
// 包含：日期范围 Chip + Deal 筛选 Chip
// 无状态，由外层通过 onFilterChanged 回调更新筛选条件

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/merchant_order.dart';
import '../providers/orders_provider.dart';

/// 订单筛选行（日期范围 + Deal 筛选）
/// ConsumerWidget，读取 orderFilterProvider 和 merchantDealsForFilterProvider
class OrderFilterBar extends ConsumerWidget {
  const OrderFilterBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(orderFilterProvider);
    final dealsAsync = ref.watch(merchantDealsForFilterProvider);

    final hasDateFilter = filter.dateFrom != null || filter.dateTo != null;
    final hasDealFilter = filter.dealId != null;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // 日期范围 Chip
          _FilterChip(
            label: filter.dateRangeLabel,
            isActive: hasDateFilter,
            icon: Icons.calendar_today_outlined,
            onTap: () => _showDateRangePicker(context, ref, filter),
            onClear: hasDateFilter
                ? () => ref.read(orderFilterProvider.notifier).update(
                      (f) => f.copyWith(
                          clearDateFrom: true, clearDateTo: true),
                    )
                : null,
          ),
          const SizedBox(width: 8),

          // Deal 筛选 Chip
          dealsAsync.when(
            data: (deals) => _FilterChip(
              label: filter.dealTitle ?? 'All Deals',
              isActive: hasDealFilter,
              icon: Icons.local_offer_outlined,
              onTap: () =>
                  _showDealPicker(context, ref, filter, deals),
              onClear: hasDealFilter
                  ? () => ref.read(orderFilterProvider.notifier).update(
                        (f) => f.copyWith(clearDeal: true),
                      )
                  : null,
            ),
            loading: () => _FilterChip(
              label: 'All Deals',
              isActive: false,
              icon: Icons.local_offer_outlined,
              onTap: () {},
              onClear: null,
            ),
            error: (err, st) => _FilterChip(
              label: 'All Deals',
              isActive: false,
              icon: Icons.local_offer_outlined,
              onTap: () {},
              onClear: null,
            ),
          ),

          // 有额外筛选时显示 Clear All 按钮
          if (filter.hasExtraFilter) ...[
            const Spacer(),
            TextButton(
              onPressed: () {
                ref
                    .read(orderFilterProvider.notifier)
                    .update((f) => f.clearExtra());
              },
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Clear All',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFFFF6B35),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // 日期范围选择器
  Future<void> _showDateRangePicker(
    BuildContext context,
    WidgetRef ref,
    OrderFilter filter,
  ) async {
    final now = DateTime.now();
    final initial = DateTimeRange(
      start: filter.dateFrom ?? now.subtract(const Duration(days: 30)),
      end: filter.dateTo ?? now,
    );

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: now,
      initialDateRange: initial,
      builder: (ctx, child) {
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFFF6B35),
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      ref.read(orderFilterProvider.notifier).update(
            (f) => f.copyWith(
              dateFrom: picked.start,
              dateTo: picked.end,
            ),
          );
    }
  }

  // Deal 选择底部弹窗
  Future<void> _showDealPicker(
    BuildContext context,
    WidgetRef ref,
    OrderFilter filter,
    List<Map<String, String>> deals,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.5,
          maxChildSize: 0.85,
          minChildSize: 0.3,
          builder: (ctx, scrollController) {
            return Column(
              children: [
                // 顶部把手
                const SizedBox(height: 12),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Filter by Deal',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 8),
                Divider(color: Colors.grey.shade100),

                Expanded(
                  child: ListView(
                    controller: scrollController,
                    children: [
                      // "All Deals" 选项
                      _DealPickerItem(
                        title: 'All Deals',
                        isSelected: filter.dealId == null,
                        onTap: () {
                          ref.read(orderFilterProvider.notifier).update(
                                (f) => f.copyWith(clearDeal: true),
                              );
                          Navigator.of(ctx).pop();
                        },
                      ),
                      ...deals.map((deal) => _DealPickerItem(
                            title: deal['title'] ?? '',
                            isSelected: filter.dealId == deal['id'],
                            onTap: () {
                              ref
                                  .read(orderFilterProvider.notifier)
                                  .update(
                                    (f) => f.copyWith(
                                      dealId: deal['id'],
                                      dealTitle: deal['title'],
                                    ),
                                  );
                              Navigator.of(ctx).pop();
                            },
                          )),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

// =============================================================
// 内部组件：筛选 Chip
// =============================================================
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.isActive,
    required this.icon,
    required this.onTap,
    this.onClear,
  });

  final String label;
  final bool isActive;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.only(
          left: 10,
          right: onClear != null ? 6 : 10,
          top: 7,
          bottom: 7,
        ),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFFFFF4F0)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive
                ? const Color(0xFFFF6B35).withValues(alpha: 0.5)
                : Colors.grey.shade200,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isActive
                  ? const Color(0xFFFF6B35)
                  : Colors.grey.shade500,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight:
                    isActive ? FontWeight.w600 : FontWeight.w500,
                color: isActive
                    ? const Color(0xFFFF6B35)
                    : Colors.grey.shade700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (onClear != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onClear,
                child: Icon(
                  Icons.close_rounded,
                  size: 14,
                  color: const Color(0xFFFF6B35).withValues(alpha: 0.7),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// =============================================================
// 内部组件：Deal 选择项
// =============================================================
class _DealPickerItem extends StatelessWidget {
  const _DealPickerItem({
    required this.title,
    required this.isSelected,
    required this.onTap,
  });

  final String title;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight:
                      isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected
                      ? const Color(0xFFFF6B35)
                      : const Color(0xFF1A1A1A),
                ),
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_rounded,
                size: 18,
                color: Color(0xFFFF6B35),
              ),
          ],
        ),
      ),
    );
  }
}
