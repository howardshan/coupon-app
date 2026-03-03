import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/providers/deals_provider.dart';
import '../../../merchant/domain/providers/merchant_provider.dart';
import '../widgets/collection_cards.dart';

class SavedDealsScreen extends StatelessWidget {
  const SavedDealsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('My Collection'),
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
          children: [_SavedDealsTab(), _SavedStoresTab()],
        ),
      ),
    );
  }
}

// ── Deals tab ─────────────────────────────────────────────────
class _SavedDealsTab extends ConsumerWidget {
  const _SavedDealsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dealsAsync = ref.watch(savedDealsListProvider);

    return dealsAsync.when(
      data: (deals) => deals.isEmpty
          ? CollectionEmptyState(
              icon: Icons.star_border_outlined,
              message: 'No saved deals yet',
              hint: 'Tap the heart icon on any deal to save it',
              onExplore: () => context.go('/home'),
            )
          : RefreshIndicator(
              onRefresh: () async => ref.invalidate(savedDealsListProvider),
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: deals.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (_, i) => DealListCard(deal: deals[i]),
              ),
            ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}

// ── Stores tab ────────────────────────────────────────────────
class _SavedStoresTab extends ConsumerWidget {
  const _SavedStoresTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storesAsync = ref.watch(savedMerchantsProvider);

    return storesAsync.when(
      data: (stores) => stores.isEmpty
          ? CollectionEmptyState(
              icon: Icons.store_outlined,
              message: 'No saved stores yet',
              hint: 'Follow your favorite restaurants',
              onExplore: () => context.go('/home'),
            )
          : RefreshIndicator(
              onRefresh: () async => ref.invalidate(savedMerchantsProvider),
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: stores.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (_, i) => MerchantListCard(merchant: stores[i]),
              ),
            ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}
