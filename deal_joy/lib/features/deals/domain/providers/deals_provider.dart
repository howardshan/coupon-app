import 'package:flutter/foundation.dart';
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
// Near Me 模式用 GPS 半径过滤；城市模式按选中城市过滤
final featuredDealsProvider = FutureProvider<List<DealModel>>((ref) async {
  final repo = ref.watch(dealsRepositoryProvider);
  final isNearMe = ref.watch(isNearMeProvider);

  if (isNearMe) {
    // Near Me：用 searchDealsNearby RPC，只保留有 sort_order 的 deal
    final loc = await ref.watch(userLocationProvider.future);
    debugPrint('[DEBUG] featuredDealsProvider → Near Me GPS=(${loc.lat}, ${loc.lng})');
    final allNearby = await repo.searchDealsNearby(
      lat: loc.lat,
      lng: loc.lng,
      radiusMeters: 32187, // ~20 英里，和 store list 一致
    );
    final results = allNearby.where((d) => d.sortOrder != null).toList();
    debugPrint('[DEBUG] featuredDealsProvider → Near Me 返回 ${results.length} 条 (总nearby=${allNearby.length})');
    return results;
  }

  final city = ref.watch(selectedLocationProvider).city;
  debugPrint('[DEBUG] featuredDealsProvider → 城市模式, city=$city');
  final results = await repo.fetchFeaturedDeals(city: city);
  debugPrint('[DEBUG] featuredDealsProvider → 返回 ${results.length} 条');
  return results;
});

// Deals 列表（Near Me 用 GPS 搜索；城市模式用精确 city 匹配）
final dealsListProvider = FutureProvider.family<List<DealModel>, int>((
  ref,
  page,
) async {
  final isNearMe = ref.watch(isNearMeProvider);
  final category = ref.watch(selectedCategoryProvider);
  final repo = ref.watch(dealsRepositoryProvider);
  final search = ref.watch(searchQueryProvider);

  // 有搜索词时统一走 fetchDeals（支持 title/description/short_name 全文搜索）。
  // 注意：搜索时故意忽略 selectedCategoryProvider，避免用户之前选中的分类
  // 把与搜索词匹配的 deal 误过滤掉（UI 在搜索模式下也隐藏了分类选择器）。
  if (search.isNotEmpty) {
    final city = isNearMe ? null : ref.watch(selectedLocationProvider).city;
    debugPrint('[DEBUG] dealsListProvider → 搜索模式, city=$city, search="$search"');
    final results = await repo.fetchDeals(
      city: city,
      category: null,
      search: search,
      page: page,
    );
    debugPrint('[DEBUG] dealsListProvider → 搜索返回 ${results.length} 条');
    return results;
  }

  if (isNearMe) {
    final loc = await ref.watch(userLocationProvider.future);
    debugPrint('[DEBUG] dealsListProvider → Near Me 模式, GPS=(${loc.lat}, ${loc.lng}), category=$category');
    final results = await repo.searchDealsNearby(
      lat: loc.lat,
      lng: loc.lng,
      category: category,
      page: page,
    );
    debugPrint('[DEBUG] dealsListProvider → Near Me 返回 ${results.length} 条');
    return results;
  }

  final city = ref.watch(selectedLocationProvider).city;
  final userLoc = ref.watch(userLocationProvider).valueOrNull;

  return repo.searchDealsByCity(
    city: city,
    userLat: userLoc?.lat,
    userLng: userLoc?.lng,
    category: category,
    page: page,
  );
});

// 搜索无结果时的相似推荐 deal
final similarDealsProvider = FutureProvider<List<DealModel>>((ref) async {
  final repo = ref.watch(dealsRepositoryProvider);
  final city = ref.watch(selectedLocationProvider).city;
  return repo.fetchSimilarDeals(city: city);
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

// ---- GPS 权限状态 Provider ----
// 追踪位置权限是否被拒绝，用于在 Near Me 模式下显示提示条
final locationPermissionDeniedProvider = StateProvider<bool>((ref) => false);

// ---- GPS 位置 Provider ----
// 获取当前 GPS 坐标，权限被拒则返回 Dallas 默认坐标
final userLocationProvider = FutureProvider<({double lat, double lng})>((
  ref,
) async {
  try {
    LocationPermission permission = await Geolocator.checkPermission();
    debugPrint('[DEBUG] userLocationProvider → checkPermission=$permission');
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      debugPrint('[DEBUG] userLocationProvider → requestPermission 结果=$permission');
    }
    if (permission == LocationPermission.deniedForever ||
        permission == LocationPermission.denied) {
      // 权限被拒，标记状态并使用 Dallas 默认坐标
      debugPrint('[DEBUG] userLocationProvider → 权限被拒，使用 Dallas 默认坐标');
      ref.read(locationPermissionDeniedProvider.notifier).state = true;
      return (lat: AppConstants.dallasLat, lng: AppConstants.dallasLng);
    }
    // 权限已授予，清除拒绝标记
    ref.read(locationPermissionDeniedProvider.notifier).state = false;
    // 先尝试获取上次已知位置（毫秒级返回），避免 GPS 冷启动等待
    final lastKnown = await Geolocator.getLastKnownPosition();
    if (lastKnown != null) {
      debugPrint('[DEBUG] userLocationProvider → 使用缓存 GPS=(${lastKnown.latitude}, ${lastKnown.longitude})');
      // 后台异步获取 medium 精度位置，存入缓存，用户下拉刷新时生效
      _refreshPreciseLocation(ref);
      return (lat: lastKnown.latitude, lng: lastKnown.longitude);
    }
    // 没有缓存位置，用 low 精度快速获取
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.low,
        distanceFilter: 100,
      ),
    );
    debugPrint('[DEBUG] userLocationProvider → low 精度 GPS=(${position.latitude}, ${position.longitude})');
    // 后台异步获取 medium 精度位置，用户下拉刷新时生效
    _refreshPreciseLocation(ref);
    return (lat: position.latitude, lng: position.longitude);
  } catch (e) {
    debugPrint('[DEBUG] userLocationProvider → 异常: $e，使用 Dallas 默认坐标');
    return (lat: AppConstants.dallasLat, lng: AppConstants.dallasLng);
  }
});

// 后台异步获取 medium 精度 GPS，完成后缓存到 Geolocator 内部，
// 用户下拉刷新 invalidate userLocationProvider 时会通过 getLastKnownPosition 拿到更精确的值
void _refreshPreciseLocation(Ref ref) {
  Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.medium,
      distanceFilter: 100,
    ),
  ).then((pos) {
    debugPrint('[DEBUG] _refreshPreciseLocation → medium GPS=(${pos.latitude}, ${pos.longitude})');
  }).catchError((e) {
    debugPrint('[DEBUG] _refreshPreciseLocation → 失败: $e');
  });
}

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
