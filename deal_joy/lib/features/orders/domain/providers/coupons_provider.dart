// 团购券 Riverpod Providers

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../shared/providers/supabase_provider.dart';
import '../../../auth/domain/providers/auth_provider.dart';
import '../../data/models/coupon_model.dart';
import '../../data/models/coupon_gift_model.dart';
import '../../data/repositories/coupons_repository.dart';
import '../../../profile/domain/providers/store_credit_provider.dart';
import 'orders_provider.dart';

/// CouponsRepository Provider
final couponsRepositoryProvider = Provider<CouponsRepository>((ref) {
  return CouponsRepository(ref.watch(supabaseClientProvider));
});

/// 当前用户全部团购券
final userCouponsProvider = FutureProvider<List<CouponModel>>((ref) async {
  final user = await ref.watch(currentUserProvider.future);
  if (user == null) return [];
  return ref.watch(couponsRepositoryProvider).fetchUserCoupons(user.id);
});

/// 用户已评价的 deal ID 集合（用于 To Review tab 过滤）
final reviewedDealIdsProvider = FutureProvider<Set<String>>((ref) async {
  final client = Supabase.instance.client;
  final userId = client.auth.currentUser?.id;
  if (userId == null) return {};
  final data = await client
      .from('reviews')
      .select('deal_id')
      .eq('user_id', userId);
  return (data as List).map((r) => r['deal_id'] as String).toSet();
});

/// 按状态过滤的团购券列表（derived provider）
/// unused: 未使用且未过期
/// used: 已核销
/// to_review: 已核销且未评价
/// expired: 已过期（含过期后退款的 "Expired Return"）
/// returned: 未过期就退款的
/// cancelled: 已作废 (voided)
final couponsByStatusProvider =
    Provider.family<AsyncValue<List<CouponModel>>, String>((ref, status) {
  if (status == 'to_review') {
    // to_review 需要同时等待 coupons 和 reviewedDealIds
    final couponsAsync = ref.watch(userCouponsProvider);
    final reviewedAsync = ref.watch(reviewedDealIdsProvider);
    return couponsAsync.whenData((coupons) {
      final reviewedIds = reviewedAsync.valueOrNull ?? {};
      return coupons
          .where((c) =>
              c.status == 'used' &&
              c.dealId.isNotEmpty &&
              !reviewedIds.contains(c.dealId))
          .toList();
    });
  }

  return ref.watch(userCouponsProvider).whenData((coupons) {
    switch (status) {
      case 'unused':
        // 排除：已过期、已退款（refundedAt 有值）、无 order_item 的孤儿券
        return coupons.where((c) =>
            c.status == 'unused' && !c.isExpired &&
            c.refundedAt == null && c.orderItemId != null).toList();
      case 'used':
        return coupons.where((c) => c.status == 'used').toList();
      case 'expired':
        // 已过期的（不含 voided），全部都是 Expired Return（过期自动退款）
        return coupons.where((c) =>
            c.isExpired && c.status != 'voided').toList();
      case 'refunded':
        // 未过期就主动退款的
        return coupons.where((c) =>
            c.status == 'refunded' && !c.isExpired).toList();
      case 'gifted':
        return coupons.where((c) => c.status == 'voided' && c.voidReason == 'gifted').toList();
      default:
        return coupons.where((c) => c.status == status).toList();
    }
  });
});


/// 单张团购券详情 Provider（通过 couponId 查询）
final couponDetailProvider =
    FutureProvider.family<CouponModel, String>((ref, couponId) {
  return ref.watch(couponsRepositoryProvider).fetchCouponDetail(couponId);
});

/// 查询某个 order_item 的活跃赠送记录（pending/claimed）
final activeGiftProvider =
    FutureProvider.family<CouponGiftModel?, String>((ref, orderItemId) {
  return ref.watch(couponsRepositoryProvider).fetchActiveGift(orderItemId);
});

/// 根据门店 ID 列表查询门店基本信息（名称+地址），用于券详情页展示可用门店
final applicableStoresProvider =
    FutureProvider.family<List<Map<String, String>>, List<String>>((ref, storeIds) async {
  if (storeIds.isEmpty) return [];
  final client = ref.watch(supabaseClientProvider);
  final data = await client
      .from('merchants')
      .select('id, name, address')
      .inFilter('id', storeIds);
  return (data as List).map((e) {
    final m = e as Map<String, dynamic>;
    return {
      'id': m['id'] as String? ?? '',
      'name': m['name'] as String? ?? '',
      'address': m['address'] as String? ?? '',
    };
  }).toList();
});

