// 营销工具服务层
// 封装与 Supabase 的数据交互，调用 merchant-marketing Edge Function
// 优先级: P2/V2 — 方法存根，V2 实现完整业务逻辑

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/marketing_models.dart';

/// 营销工具服务
/// 负责与后端 merchant-marketing Edge Function 以及 Supabase 直接查询交互
class MarketingService {
  MarketingService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  // ignore: unused_field — V2 时所有方法存根将替换为真实 API 调用
  final SupabaseClient _client;

  // ============================================================
  // Flash Deals — 限时折扣
  // ============================================================

  /// 获取商家的所有限时折扣活动
  ///
  /// TODO: V2 — 调用 Edge Function GET /merchant-marketing/flash-deals
  /// 返回包含关联 deal 信息的列表
  Future<List<FlashDeal>> getFlashDeals(String merchantId) async {
    // TODO: V2 实现:
    // final response = await _client.functions.invoke(
    //   'merchant-marketing',
    //   method: HttpMethod.get,
    //   headers: {'x-resource': 'flash-deals'},
    // );
    // return (response.data['data'] as List)
    //     .map((e) => FlashDeal.fromJson(e))
    //     .toList();
    return [];
  }

  /// 创建限时折扣活动
  ///
  /// TODO: V2 — 调用 Edge Function POST /merchant-marketing/flash-deals
  /// [flashDeal] 不含 id、createdAt、updatedAt（由服务端生成）
  Future<FlashDeal> createFlashDeal(FlashDeal flashDeal) async {
    // TODO: V2 实现:
    // final response = await _client.functions.invoke(
    //   'merchant-marketing',
    //   method: HttpMethod.post,
    //   headers: {'x-resource': 'flash-deals'},
    //   body: {
    //     'deal_id': flashDeal.dealId,
    //     'discount_percentage': flashDeal.discountPercentage,
    //     'start_time': flashDeal.startTime.toIso8601String(),
    //     'end_time': flashDeal.endTime.toIso8601String(),
    //   },
    // );
    // return FlashDeal.fromJson(response.data['data']);
    throw UnimplementedError('TODO: V2 — createFlashDeal not implemented');
  }

  /// 关闭限时折扣活动（将 is_active 置为 false）
  ///
  /// TODO: V2 — 调用 Edge Function DELETE /merchant-marketing/flash-deals/:id
  Future<void> deleteFlashDeal(String id) async {
    // TODO: V2 实现:
    // await _client.functions.invoke(
    //   'merchant-marketing',
    //   method: HttpMethod.delete,
    //   headers: {'x-resource': 'flash-deals', 'x-resource-id': id},
    // );
    throw UnimplementedError('TODO: V2 — deleteFlashDeal not implemented');
  }

  // ============================================================
  // New Customer Offers — 新客特惠
  // ============================================================

  /// 获取商家的所有新客特惠
  ///
  /// TODO: V2 — 调用 Edge Function GET /merchant-marketing/new-customer-offers
  Future<List<NewCustomerOffer>> getNewCustomerOffers(String merchantId) async {
    // TODO: V2 实现:
    // final response = await _client.functions.invoke(
    //   'merchant-marketing',
    //   method: HttpMethod.get,
    //   headers: {'x-resource': 'new-customer-offers'},
    // );
    // return (response.data['data'] as List)
    //     .map((e) => NewCustomerOffer.fromJson(e))
    //     .toList();
    return [];
  }

  /// 为指定 Deal 创建新客特惠
  ///
  /// TODO: V2 — 调用 Edge Function POST /merchant-marketing/new-customer-offers
  /// 后端会校验 specialPrice < Deal 原价
  Future<NewCustomerOffer> createNewCustomerOffer(
    NewCustomerOffer offer,
  ) async {
    // TODO: V2 实现:
    // final response = await _client.functions.invoke(
    //   'merchant-marketing',
    //   method: HttpMethod.post,
    //   headers: {'x-resource': 'new-customer-offers'},
    //   body: {
    //     'deal_id': offer.dealId,
    //     'special_price': offer.specialPrice,
    //   },
    // );
    // return NewCustomerOffer.fromJson(response.data['data']);
    throw UnimplementedError(
      'TODO: V2 — createNewCustomerOffer not implemented',
    );
  }

  /// 关闭新客特惠（将 is_active 置为 false）
  ///
  /// TODO: V2 — 调用 Edge Function DELETE /merchant-marketing/new-customer-offers/:id
  Future<void> deleteNewCustomerOffer(String id) async {
    // TODO: V2 实现:
    // await _client.functions.invoke(
    //   'merchant-marketing',
    //   method: HttpMethod.delete,
    //   headers: {'x-resource': 'new-customer-offers', 'x-resource-id': id},
    // );
    throw UnimplementedError(
      'TODO: V2 — deleteNewCustomerOffer not implemented',
    );
  }

  // ============================================================
  // Promotions — 满减活动
  // ============================================================

  /// 获取商家的所有满减活动
  ///
  /// TODO: V2 — 调用 Edge Function GET /merchant-marketing/promotions
  Future<List<Promotion>> getPromotions(String merchantId) async {
    // TODO: V2 实现:
    // final response = await _client.functions.invoke(
    //   'merchant-marketing',
    //   method: HttpMethod.get,
    //   headers: {'x-resource': 'promotions'},
    // );
    // return (response.data['data'] as List)
    //     .map((e) => Promotion.fromJson(e))
    //     .toList();
    return [];
  }

  /// 创建满减活动
  ///
  /// TODO: V2 — 调用 Edge Function POST /merchant-marketing/promotions
  /// 后端会校验 discountAmount < minSpend
  Future<Promotion> createPromotion(Promotion promotion) async {
    // TODO: V2 实现:
    // final response = await _client.functions.invoke(
    //   'merchant-marketing',
    //   method: HttpMethod.post,
    //   headers: {'x-resource': 'promotions'},
    //   body: {
    //     'deal_id': promotion.dealId,
    //     'min_spend': promotion.minSpend,
    //     'discount_amount': promotion.discountAmount,
    //     'title': promotion.title,
    //     'description': promotion.description,
    //     'start_time': promotion.startTime?.toIso8601String(),
    //     'end_time': promotion.endTime?.toIso8601String(),
    //   },
    // );
    // return Promotion.fromJson(response.data['data']);
    throw UnimplementedError('TODO: V2 — createPromotion not implemented');
  }

  /// 关闭满减活动（将 is_active 置为 false）
  ///
  /// TODO: V2 — 调用 Edge Function DELETE /merchant-marketing/promotions/:id
  Future<void> deletePromotion(String id) async {
    // TODO: V2 实现:
    // await _client.functions.invoke(
    //   'merchant-marketing',
    //   method: HttpMethod.delete,
    //   headers: {'x-resource': 'promotions', 'x-resource-id': id},
    // );
    throw UnimplementedError('TODO: V2 — deletePromotion not implemented');
  }
}
