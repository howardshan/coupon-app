import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/providers/history_provider.dart';
import '../widgets/collection_cards.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Recently Viewed'),
          backgroundColor: Colors.white,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          surfaceTintColor: Colors.white,
          bottom: const TabBar(
            tabs: [Tab(text: 'Deals'), Tab(text: 'Stores')],
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.primary,
            dividerColor: AppColors.surfaceVariant,
          ),
        ),
        body: const TabBarView(
          children: [_HistoryDealsTab(), _HistoryStoresTab()],
        ),
      ),
    );
  }
}

// ── Deals tab ─────────────────────────────────────────────────
class _HistoryDealsTab extends ConsumerWidget {
  const _HistoryDealsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dealsAsync = ref.watch(historyDealsProvider);

    return dealsAsync.when(
      data: (deals) => deals.isEmpty
          ? CollectionEmptyState(
              icon: Icons.history,
              message: 'No deals viewed yet',
              hint: 'Deals you view will appear here',
              onExplore: () => context.go('/home'),
            )
          : RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(historyIdsProvider);
                ref.invalidate(historyDealsProvider);
              },
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: deals.length + 1, // +1 清空按钮
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (_, i) {
                  if (i == deals.length) {
                    return _ClearButton(
                      onClear: () async {
                        await ref
                            .read(historyRepositoryProvider)
                            .clearHistory();
                        ref.invalidate(historyIdsProvider);
                        ref.invalidate(historyDealsProvider);
                      },
                    );
                  }
                  return DealListCard(deal: deals[i]);
                },
              ),
            ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}

// ── Stores tab ────────────────────────────────────────────────
class _HistoryStoresTab extends ConsumerWidget {
  const _HistoryStoresTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storesAsync = ref.watch(historyMerchantsProvider);

    return storesAsync.when(
      data: (stores) => stores.isEmpty
          ? CollectionEmptyState(
              icon: Icons.store_outlined,
              message: 'No stores viewed yet',
              hint: 'Stores you visit will appear here',
              onExplore: () => context.go('/home'),
            )
          : RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(historyMerchantIdsProvider);
                ref.invalidate(historyMerchantsProvider);
              },
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: stores.length + 1,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (_, i) {
                  if (i == stores.length) {
                    return _ClearButton(
                      onClear: () async {
                        await ref
                            .read(historyRepositoryProvider)
                            .clearMerchantHistory();
                        ref.invalidate(historyMerchantIdsProvider);
                        ref.invalidate(historyMerchantsProvider);
                      },
                    );
                  }
                  return MerchantListCard(merchant: stores[i]);
                },
              ),
            ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}

// ── 清空历史按钮 ───────────────────────────────────────────────
class _ClearButton extends StatelessWidget {
  final VoidCallback onClear;

  const _ClearButton({required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: OutlinedButton.icon(
        onPressed: onClear,
        icon: const Icon(Icons.delete_outline, size: 16),
        label: const Text('Clear History'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          side: const BorderSide(color: AppColors.surfaceVariant),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          minimumSize: const Size(double.infinity, 0),
        ),
      ),
    );
  }
}
