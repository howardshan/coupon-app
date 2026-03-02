import 'dart:math' show asin, cos, sin, sqrt, pi;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../shared/providers/supabase_provider.dart';
import '../../data/models/deal_model.dart';
import '../../data/repositories/deals_repository.dart';

final dealsRepositoryProvider = Provider<DealsRepository>((ref) {
  return DealsRepository(ref.watch(supabaseClientProvider));
});

// 选中的城市
final selectedLocationProvider =
    StateProvider<({String state, String metro, String city})>(
      (ref) => (state: 'Texas', metro: 'DFW', city: 'Dallas'),
    );

// 选中的分类筛选
final selectedCategoryProvider = StateProvider<String>((ref) => 'All');

// 搜索关键词
final searchQueryProvider = StateProvider<String>((ref) => '');

// 精选 Deals（按城市过滤）
final featuredDealsProvider = FutureProvider<List<DealModel>>((ref) async {
  final city = ref.watch(selectedLocationProvider).city;
  return ref.watch(dealsRepositoryProvider).fetchFeaturedDeals(city: city);
});

// Deals 列表（含城市 + 分类 + 搜索筛选）
final dealsListProvider =
    FutureProvider.family<List<DealModel>, int>((ref, page) async {
  final city = ref.watch(selectedLocationProvider).city;
  final category = ref.watch(selectedCategoryProvider);
  final search = ref.watch(searchQueryProvider);
  return ref.watch(dealsRepositoryProvider).fetchDeals(
        city: city,
        category: category,
        search: search,
        page: page,
      );
});

// 单个 Deal 详情
final dealDetailProvider =
    FutureProvider.family<DealModel, String>((ref, dealId) async {
  return ref.watch(dealsRepositoryProvider).fetchDealById(dealId);
});

// ---- GPS 位置 Provider ----
// 获取当前 GPS 坐标，权限被拒则返回 Dallas 默认坐标
final userLocationProvider = FutureProvider<({double lat, double lng})>((ref) async {
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

/// 计算两点间距离（英里），Haversine 公式
double distanceMiles(double lat1, double lng1, double lat2, double lng2) {
  const earthRadiusMiles = 3958.8;
  final dLat = _toRad(lat2 - lat1);
  final dLng = _toRad(lng2 - lng1);
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(_toRad(lat1)) * cos(_toRad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
  final c = 2 * asin(sqrt(a));
  return earthRadiusMiles * c;
}

double _toRad(double deg) => deg * pi / 180;

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
        SavedDealsNotifier.new);
