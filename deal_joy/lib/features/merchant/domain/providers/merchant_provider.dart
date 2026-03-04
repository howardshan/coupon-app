import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/providers/supabase_provider.dart';
import '../../../deals/domain/providers/deals_provider.dart';
import '../../data/models/merchant_model.dart';
import '../../data/repositories/merchant_repository.dart';

final merchantRepositoryProvider = Provider<MerchantRepository>((ref) {
  return MerchantRepository(ref.watch(supabaseClientProvider));
});

/// 首页商家列表 — 按城市筛选
final merchantListProvider = FutureProvider<List<MerchantModel>>((ref) async {
  final city = ref.watch(selectedLocationProvider).city;
  return ref.watch(merchantRepositoryProvider).fetchMerchants(city: city);
});

/// 搜索商家 — 由 searchQueryProvider 驱动
final merchantSearchProvider = FutureProvider<List<MerchantModel>>((ref) async {
  final query = ref.watch(searchQueryProvider);
  if (query.isEmpty) return [];
  return ref.watch(merchantRepositoryProvider).searchMerchants(query);
});

/// 收藏商家 ID 集合（用于快速判断是否已收藏）
final savedMerchantIdsProvider = FutureProvider<Set<String>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final userId = client.auth.currentUser?.id;
  if (userId == null) return {};
  try {
    return ref.watch(merchantRepositoryProvider).fetchSavedMerchantIds(userId);
  } catch (_) {
    return {};
  }
});

/// 用户收藏的商家列表
final savedMerchantsProvider = FutureProvider<List<MerchantModel>>((ref) async {
  final repo = ref.watch(merchantRepositoryProvider);
  final client = ref.watch(supabaseClientProvider);
  final userId = client.auth.currentUser?.id;
  if (userId == null) return [];
  return repo.fetchSavedMerchants(userId);
});

/// 切换商家收藏状态
class SavedMerchantsNotifier extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncValue.data(null);

  Future<void> toggle(String merchantId) async {
    final client = ref.read(supabaseClientProvider);
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;

    final repo = ref.read(merchantRepositoryProvider);
    final savedIds = ref.read(savedMerchantIdsProvider).valueOrNull ?? {};

    state = const AsyncValue.loading();
    try {
      if (savedIds.contains(merchantId)) {
        await repo.unsaveMerchant(userId, merchantId);
      } else {
        await repo.saveMerchant(userId, merchantId);
      }
      // 刷新收藏列表
      ref.invalidate(savedMerchantIdsProvider);
      ref.invalidate(savedMerchantsProvider);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final savedMerchantsNotifierProvider =
    NotifierProvider<SavedMerchantsNotifier, AsyncValue<void>>(
      SavedMerchantsNotifier.new,
    );

/// 按 ID 列表获取商家（用于浏览历史）
final merchantsByIdsProvider =
    FutureProvider.family<List<MerchantModel>, List<String>>((ref, ids) async {
  if (ids.isEmpty) return [];
  return ref.watch(merchantRepositoryProvider).fetchMerchantsByIds(ids);
});
