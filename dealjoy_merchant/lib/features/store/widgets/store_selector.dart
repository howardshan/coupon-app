// 门店切换组件（品牌管理员专用）
// 在 AppBar 中显示当前门店名称，点击弹出门店列表切换

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/store_summary.dart';
import '../providers/store_provider.dart';
import '../../dashboard/providers/dashboard_provider.dart';
import '../../deals/providers/deals_provider.dart';
import '../../orders/providers/orders_provider.dart';
import '../../reviews/providers/reviews_provider.dart';
import '../../analytics/providers/analytics_provider.dart';
import '../../earnings/providers/earnings_provider.dart';
import '../../scan/providers/scan_provider.dart';
import '../../notifications/providers/notifications_provider.dart';
import '../../promotions/providers/promotions_provider.dart';

// ============================================================
// StoreSelector — 品牌管理员门店切换下拉组件
// ============================================================
class StoreSelector extends ConsumerWidget {
  const StoreSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storeAsync = ref.watch(storeProvider);

    return storeAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (store) {
        // 非品牌管理员不显示切换器
        if (!store.isBrandAdmin) return const SizedBox.shrink();

        return InkWell(
          onTap: () => _showStorePicker(context, ref, store.id),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFFF6B35).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFFFF6B35).withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.store, size: 16, color: Color(0xFFFF6B35)),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Text(
                    store.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.unfold_more, size: 16, color: Color(0xFFFF6B35)),
              ],
            ),
          ),
        );
      },
    );
  }

  // ----------------------------------------------------------
  // 门店选择底部弹窗
  // ----------------------------------------------------------
  Future<void> _showStorePicker(
    BuildContext context,
    WidgetRef ref,
    String currentStoreId,
  ) async {
    final storesAsync = ref.read(brandStoresProvider);
    final stores = storesAsync.valueOrNull ?? [];

    if (stores.isEmpty) {
      // 触发加载
      ref.invalidate(brandStoresProvider);
      return;
    }

    final selected = await showModalBottomSheet<StoreSummary>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _StorePickerSheet(
        stores: stores,
        currentStoreId: currentStoreId,
      ),
    );

    if (selected != null && selected.id != currentStoreId) {
      await ref.read(storeProvider.notifier).switchStore(selected.id);
      // 切换后刷新所有门店相关数据
      invalidateAllStoreProviders(ref);
    }
  }
}

// ============================================================
// invalidateAllStoreProviders — 切换门店后刷新所有数据
// StoreSelectorPage 也会复用此函数
// ============================================================
void invalidateAllStoreProviders(WidgetRef ref) {
  ref.invalidate(brandStoresProvider);
  ref.invalidate(dashboardProvider);
  ref.invalidate(storeOnlineProvider);
  ref.invalidate(dealsProvider);
  ref.invalidate(ordersNotifierProvider);
  ref.invalidate(reviewsProvider);
  ref.invalidate(reviewStatsProvider);
  ref.invalidate(overviewProvider);
  ref.invalidate(earningsSummaryProvider);
  ref.invalidate(scanNotifierProvider);
  ref.invalidate(redemptionHistoryProvider);
  ref.invalidate(notificationsNotifierProvider);
  ref.invalidate(unreadCountProvider);
  // 广告推广数据随门店切换刷新
  ref.invalidate(adAccountProvider);
  ref.invalidate(campaignsProvider);
}

// ============================================================
// _StorePickerSheet — 门店列表弹窗
// ============================================================
class _StorePickerSheet extends StatelessWidget {
  const _StorePickerSheet({
    required this.stores,
    required this.currentStoreId,
  });

  final List<StoreSummary> stores;
  final String currentStoreId;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 拖拽指示条
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Switch Store',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.4,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: stores.length,
                itemBuilder: (ctx, i) {
                  final store = stores[i];
                  final isSelected = store.id == currentStoreId;

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isSelected
                          ? const Color(0xFFFF6B35).withValues(alpha: 0.1)
                          : Colors.grey.withValues(alpha: 0.1),
                      child: Icon(
                        Icons.store,
                        color: isSelected ? const Color(0xFFFF6B35) : Colors.grey,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      store.name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                        color: isSelected ? const Color(0xFFFF6B35) : const Color(0xFF1A1A1A),
                      ),
                    ),
                    subtitle: store.address != null
                        ? Text(
                            store.address!,
                            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )
                        : null,
                    trailing: isSelected
                        ? const Icon(Icons.check_circle, color: Color(0xFFFF6B35), size: 20)
                        : null,
                    onTap: () => Navigator.pop(ctx, store),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
