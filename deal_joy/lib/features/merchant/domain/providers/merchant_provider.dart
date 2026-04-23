import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/providers/supabase_provider.dart';
import '../../../deals/domain/providers/deals_provider.dart';
import '../../data/models/brand_detail_model.dart';
import '../../data/models/merchant_model.dart';
import '../../data/repositories/merchant_repository.dart';

final merchantRepositoryProvider = Provider<MerchantRepository>((ref) {
  return MerchantRepository(ref.watch(supabaseClientProvider));
});

/// 首页商家列表 — Near Me 时按 GPS 半径搜索；否则按城市 + 分类筛选
/// 广告竞价赢家（home_store_top）置顶，带 Sponsored 标签
final merchantListProvider = FutureProvider<List<MerchantModel>>((ref) async {
  final isNearMe = ref.watch(isNearMeProvider);
  final category = ref.watch(selectedCategoryProvider);
  final repo = ref.watch(merchantRepositoryProvider);

  // 并发发起广告请求（失败时内部返回空列表，不影响主内容）
  final sponsoredFuture = repo.fetchSponsoredMerchants();

  final List<MerchantModel> merchants;
  if (isNearMe) {
    final loc = await ref.watch(userLocationProvider.future);
    debugPrint('[DEBUG] merchantListProvider → Near Me 模式, GPS=(${loc.lat}, ${loc.lng}), category=$category');
    final results = await repo.fetchMerchantsNearby(
      lat: loc.lat,
      lng: loc.lng,
      category: category,
    );
    debugPrint('[DEBUG] merchantListProvider → Near Me 返回 ${results.length} 家店');
    merchants = results;
  } else {
    final city = ref.watch(selectedLocationProvider).city;
    debugPrint('[DEBUG] merchantListProvider → 城市模式, city=$city, category=$category');
    // 等待 GPS 解析完毕，用于客户端计算并写回距离
    final userLoc = await ref.watch(userLocationProvider.future);
    // 权限被拒时 userLoc 是 Dallas 默认坐标，不应显示距离
    final permDenied = ref.watch(locationPermissionDeniedProvider);
    final hasGps = !permDenied && (userLoc.lat != 0.0 || userLoc.lng != 0.0);
    final results = await repo.fetchMerchants(city: city, category: category);
    debugPrint('[DEBUG] merchantListProvider → 城市模式返回 ${results.length} 家店');

    // 有 GPS 时客户端计算 Haversine 距离并写回 distanceMiles
    if (hasGps) {
      double calcMiles(MerchantModel m) {
        if (m.lat == null || m.lng == null) return double.infinity;
        final dLat = (m.lat! - userLoc.lat) * pi / 180;
        final dLng = (m.lng! - userLoc.lng) * pi / 180;
        final a2 = sin(dLat / 2) * sin(dLat / 2) +
            cos(userLoc.lat * pi / 180) *
            cos(m.lat! * pi / 180) *
            sin(dLng / 2) * sin(dLng / 2);
        return 2 * 6371000 * asin(sqrt(a2)) / 1609.34; // 转英里
      }
      merchants = results.map((m) {
        final miles = calcMiles(m);
        return m.copyWith(distanceMiles: miles.isFinite ? miles : null);
      }).toList();
    } else {
      merchants = results;
    }
  }

  var sponsored = await sponsoredFuture;

  // 分类筛选：客户端过滤广告商家的 primaryCategory
  if (category != 'All' && category.isNotEmpty) {
    sponsored = sponsored
        .where((m) => m.primaryCategory?.toLowerCase() == category.toLowerCase())
        .toList();
  }

  // 去重：普通列表中排除已在广告列表里出现的商家
  final sponsoredIds = sponsored.map((m) => m.id).toSet();
  final dedupedMerchants = merchants.where((m) => !sponsoredIds.contains(m.id)).toList();

  debugPrint('[DEBUG] merchantListProvider → sponsored=${sponsored.length}, merchants=${dedupedMerchants.length}');
  return [...sponsored, ...dedupedMerchants];
});

/// 搜索商家 — 由 searchQueryProvider 驱动，有 GPS 时写回 distanceMiles 并按距离排序
final merchantSearchProvider = FutureProvider<List<MerchantModel>>((ref) async {
  final query = ref.watch(searchQueryProvider);
  if (query.isEmpty) return [];

  final results = await ref.watch(merchantRepositoryProvider).searchMerchants(query);

  // 尝试获取 GPS（非阻塞方式，若已缓存则直接返回）
  final userLoc = await ref.watch(userLocationProvider.future);
  // 权限被拒时 userLoc 是 Dallas 默认坐标，不应显示距离
  final permDenied = ref.watch(locationPermissionDeniedProvider);
  final hasGps = !permDenied && (userLoc.lat != 0.0 || userLoc.lng != 0.0);

  if (!hasGps) return results;

  // 有 GPS：客户端 Haversine 计算距离 → 写回 distanceMiles → 按距离排序
  double calcMiles(MerchantModel m) {
    if (m.lat == null || m.lng == null) return double.infinity;
    final dLat = (m.lat! - userLoc.lat) * pi / 180;
    final dLng = (m.lng! - userLoc.lng) * pi / 180;
    final a2 = sin(dLat / 2) * sin(dLat / 2) +
        cos(userLoc.lat * pi / 180) *
        cos(m.lat! * pi / 180) *
        sin(dLng / 2) * sin(dLng / 2);
    return 2 * 6371000 * asin(sqrt(a2)) / 1609.34; // 转英里
  }

  final withDist = results.map((m) {
    final miles = calcMiles(m);
    return m.copyWith(distanceMiles: miles.isFinite ? miles : null);
  }).toList();

  // 按距离近→远排序
  withDist.sort((a, b) {
    final aDist = a.distanceMiles ?? double.infinity;
    final bDist = b.distanceMiles ?? double.infinity;
    return aDist.compareTo(bDist);
  });

  debugPrint('[DEBUG] merchantSearchProvider → 搜索返回 ${withDist.length} 家店（含距离）');
  return withDist;
});

/// 搜索无结果时的相似推荐商家
final similarMerchantsProvider = FutureProvider<List<MerchantModel>>((ref) async {
  final city = ref.watch(selectedLocationProvider).city;
  return ref.watch(merchantRepositoryProvider).fetchSimilarMerchants(city: city);
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

// ============================================================
// V2.4 品牌聚合页 Provider
// ============================================================

/// 品牌详情（含旗下门店列表 + 聚合数据）
final brandDetailProvider =
    FutureProvider.family<BrandDetailModel, String>((ref, brandId) async {
  return ref.watch(merchantRepositoryProvider).fetchBrandDetail(brandId);
});
