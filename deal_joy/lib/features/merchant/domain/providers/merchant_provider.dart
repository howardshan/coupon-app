import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/providers/supabase_provider.dart';
import '../../../deals/domain/providers/deals_provider.dart';
import '../../data/models/merchant_model.dart';
import '../../data/repositories/merchant_repository.dart';

final merchantRepositoryProvider = Provider<MerchantRepository>((ref) {
  return MerchantRepository(ref.watch(supabaseClientProvider));
});

/// 首页商家列表 — 按城市筛选
final merchantListProvider =
    FutureProvider<List<MerchantModel>>((ref) async {
  final city = ref.watch(selectedLocationProvider).city;
  return ref.watch(merchantRepositoryProvider).fetchMerchants(city: city);
});

/// 搜索商家 — 由 searchQueryProvider 驱动
final merchantSearchProvider =
    FutureProvider<List<MerchantModel>>((ref) async {
  final query = ref.watch(searchQueryProvider);
  if (query.isEmpty) return [];
  return ref.watch(merchantRepositoryProvider).searchMerchants(query);
});
