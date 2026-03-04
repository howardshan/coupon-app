// 营销工具 Riverpod Provider
// 使用 AsyncNotifier 模式管理营销工具状态
// 优先级: P2/V2 — Provider 结构完整，V2 时接入真实数据

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/marketing_models.dart';
import '../services/marketing_service.dart';

// ============================================================
// 聚合状态类
// ============================================================

/// 营销工具聚合状态
/// 统一管理三类营销工具的数据
class MarketingState {
  const MarketingState({
    this.flashDeals = const [],
    this.newCustomerOffers = const [],
    this.promotions = const [],
  });

  /// 限时折扣列表
  final List<FlashDeal> flashDeals;

  /// 新客特惠列表
  final List<NewCustomerOffer> newCustomerOffers;

  /// 满减活动列表
  final List<Promotion> promotions;

  /// 不可变更新
  MarketingState copyWith({
    List<FlashDeal>? flashDeals,
    List<NewCustomerOffer>? newCustomerOffers,
    List<Promotion>? promotions,
  }) {
    return MarketingState(
      flashDeals: flashDeals ?? this.flashDeals,
      newCustomerOffers: newCustomerOffers ?? this.newCustomerOffers,
      promotions: promotions ?? this.promotions,
    );
  }
}

// ============================================================
// Service Provider（依赖注入）
// ============================================================

/// MarketingService 的 Provider，方便测试时 override
final marketingServiceProvider = Provider<MarketingService>((ref) {
  return MarketingService();
});

// ============================================================
// MarketingNotifier — 聚合营销工具状态
// ============================================================

/// 营销工具主 Notifier
/// 管理 Flash Deals / New Customer Offers / Promotions 三类数据
///
/// TODO: V2 — 接入真实 MarketingService 方法
class MarketingNotifier extends AsyncNotifier<MarketingState> {
  @override
  Future<MarketingState> build() async {
    // TODO: V2 — 从 MarketingService 加载数据:
    // final service = ref.read(marketingServiceProvider);
    // final merchantId = ref.read(currentMerchantIdProvider);
    // final results = await Future.wait([
    //   service.getFlashDeals(merchantId),
    //   service.getNewCustomerOffers(merchantId),
    //   service.getPromotions(merchantId),
    // ]);
    // return MarketingState(
    //   flashDeals: results[0] as List<FlashDeal>,
    //   newCustomerOffers: results[1] as List<NewCustomerOffer>,
    //   promotions: results[2] as List<Promotion>,
    // );

    // V2 前返回空状态
    return const MarketingState();
  }

  /// 刷新所有营销数据
  ///
  /// TODO: V2 — 实现完整刷新逻辑
  Future<void> refresh() async {
    // TODO: V2 实现
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => build());
  }
}

/// 营销工具主 Provider
final marketingProvider =
    AsyncNotifierProvider<MarketingNotifier, MarketingState>(
  MarketingNotifier.new,
);

// ============================================================
// Flash Deals Provider
// ============================================================

/// 限时折扣 Notifier
///
/// TODO: V2 — 实现 CRUD 操作
class FlashDealsNotifier extends AsyncNotifier<List<FlashDeal>> {
  @override
  Future<List<FlashDeal>> build() async {
    // TODO: V2 — 从 MarketingService 加载数据
    return [];
  }

  /// 创建限时折扣活动
  ///
  /// TODO: V2 — 调用 MarketingService.createFlashDeal()
  Future<void> createFlashDeal(FlashDeal flashDeal) async {
    // TODO: V2 实现
    throw UnimplementedError('TODO: V2 — createFlashDeal');
  }

  /// 关闭限时折扣活动
  ///
  /// TODO: V2 — 调用 MarketingService.deleteFlashDeal()
  Future<void> deleteFlashDeal(String id) async {
    // TODO: V2 实现
    throw UnimplementedError('TODO: V2 — deleteFlashDeal');
  }
}

/// 限时折扣 Provider
final flashDealsProvider =
    AsyncNotifierProvider<FlashDealsNotifier, List<FlashDeal>>(
  FlashDealsNotifier.new,
);

// ============================================================
// New Customer Offers Provider
// ============================================================

/// 新客特惠 Notifier
///
/// TODO: V2 — 实现 CRUD 操作
class NewCustomerOffersNotifier extends AsyncNotifier<List<NewCustomerOffer>> {
  @override
  Future<List<NewCustomerOffer>> build() async {
    // TODO: V2 — 从 MarketingService 加载数据
    return [];
  }

  /// 创建新客特惠
  ///
  /// TODO: V2 — 调用 MarketingService.createNewCustomerOffer()
  Future<void> createNewCustomerOffer(NewCustomerOffer offer) async {
    // TODO: V2 实现
    throw UnimplementedError('TODO: V2 — createNewCustomerOffer');
  }

  /// 关闭新客特惠
  ///
  /// TODO: V2 — 调用 MarketingService.deleteNewCustomerOffer()
  Future<void> deleteNewCustomerOffer(String id) async {
    // TODO: V2 实现
    throw UnimplementedError('TODO: V2 — deleteNewCustomerOffer');
  }
}

/// 新客特惠 Provider
final newCustomerOffersProvider =
    AsyncNotifierProvider<NewCustomerOffersNotifier, List<NewCustomerOffer>>(
  NewCustomerOffersNotifier.new,
);

// ============================================================
// Promotions Provider
// ============================================================

/// 满减活动 Notifier
///
/// TODO: V2 — 实现 CRUD 操作
class PromotionsNotifier extends AsyncNotifier<List<Promotion>> {
  @override
  Future<List<Promotion>> build() async {
    // TODO: V2 — 从 MarketingService 加载数据
    return [];
  }

  /// 创建满减活动
  ///
  /// TODO: V2 — 调用 MarketingService.createPromotion()
  Future<void> createPromotion(Promotion promotion) async {
    // TODO: V2 实现
    throw UnimplementedError('TODO: V2 — createPromotion');
  }

  /// 关闭满减活动
  ///
  /// TODO: V2 — 调用 MarketingService.deletePromotion()
  Future<void> deletePromotion(String id) async {
    // TODO: V2 实现
    throw UnimplementedError('TODO: V2 — deletePromotion');
  }
}

/// 满减活动 Provider
final promotionsProvider =
    AsyncNotifierProvider<PromotionsNotifier, List<Promotion>>(
  PromotionsNotifier.new,
);