/// 退款操作 Notifier
class RefundNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// 通过 couponId 请求退款（券详情页使用）
  /// [refundMethod] 退款方式：'store_credit' | 'original_payment'，默认 'original_payment'
  Future<bool> requestRefund(
    String couponId, {
    String? reason,
    String refundMethod = 'original_payment',
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref
          .read(couponsRepositoryProvider)
          .requestRefund(couponId, reason: reason, refundMethod: refundMethod),
    );
    if (!state.hasError) {
      // 刷新券列表、订单列表和 store credit 余额
      ref.invalidate(userCouponsProvider);
      ref.invalidate(couponDetailProvider(couponId));
      ref.invalidate(userOrdersProvider);
      ref.invalidate(storeCreditBalanceProvider);
      ref.invalidate(storeCreditTransactionsProvider);
    }
    return !state.hasError;
  }

  /// V3：通过 orderItemId 直接请求退款（订单详情页 item 维度退款）
  /// [refundMethod] 退款方式：'store_credit' | 'original_payment'，默认 'original_payment'
  Future<bool> requestItemRefund(
    String orderItemId, {
    String refundMethod = 'original_payment',
    String? reason,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref
          .read(couponsRepositoryProvider)
          .requestRefundByItemId(
            orderItemId,
            refundMethod: refundMethod,
            reason: reason,
          ),
    );
    if (!state.hasError) {
      // 刷新券列表、订单列表和 store credit 余额
      ref.invalidate(userCouponsProvider);
      ref.invalidate(userOrdersProvider);
      ref.invalidate(storeCreditBalanceProvider);
      ref.invalidate(storeCreditTransactionsProvider);
    }
    return !state.hasError;
  }

  /// 通过 orderId 请求退款（旧版订单列表/退款页使用，向后兼容）
  Future<bool> requestRefundByOrderId(String orderId,
      {String? reason}) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref
          .read(couponsRepositoryProvider)
          .requestRefundByOrderId(orderId, reason: reason),
    );
    if (!state.hasError) {
      // 刷新券列表、订单列表和 store credit 余额
      ref.invalidate(userCouponsProvider);
      ref.invalidate(userOrdersProvider);
      ref.invalidate(orderDetailProvider(orderId));
      ref.invalidate(storeCreditBalanceProvider);
      ref.invalidate(storeCreditTransactionsProvider);
    }
    return !state.hasError;
  }
}

final refundNotifierProvider =
    AsyncNotifierProvider<RefundNotifier, void>(RefundNotifier.new);

/// 转赠操作 Notifier（V2: 支持 email/phone/message + recall + edit）
class GiftNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// 发起赠送 — 通过 send-gift Edge Function
  Future<bool> sendGift({
    required String orderItemId,
    String? recipientEmail,
    String? recipientPhone,
    String? giftMessage,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(couponsRepositoryProvider).sendGift(
            orderItemId: orderItemId,
            recipientEmail: recipientEmail,
            recipientPhone: recipientPhone,
            giftMessage: giftMessage,
          ),
    );
    if (!state.hasError) {
      ref.invalidate(userCouponsProvider);
      ref.invalidate(userOrdersProvider);
    }
    return !state.hasError;
  }

  /// 撤回赠送
  Future<bool> recallGift(String giftId) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(couponsRepositoryProvider).recallGift(giftId),
    );
    if (!state.hasError) {
      ref.invalidate(userCouponsProvider);
      ref.invalidate(userOrdersProvider);
    }
    return !state.hasError;
  }

  /// 旧版兼容：通过 couponId + email 赠送
  Future<bool> giftCoupon(String couponId, String recipientEmail) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref
          .read(couponsRepositoryProvider)
          .giftCoupon(couponId, recipientEmail),
    );
    if (!state.hasError) {
      ref.invalidate(userCouponsProvider);
      ref.invalidate(couponDetailProvider(couponId));
    }
    return !state.hasError;
  }
}

final giftNotifierProvider =
    AsyncNotifierProvider<GiftNotifier, void>(GiftNotifier.new);
