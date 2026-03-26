import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/providers/supabase_provider.dart';
import '../../data/models/deal_model.dart';
import '../../data/repositories/recommendation_repository.dart';
import 'deals_provider.dart';

/// RecommendationRepository 实例 Provider
final recommendationRepositoryProvider =
    Provider<RecommendationRepository>((ref) {
  return RecommendationRepository(ref.watch(supabaseClientProvider));
});

/// 个性化推荐 Deal 列表 Provider
/// 使用 AsyncNotifier，在首页等场景加载推荐内容
class RecommendedDealsNotifier extends AsyncNotifier<List<DealModel>> {
  @override
  Future<List<DealModel>> build() async {
    return _loadRecommendations();
  }

  Future<List<DealModel>> _loadRecommendations() async {
    final repo = ref.read(recommendationRepositoryProvider);
    // 尝试读取 GPS 坐标（失败则传 null，服务端 fallback 到默认城市）
    double? lat;
    double? lng;
    try {
      final loc = await ref.read(userLocationProvider.future);
      lat = loc.lat;
      lng = loc.lng;
    } catch (_) {
      // 位置获取失败，不影响推荐请求
    }

    return repo.fetchRecommendations(lat: lat, lng: lng, limit: 20);
  }

  /// 手动刷新推荐列表
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_loadRecommendations);
  }
}

final recommendedDealsProvider =
    AsyncNotifierProvider<RecommendedDealsNotifier, List<DealModel>>(
  RecommendedDealsNotifier.new,
);
