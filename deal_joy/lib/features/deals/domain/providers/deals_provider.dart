import 'dart:math';

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

// 首页展示券：广告竞价赢家（Sponsored）优先，后接 sort_order 手动排序 deal
// Near Me / 城市模式均支持；跟随 selectedCategory 筛选（广告侧客户端过滤）
final featuredDealsProvider = FutureProvider<List<DealModel>>((ref) async {
  final repo = ref.watch(dealsRepositoryProvider);
  final isNearMe = ref.watch(isNearMeProvider);
  final category = ref.watch(selectedCategoryProvider);

  // 并发发起广告请求（失败时内部返回空列表，不影响手动排序内容）
  final sponsoredFuture = repo.fetchSponsoredDeals();

  final List<DealModel> manual;
  if (isNearMe) {
    final loc = await ref.watch(userLocationProvider.future);
    debugPrint('[DEBUG] featuredDealsProvider → Near Me GPS=(${loc.lat}, ${loc.lng}), category=$category');
    final allNearby = await repo.searchDealsNearby(
      lat: loc.lat,
      lng: loc.lng,
      radiusMeters: 32187,
      category: category,
    );
    manual = allNearby.where((d) => d.sortOrder != null).toList();
    debugPrint('[DEBUG] featuredDealsProvider → Near Me 手动 ${manual.length} 条');
  } else {
    final city = ref.watch(selectedLocationProvider).city;
    debugPrint('[DEBUG] featuredDealsProvider → 城市模式, city=$city, category=$category');
    manual = await repo.fetchFeaturedDeals(city: city, category: category);
    debugPrint('[DEBUG] featuredDealsProvider → 手动 ${manual.length} 条');
  }

  var sponsored = await sponsoredFuture;

  // 分类筛选：客户端过滤广告 deal 的 category 字段
  if (category != 'All' && category.isNotEmpty) {
    sponsored = sponsored
        .where((d) => d.category.toLowerCase() == category.toLowerCase())
        .toList();
  }

  // 去重：手动排序中排除已在广告列表里出现的 deal
  final sponsoredIds = sponsored.map((d) => d.id).toSet();
  final dedupedManual = manual.where((d) => !sponsoredIds.contains(d.id)).toList();

  debugPrint('[DEBUG] featuredDealsProvider → sponsored=${sponsored.length}, manual=${dedupedManual.length}');
  return [...sponsored, ...dedupedManual];
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

  // 搜索模式：
  // - 有 GPS 授权 → 搜全部城市，按距离+评分+boosted 排序，并写回 distanceMeters 显示
  // - 无 GPS 授权 → 只搜当前选中城市，按 featured+评分+销量 排序
  if (search.isNotEmpty) {
    final userLoc = await ref.watch(userLocationProvider.future);
    final hasGps = userLoc.lat != 0.0 || userLoc.lng != 0.0;
    final city = hasGps ? null : ref.watch(selectedLocationProvider).city;

    debugPrint('[DEBUG] dealsListProvider → 搜索模式, hasGps=$hasGps, city=$city, search="$search"');
    final results = await repo.fetchDeals(
      city: city,
      category: null,
      search: search,
      page: page,
    );

    // 有 GPS 时客户端算距离并写回 distanceMeters，同时按距离排序
    if (hasGps) {
      // Haversine 公式算距离 meters
      double calcMeters(DealModel d) {
        if (d.lat == null || d.lng == null) return double.infinity;
        final dLat = (d.lat! - userLoc.lat) * pi / 180;
        final dLng = (d.lng! - userLoc.lng) * pi / 180;
        final a2 = sin(dLat / 2) * sin(dLat / 2) +
            cos(userLoc.lat * pi / 180) *
            cos(d.lat! * pi / 180) *
            sin(dLng / 2) * sin(dLng / 2);
        return 2 * 6371000 * asin(sqrt(a2)); // 返回 meters
      }

      // 写回 distanceMeters 后排序
      final withDist = results.map((d) {
        final meters = calcMeters(d);
        return d.copyWithDistance(meters.isFinite ? meters : null);
      }).toList();

      withDist.sort((a, b) {
        // 1. featured / boosted 置顶
        final aFeatured = (a.isFeatured || a.isSponsored) ? 0 : 1;
        final bFeatured = (b.isFeatured || b.isSponsored) ? 0 : 1;
        if (aFeatured != bFeatured) return aFeatured.compareTo(bFeatured);

        // 2. 距离近→远（差距 > 160m ≈ 0.1 mile 才区分）
        final aDist = a.distanceMeters ?? double.infinity;
        final bDist = b.distanceMeters ?? double.infinity;
        if ((aDist - bDist).abs() > 160) return aDist.compareTo(bDist);

        // 3. 评分高→低
        if (a.rating != b.rating) return b.rating.compareTo(a.rating);

        // 4. 销量高→低
        return b.totalSold.compareTo(a.totalSold);
      });

      debugPrint('[DEBUG] dealsListProvider → 搜索返回 ${withDist.length} 条（含距离）');
      return withDist;
    }

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
  // 等待 GPS 权限/坐标解析完成，避免 valueOrNull 返回 null 导致距离缺失
  final userLoc = await ref.watch(userLocationProvider.future);

  return repo.searchDealsByCity(
    city: city,
    userLat: userLoc.lat,
    userLng: userLoc.lng,
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
// 获取当前 GPS 坐标，权限被拒或超时则返回 Dallas 默认坐标
final userLocationProvider = FutureProvider<({double lat, double lng})>((
  ref,
) async {
  try {
    return await _fetchUserLocation(ref).timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        debugPrint('[DEBUG] userLocationProvider → GPS 超时，使用 Dallas 默认坐标');
        ref.read(locationPermissionDeniedProvider.notifier).state = true;
        return (lat: AppConstants.dallasLat, lng: AppConstants.dallasLng);
      },
    );
  } catch (e) {
    debugPrint('[DEBUG] userLocationProvider → 异常: $e，使用 Dallas 默认坐标');
    return (lat: AppConstants.dallasLat, lng: AppConstants.dallasLng);
  }
});

Future<({double lat, double lng})> _fetchUserLocation(Ref ref) async {
  try {
    LocationPermission permission = await Geolocator.checkPermission();
    debugPrint('[DEBUG] userLocationProvider → checkPermission=$permission');
    // 不在 provider 内弹权限对话框，避免与 UI 层竞态；UI 层（postFrameCallback / banner）负责 requestPermission
    if (permission == LocationPermission.deniedForever ||
        permission == LocationPermission.denied) {
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
}

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

// ---- 数据库分类列表 Provider（动态替代硬编码 AppConstants.categoryItems）----
// 返回 categories 表全部记录（id, name, icon URL/emoji, order）
final dbCategoriesProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return ref.watch(dealsRepositoryProvider).fetchCategoriesFromDB();
});

// ---- 可用分类 Provider（首页隐藏空分类用）----
// 返回当前位置下有 active deal 的分类名集合
final availableCategoriesProvider = FutureProvider<Set<String>>((ref) async {
  final repo = ref.watch(dealsRepositoryProvider);
  final isNearMe = ref.watch(isNearMeProvider);
  // Near Me 模式不做城市过滤，返回全部有 deal 的分类
  final city = isNearMe ? null : ref.watch(selectedLocationProvider).city;
  return repo.fetchAvailableCategories(city: city);
});

// ---- 选项组选择状态 Provider ----
// 存储每个 deal 的选项选择：dealId -> { groupId: Set<itemId> }
// 用于在 deal 详情页的 _OptionGroupsSelector 和 _BottomBar 之间共享状态
final dealOptionSelectionsProvider =
    StateProvider.family<Map<String, Set<String>>, String>((ref, dealId) => {});
