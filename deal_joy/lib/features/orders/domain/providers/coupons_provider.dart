// 团购券 Riverpod Providers

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/providers/supabase_provider.dart';
import '../../../auth/domain/providers/auth_provider.dart';
import '../../data/models/coupon_model.dart';
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

/// 按状态过滤的团购券列表（derived provider）
/// Expired：仅「已过期且未退款」；Refunded：仅「已退款」；Unused：未使用且未过期
final couponsByStatusProvider =
    Provider.family<AsyncValue<List<CouponModel>>, String>((ref, status) {
  return ref.watch(userCouponsProvider).whenData((coupons) {
    if (status == 'expired') {
      return coupons.where((c) => c.isExpired && c.status != 'refunded').toList();
    }
    if (status == 'unused') {
      return coupons.where((c) => c.status == 'unused' && !c.isExpired).toList();
    }
    return coupons.where((c) => c.status == status).toList();
  });
});

/// 单张团购券详情 Provider（通过 couponId 查询）
final couponDetailProvider =
    FutureProvider.family<CouponModel, String>((ref, couponId) {
  return ref.watch(couponsRepositoryProvider).fetchCouponDetail(couponId);
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

/// 转赠操作 Notifier
class GiftNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

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
