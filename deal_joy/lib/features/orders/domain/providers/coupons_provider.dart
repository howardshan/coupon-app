// 团购券 Riverpod Providers

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/providers/supabase_provider.dart';
import '../../../auth/domain/providers/auth_provider.dart';
import '../../../chat/domain/providers/chat_provider.dart';
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

/// 按状态过滤的团购券列表（derived provider）
/// unused: 未使用且未过期
/// used: 已核销
/// expired: 已过期（含过期后退款的 "Expired Return"）
/// returned: 未过期就退款的
/// cancelled: 已作废 (voided)
/// 注：待评价 / 已提交评价见 My Coupons → Reviews（toReviewProvider / myWrittenReviewsProvider）
final couponsByStatusProvider =
    Provider.family<AsyncValue<List<CouponModel>>, String>((ref, status) {
  return ref.watch(userCouponsProvider).whenData((coupons) {
    switch (status) {
      case 'unused':
        // 排除：已过期、已退款（refundedAt 有值或 customerStatus 为退款相关）、无 order_item 的孤儿券
        return coupons.where((c) =>
            c.status == 'unused' && !c.isExpired &&
            c.refundedAt == null && c.orderItemId != null &&
            (c.customerStatus == null || c.customerStatus == 'unused')).toList();
      case 'used':
        return coupons.where((c) => c.status == 'used').toList();
      case 'expired':
        // 已过期的：全部都是 Expired Return（过期自动退款）
        // 包含赠送出去但已过期的券（voided + gifted + 已过期）
        return coupons.where((c) =>
            c.isExpired && (c.status != 'voided' ||
            (c.status == 'voided' && c.voidReason == 'gifted'))).toList();
      case 'refunded':
        // 未过期就主动退款的
        return coupons.where((c) =>
            c.status == 'refunded' && !c.isExpired).toList();
      case 'gifted':
        // 赠送出去的券：order_items.customer_status == 'gifted'
        return coupons.where((c) => c.customerStatus == 'gifted').toList();
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

  /// 赠送给好友 — 调用 send-gift + 发送 chat 消息
  Future<bool> sendGiftToFriend({
    required String orderItemId,
    required String recipientUserId,
    String? giftMessage,
    required String dealTitle,
    String? dealImageUrl,
    String? merchantName,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      // 1. 调用 send-gift Edge Function（传 recipient_user_id）
      final result = await ref.read(couponsRepositoryProvider).sendGift(
            orderItemId: orderItemId,
            recipientUserId: recipientUserId,
            giftMessage: giftMessage,
          );

      // 2. 发送 chat 消息通知好友
      try {
        final userId =
            (await ref.read(currentUserProvider.future))?.id;
        if (userId != null) {
          final chatRepo = ref.read(chatRepositoryProvider);
          final convId =
              await chatRepo.getOrCreateDirectChat(userId, recipientUserId);
          await chatRepo.sendCouponMessage(convId, userId, {
            'gift_action': 'gift_sent',
            'gift_id': result['gift_id'],
            'deal_title': dealTitle,
            'deal_image_url': dealImageUrl,
            'merchant_name': merchantName,
            'gift_message': giftMessage,
          });
          // 刷新会话列表
          ref.invalidate(conversationsProvider);
        }
      } catch (e) {
        // chat 消息发送失败不阻断赠送流程
        debugPrint('[GiftNotifier] chat message failed: $e');
      }
    });
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

  /// 撤回好友赠送 — 调用 recall-gift + 发送 chat 撤回消息
  Future<bool> recallFriendGift({
    required String giftId,
    required String recipientUserId,
    required String dealTitle,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await ref.read(couponsRepositoryProvider).recallGift(giftId);

      // 发送 chat 撤回通知消息
      try {
        final userId =
            (await ref.read(currentUserProvider.future))?.id;
        if (userId != null) {
          final chatRepo = ref.read(chatRepositoryProvider);
          final convId =
              await chatRepo.getOrCreateDirectChat(userId, recipientUserId);
          await chatRepo.sendCouponMessage(convId, userId, {
            'gift_action': 'gift_recalled',
            'gift_id': giftId,
            'deal_title': dealTitle,
          });
          ref.invalidate(conversationsProvider);
        }
      } catch (e) {
        debugPrint('[GiftNotifier] recall chat message failed: $e');
      }
    });
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
