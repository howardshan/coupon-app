import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/providers/supabase_provider.dart';
import '../../data/models/deal_model.dart';
import '../../data/repositories/deals_repository.dart';

final dealsRepositoryProvider = Provider<DealsRepository>((ref) {
  return DealsRepository(ref.watch(supabaseClientProvider));
});

// Selected category filter
final selectedCategoryProvider = StateProvider<String>((ref) => 'All');

// Search query
final searchQueryProvider = StateProvider<String>((ref) => '');

// Featured deals
final featuredDealsProvider = FutureProvider<List<DealModel>>((ref) async {
  return ref.watch(dealsRepositoryProvider).fetchFeaturedDeals();
});

// Deals list with filters
final dealsListProvider =
    FutureProvider.family<List<DealModel>, int>((ref, page) async {
  final category = ref.watch(selectedCategoryProvider);
  final search = ref.watch(searchQueryProvider);
  return ref.watch(dealsRepositoryProvider).fetchDeals(
        category: category,
        search: search,
        page: page,
      );
});

// Single deal
final dealDetailProvider =
    FutureProvider.family<DealModel, String>((ref, dealId) async {
  return ref.watch(dealsRepositoryProvider).fetchDealById(dealId);
});
