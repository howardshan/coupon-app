import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../shared/providers/supabase_provider.dart';
import '../../data/models/deal_model.dart';
import '../../data/models/review_model.dart';
import '../../data/repositories/deals_repository.dart';

final dealsRepositoryProvider = Provider<DealsRepository>((ref) {
  return DealsRepository(ref.watch(supabaseClientProvider));
});

// 选中的城市
final selectedLocationProvider =
    StateProvider<({String state, String metro, String city})>(
      (ref) => (state: 'Texas', metro: 'DFW', city: 'Dallas'),
    );

// Near Me 模式开关（true = GPS 半径搜索；false = 城市精确匹配）
final isNearMeProvider = StateProvider<bool>((ref) => false);

// 选中的分类筛选
final selectedCategoryProvider = StateProvider<String>((ref) => 'All');

// 搜索关键词
final searchQueryProvider = StateProvider<String>((ref) => '');

// 首页展示券：sort_order 不为空的 active deal，按 sort_order 升序
final featuredDealsProvider = FutureProvider<List<DealModel>>((ref) async {
  final repo = ref.watch(dealsRepositoryProvider);
  return repo.fetchFeaturedDeals();
});

// Deals 列表（Near Me 用 GPS 搜索；城市模式用精确 city 匹配）
final dealsListProvider = FutureProvider.family<List<DealModel>, int>((
  ref,
  page,
) async {
  final isNearMe = ref.watch(isNearMeProvider);
  final category = ref.watch(selectedCategoryProvider);
  final repo = ref.watch(dealsRepositoryProvider);

  if (isNearMe) {
    final loc = await ref.watch(userLocationProvider.future);
    return repo.searchDealsNearby(
      lat: loc.lat,
      lng: loc.lng,
      category: category,
      page: page,
    );
  }

  final city = ref.watch(selectedLocationProvider).city;
  final userLoc = ref.watch(userLocationProvider).valueOrNull;
  final search = ref.watch(searchQueryProvider);

  // 有搜索词时退回旧接口（支持全文搜索）
  if (search.isNotEmpty) {
    return repo.fetchDeals(
        city: city, category: category, search: search, page: page);
  }

  return repo.searchDealsByCity(
    city: city,
    userLat: userLoc?.lat,
    userLng: userLoc?.lng,
    category: category,
    page: page,
  );
});

// 单个 Deal 详情
final dealDetailProvider = FutureProvider.family<DealModel, String>((
  ref,
  dealId,
) async {
  return ref.watch(dealsRepositoryProvider).fetchDealById(dealId);
});

// Other deals from the same merchant
final merchantDealsProvider =
    FutureProvider.family<
      List<DealModel>,
      ({String merchantId, String excludeDealId})
    >((ref, params) async {
      return ref
          .watch(dealsRepositoryProvider)
          .fetchDealsByMerchant(
            params.merchantId,
            excludeDealId: params.excludeDealId,
          );
    });

// Reviews for a specific deal
final dealReviewsProvider = FutureProvider.family<List<ReviewModel>, String>((
  ref,
  dealId,
) async {
  return ref.watch(dealsRepositoryProvider).fetchReviewsByDeal(dealId);
});

// ---- GPS 位置 Provider ----
// 获取当前 GPS 坐标，权限被拒则返回 Dallas 默认坐标
final userLocationProvider = FutureProvider<({double lat, double lng})>((
  ref,
) async {
  try {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever ||
        permission == LocationPermission.denied) {
      // 权限被拒，使用 Dallas 默认坐标
      return (lat: AppConstants.dallasLat, lng: AppConstants.dallasLng);
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: 100,
      ),
    );
    return (lat: position.latitude, lng: position.longitude);
  } catch (_) {
    return (lat: AppConstants.dallasLat, lng: AppConstants.dallasLng);
  }
});

// Haversine 距离计算已提取到 core/utils/location_utils.dart
// 使用 haversineDistanceMiles() 替代原 distanceMiles()

// ---- 收藏 Deals Provider ----
// 收藏 ID 集合，用于快速检查是否已收藏
final savedDealIdsProvider = FutureProvider<Set<String>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final userId = client.auth.currentUser?.id;
  if (userId == null) return {};
  try {
    final data = await client
        .from('saved_deals')
        .select('deal_id')
        .eq('user_id', userId);
    return (data as List).map((e) => e['deal_id'] as String).toSet();
  } catch (_) {
    return {};
  }
});

// 用户收藏的 Deal 列表
final savedDealsListProvider = FutureProvider<List<DealModel>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final userId = client.auth.currentUser?.id;
  if (userId == null) return [];
  return ref.watch(dealsRepositoryProvider).fetchSavedDeals(userId);
});

// 切换收藏状态
class SavedDealsNotifier extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncValue.data(null);

  Future<void> toggle(String dealId) async {
    final client = ref.read(supabaseClientProvider);
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;

    final repo = ref.read(dealsRepositoryProvider);
    final savedIds = ref.read(savedDealIdsProvider).valueOrNull ?? {};

    state = const AsyncValue.loading();
    try {
      if (savedIds.contains(dealId)) {
        await repo.unsaveDeal(userId, dealId);
      } else {
        await repo.saveDeal(userId, dealId);
      }
      // 刷新收藏列表
      ref.invalidate(savedDealIdsProvider);
      ref.invalidate(savedDealsListProvider);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final savedDealsNotifierProvider =
    NotifierProvider<SavedDealsNotifier, AsyncValue<void>>(
      SavedDealsNotifier.new,
    );

// ---- 选项组选择状态 Provider ----
// 存储每个 deal 的选项选择：dealId -> { groupId: Set<itemId> }
// 用于在 deal 详情页的 _OptionGroupsSelector 和 _BottomBar 之间共享状态
final dealOptionSelectionsProvider =
    StateProvider.family<Map<String, Set<String>>, String>((ref, dealId) => {});
