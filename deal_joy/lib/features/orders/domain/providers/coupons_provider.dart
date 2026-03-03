// 团购券 Riverpod Providers

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/providers/supabase_provider.dart';
import '../../../auth/domain/providers/auth_provider.dart';
import '../../data/models/coupon_model.dart';
import '../../data/repositories/coupons_repository.dart';
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
/// 使用 .family 让状态字符串作为参数
final couponsByStatusProvider =
    Provider.family<AsyncValue<List<CouponModel>>, String>((ref, status) {
  return ref.watch(userCouponsProvider).whenData(
        (coupons) =>
            coupons.where((c) => c.status == status).toList(),
      );
});

/// 单张团购券详情 Provider（通过 couponId 查询）
final couponDetailProvider =
    FutureProvider.family<CouponModel, String>((ref, couponId) {
  return ref.watch(couponsRepositoryProvider).fetchCouponDetail(couponId);
});

/// 退款操作 Notifier
class RefundNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// 通过 couponId 请求退款（券详情页使用）
  Future<bool> requestRefund(String couponId, {String? reason}) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref
          .read(couponsRepositoryProvider)
          .requestRefund(couponId, reason: reason),
    );
    if (!state.hasError) {
      // 刷新券列表和订单列表
      ref.invalidate(userCouponsProvider);
      ref.invalidate(couponDetailProvider(couponId));
      ref.invalidate(userOrdersProvider);
    }
    return !state.hasError;
  }

  /// 通过 orderId 请求退款（订单列表/退款页使用）
  Future<bool> requestRefundByOrderId(String orderId,
      {String? reason}) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref
          .read(couponsRepositoryProvider)
          .requestRefundByOrderId(orderId, reason: reason),
    );
    if (!state.hasError) {
      // 刷新券列表和订单列表
      ref.invalidate(userCouponsProvider);
      ref.invalidate(userOrdersProvider);
      ref.invalidate(orderDetailProvider(orderId));
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
