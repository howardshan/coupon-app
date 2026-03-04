// 核销历史记录页
// 分页列表，顶部筛选（日期范围 + Deal），支持撤销（10分钟内）

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/coupon_info.dart';
import '../providers/scan_provider.dart';
import '../widgets/redemption_record_tile.dart';

class RedemptionHistoryPage extends ConsumerWidget {
  const RedemptionHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(redemptionHistoryProvider);
    final filter = ref.watch(redemptionHistoryFilterProvider);
    final notifier = ref.read(redemptionHistoryProvider.notifier);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Redemption History',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        actions: [
          // 清除筛选按钮（有筛选条件时显示）
          if (filter.hasFilter)
            TextButton(
              onPressed: () {
                ref.read(redemptionHistoryFilterProvider.notifier).state =
                    const RedemptionHistoryFilter();
              },
              child: const Text(
                'Clear',
                style: TextStyle(color: Color(0xFFFF6B35)),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // 顶部筛选区域
          _FilterBar(filter: filter, ref: ref),

          // 历史记录列表
          Expanded(
            child: historyAsync.when(
              data: (records) => _buildList(context, ref, records, notifier),
              loading: () => const Center(
                child: CircularProgressIndicator(color: Color(0xFFFF6B35)),
              ),
              error: (e, _) => _buildError(context, notifier, e),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    WidgetRef ref,
    List<RedemptionRecord> records,
    RedemptionHistoryNotifier notifier,
  ) {
    if (records.isEmpty) {
      return _buildEmpty(context);
    }

    return RefreshIndicator(
      color: const Color(0xFFFF6B35),
      onRefresh: () => notifier.refresh(),
      child: NotificationListener<ScrollNotification>(
        // 监听滚动到底部，触发加载更多
        onNotification: (notification) {
          if (notification is ScrollEndNotification &&
              notification.metrics.extentAfter < 100 &&
              notifier.hasMore) {
            notifier.loadMore();
          }
          return false;
        },
        child: ListView.builder(
          padding: const EdgeInsets.only(top: 8, bottom: 24),
          itemCount: records.length + (notifier.hasMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= records.length) {
              // 加载更多指示器
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFFFF6B35),
                  ),
                ),
              );
            }

            final record = records[index];
            return RedemptionRecordTile(
              record: record,
              onUndo: record.canRevert
                  ? () => _handleUndo(context, ref, record)
                  : null,
            );
          },
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 72,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            'No redemption records yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Records will appear here after\nvouchers are redeemed.',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade400,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildError(
    BuildContext context,
    RedemptionHistoryNotifier notifier,
    Object error,
  ) {
    final message = error is ScanException ? error.message : 'Failed to load records.';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off_rounded, size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              message,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => notifier.refresh(),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B35),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 处理撤销按钮点击
  void _handleUndo(
    BuildContext context,
    WidgetRef ref,
    RedemptionRecord record,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Undo Redemption',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        content: Text(
          'Are you sure you want to undo the redemption of "${record.dealTitle}" for ${record.userName}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref
                    .read(redemptionHistoryProvider.notifier)
                    .revert(record.couponId);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Redemption reverted successfully.'),
                      backgroundColor: Color(0xFF34C759),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              } on ScanException catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(e.message),
                      backgroundColor: Colors.red.shade600,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            },
            child: Text(
              'Undo',
              style: TextStyle(color: Colors.red.shade500),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================
// 顶部筛选 Bar 组件
// =============================================================
class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.filter, required this.ref});
  final RedemptionHistoryFilter filter;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM d');

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // 日期范围选择器
          Expanded(
            child: _FilterChip(
              label: filter.dateFrom != null && filter.dateTo != null
                  ? '${dateFormat.format(filter.dateFrom!)} - ${dateFormat.format(filter.dateTo!)}'
                  : filter.dateFrom != null
                      ? 'From ${dateFormat.format(filter.dateFrom!)}'
                      : 'All Dates',
              icon: Icons.date_range_rounded,
              isActive: filter.dateFrom != null || filter.dateTo != null,
              onTap: () => _pickDateRange(context),
            ),
          ),
          const SizedBox(width: 10),

          // Deal 筛选（简化为文本按钮，实际项目可接 Deal 列表 API）
          Expanded(
            child: _FilterChip(
              label: filter.dealTitle ?? 'All Deals',
              icon: Icons.local_offer_outlined,
              isActive: filter.dealId != null,
              onTap: () => _showDealFilter(context),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDateRange(BuildContext context) async {
    final now = DateTime.now();
    final result = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: now,
      initialDateRange: (filter.dateFrom != null && filter.dateTo != null)
          ? DateTimeRange(start: filter.dateFrom!, end: filter.dateTo!)
          : null,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: const Color(0xFFFF6B35),
                ),
          ),
          child: child!,
        );
      },
    );

    if (result != null) {
      ref.read(redemptionHistoryFilterProvider.notifier).state =
          filter.copyWith(
        dateFrom: result.start,
        dateTo: result.end,
      );
    }
  }

  /// 展示 Deal 筛选弹窗（简化实现，实际项目需从后端加载 Deal 列表）
  void _showDealFilter(BuildContext context) {
    // 如果当前有 Deal 筛选，先清除
    if (filter.dealId != null) {
      ref.read(redemptionHistoryFilterProvider.notifier).state =
          filter.copyWith(clearDeal: true);
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Filter by Deal',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Deal filter requires integration with deal list API.\nTap any deal from your list to filter.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================
// 筛选条件 Chip 组件
// =============================================================
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFFFFF3EE)
              : const Color(0xFFF8F9FA),
          border: Border.all(
            color: isActive
                ? const Color(0xFFFF6B35)
                : Colors.grey.shade200,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isActive
                  ? const Color(0xFFFF6B35)
                  : Colors.grey.shade500,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isActive
                      ? const Color(0xFFFF6B35)
                      : Colors.grey.shade600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
